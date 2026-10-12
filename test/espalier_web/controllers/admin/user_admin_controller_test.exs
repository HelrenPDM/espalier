defmodule EspalierWeb.Admin.UserAdminControllerTest do
  @moduledoc """
  User administration of task 0015 (spec steps 4 and 19, bullets "User
  administration" and "Directory counters"; README section 8): the list
  pages 50 users and names provider keys without subjects (ASVS 15.3.1),
  the lookup takes the exact address in the body (ASVS 14.2.1), an
  invitation enqueues one mail job and answers 404 with
  `LOCAL_ACCOUNTS=false`, disabling deletes every token row (ASVS 7.4.2),
  admins end the sessions of one user or of all users (ASVS 7.4.5), the
  reset of decision D11 removes every factor, counter and token row in one
  transaction (ASVS 2.3.3), and the failure counter reset reaches the
  directory counters, which carry no `user_id`. Every change writes its
  `audit_events` row with actor and subject.
  """
  # put_setting/2 and the LDAP provider change the application environment.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import OpenApiSpex.TestAssertions

  alias Espalier.Accounts

  alias Espalier.Accounts.{
    ExternalIdentity,
    FailureCounter,
    FailureCounters,
    MailWorker,
    Scope,
    User
  }

  alias Espalier.Audit.AuditEvent
  alias Espalier.{LdapConnHelpers, Repo}
  alias EspalierWeb.ApiSpec

  setup %{conn: conn} do
    admin = user_with_role_fixture(:admin)
    {_authenticator, _passkey} = passkey_fixture(admin)
    %{admin: admin, conn: log_in_user(conn, admin), spec: ApiSpec.spec()}
  end

  # SELECT count(*) FROM users_tokens WHERE user_id = <id> (spec "Acceptance").
  defp token_count(user) do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM users_tokens WHERE user_id = $1", [
        Ecto.UUID.dump!(user.id)
      ])

    count
  end

  defp session_count do
    %{rows: [[count]]} =
      Repo.query!("SELECT count(*) FROM users_tokens WHERE context = 'session'")

    count
  end

  # The sum of passkeys, TOTP factors and recovery codes (spec "Acceptance").
  defp factor_count(user) do
    %{rows: [[count]]} =
      Repo.query!(
        """
        SELECT (SELECT count(*) FROM webauthn_credentials WHERE user_id = $1)
             + (SELECT count(*) FROM totp_factors WHERE user_id = $1)
             + (SELECT count(*) FROM recovery_codes WHERE user_id = $1)
        """,
        [Ecto.UUID.dump!(user.id)]
      )

    count
  end

  # The kinds of the mail jobs enqueued for `user`.
  defp mail_kinds(user) do
    for %Oban.Job{args: %{"kind" => kind, "user_id" => id}} <- all_enqueued(worker: MailWorker),
        id == user.id,
        do: kind
  end

  defp audit_events(action) do
    Repo.all(from e in AuditEvent, where: e.action == ^action, order_by: e.inserted_at)
  end

  # The one audit event of `action` on `subject` by `actor`.
  defp assert_audit(action, actor, subject) do
    assert [%AuditEvent{} = event] =
             Repo.all(
               from e in AuditEvent, where: e.action == ^action and e.subject_id == ^subject.id
             )

    assert event.actor_id == actor.id
    assert event.subject_type == "User"
    event
  end

  # A conn of `user` that has made one successful request, so that its
  # session cookie is set for the next one.
  defp signed_in(user) do
    conn = api_conn() |> log_in_user(user) |> get("/api/me/sessions")
    assert json_response(conn, 200)
    conn
  end

  defp next_answer(conn), do: conn |> next_request() |> get("/api/me/sessions")

  defp reserve(config, subject) do
    FailureCounters.reserve_directory(
      config.key,
      subject,
      config.failure_limit,
      config.lock_minutes
    )
  end

  describe "GET /api/admin/users" do
    test "pages 50 users per page in the order of creation", %{conn: conn, spec: spec} do
      for _ <- 1..55, do: user_fixture(%{password: nil})

      expected =
        Repo.all(from u in User, order_by: [asc: u.inserted_at, asc: u.id], select: u.id)

      total = length(expected)
      assert total > 50

      first = conn |> json_request(:get, "/api/admin/users") |> json_response(200)
      second = conn |> json_request(:get, "/api/admin/users?page=2") |> json_response(200)

      assert %{"page" => 1, "per_page" => 50, "total" => ^total} = first
      assert %{"page" => 2, "per_page" => 50, "total" => ^total} = second
      assert length(first["users"]) == 50
      assert length(second["users"]) == total - 50

      assert Enum.map(first["users"] ++ second["users"], & &1["id"]) == expected

      assert_schema(first, "AdminUserList", spec)
      assert_schema(second, "AdminUserList", spec)
    end

    test "an entry names roles, enrollment and provider keys, and no subject or address",
         %{conn: conn, admin: admin} do
      user = user_fixture(%{display_name: "Listed Person"})
      subject = "subject-#{System.unique_integer([:positive])}"
      external_identity_fixture(user, %{provider_key: "test", subject: subject})
      {:ok, _grant} = Accounts.grant_role(Scope.system(), user, :author)
      passkey_fixture(user)

      conn = json_request(conn, :get, "/api/admin/users")
      body = response(conn, 200)
      users = json_response(conn, 200)["users"]

      entry = Enum.find(users, &(&1["id"] == user.id))

      assert Map.keys(entry) |> Enum.sort() ==
               ~w(display_name enrolled grants id last_login_at provider_keys roles status)

      assert entry["display_name"] == "Listed Person"
      assert entry["status"] == "active"
      assert Enum.sort(entry["roles"]) == ["author", "learner"]
      assert entry["enrolled"] == true
      assert entry["provider_keys"] == ["test"]

      assert [%{"role" => "author", "source" => "manual", "provider_key" => nil}] =
               entry["grants"]

      admin_entry = Enum.find(users, &(&1["id"] == admin.id))
      assert admin_entry["provider_keys"] == []

      refute body =~ subject
      refute body =~ user.email
      refute body =~ admin.email
      refute body =~ "subject"
      refute body =~ "email"
    end

    test "answers 422 validation_failed for a page below 1", %{conn: conn} do
      conn = json_request(conn, :get, "/api/admin/users?page=0")
      assert json_response(conn, 422)["error"] == "validation_failed"
    end
  end

  describe "POST /api/admin/user-lookups" do
    test "returns the user with its grants for the exact address in any letter case",
         %{conn: conn, spec: spec} do
      user = user_fixture()
      {:ok, grant} = Accounts.grant_role(Scope.system(), user, :facilitator)

      bodies =
        for email <- [user.email, String.upcase(user.email), "  #{user.email} "] do
          response = json_request(conn, :post, "/api/admin/user-lookups", %{email: email})
          body = json_response(response, 200)
          assert body["id"] == user.id
          assert Enum.sort(body["roles"]) == ["facilitator", "learner"]

          assert [%{"id" => grant_id, "role" => "facilitator", "source" => "manual"}] =
                   body["grants"]

          assert grant_id == grant.id
          refute response(response, 200) =~ user.email
          assert get_resp_header(response, "cache-control") == ["no-store"]
          body
        end

      for body <- bodies, do: assert_schema(body, "AdminUser", spec)
    end

    test "answers 404 not_found for an unknown address", %{conn: conn} do
      conn = json_request(conn, :post, "/api/admin/user-lookups", %{email: unique_user_email()})
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "needs no recent second factor, because it changes no state", %{admin: admin} do
      user = user_fixture()
      eleven_minutes_ago = DateTime.add(DateTime.utc_now(:second), -11, :minute)
      conn = log_in_user(api_conn(), admin, %{mfa_at: eleven_minutes_ago})

      conn = json_request(conn, :post, "/api/admin/user-lookups", %{email: user.email})
      assert json_response(conn, 200)["id"] == user.id
    end
  end

  describe "POST /api/admin/users" do
    test "invites a local user, enqueues one mail job and answers 202",
         %{conn: conn, admin: admin, spec: spec} do
      email = unique_user_email()

      conn =
        json_request(conn, :post, "/api/admin/users", %{email: email, display_name: "New Person"})

      body = json_response(conn, 202)
      assert_schema(body, "Accepted", spec)
      assert body == %{"status" => "accepted"}

      user = Accounts.get_user_by_email(email)
      assert user.display_name == "New Person"
      assert [%Oban.Job{args: args}] = all_enqueued(worker: MailWorker)
      assert args == %{"kind" => "invitation", "user_id" => user.id}
      assert_audit("user.invited", admin, user)
    end

    test "answers 409 user_exists for an address with an account", %{conn: conn} do
      user = user_fixture()

      conn =
        json_request(conn, :post, "/api/admin/users", %{email: String.upcase(user.email)})

      assert json_response(conn, 409) == %{"error" => "user_exists"}
      assert all_enqueued(worker: MailWorker) == []
    end

    test "answers 404 not_found with LOCAL_ACCOUNTS=false", %{conn: conn} do
      put_setting(:local_accounts, false)
      email = unique_user_email()

      conn = json_request(conn, :post, "/api/admin/users", %{email: email})

      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert Accounts.get_user_by_email(email) == nil
      assert all_enqueued(worker: MailWorker) == []
    end

    test "answers 422 validation_failed for a body with an extra member", %{conn: conn} do
      conn =
        json_request(conn, :post, "/api/admin/users", %{
          email: unique_user_email(),
          role: "admin"
        })

      assert json_response(conn, 422)["error"] == "validation_failed"
      assert all_enqueued(worker: MailWorker) == []
    end
  end

  describe "POST /api/admin/users/:id/invitation" do
    test "sends a new invitation and records user.invitation_resent",
         %{conn: conn, admin: admin} do
      user = user_fixture()

      conn = json_request(conn, :post, "/api/admin/users/#{user.id}/invitation")

      assert json_response(conn, 202) == %{"status" => "accepted"}
      assert mail_kinds(user) == ["invitation"]
      assert_audit("user.invitation_resent", admin, user)
    end

    test "answers 409 not_invitable for an enrolled, a disabled and a federated user",
         %{conn: conn} do
      enrolled = user_fixture()
      passkey_fixture(enrolled)

      disabled =
        user_fixture() |> Ecto.Changeset.change(status: :disabled) |> Repo.update!()

      federated = user_fixture()
      external_identity_fixture(federated)

      for user <- [enrolled, disabled, federated] do
        response = json_request(conn, :post, "/api/admin/users/#{user.id}/invitation")
        assert json_response(response, 409) == %{"error" => "not_invitable"}
        assert mail_kinds(user) == []
      end

      assert audit_events("user.invitation_resent") == []
    end
  end

  describe "POST /api/admin/users/:id/disable" do
    test "deletes every token row of the user, whose next request answers 401",
         %{conn: conn, admin: admin, spec: spec} do
      user = user_fixture()
      target = signed_in(user)
      {_token, _session} = session_fixture(user)
      email_token_fixture(user, :recovery_email)
      assert token_count(user) == 3

      conn = json_request(conn, :post, "/api/admin/users/#{user.id}/disable")

      body = json_response(conn, 200)
      assert_schema(body, "AdminUser", spec)
      assert body["status"] == "disabled"
      assert token_count(user) == 0
      assert Accounts.get_user!(user.id).status == :disabled
      assert json_response(next_answer(target), 401) == %{"error" => "unauthenticated"}
      assert_audit("user.disabled", admin, user)
    end

    test "answers 409 own_account for the acting admin", %{conn: conn, admin: admin} do
      conn = json_request(conn, :post, "/api/admin/users/#{admin.id}/disable")

      assert json_response(conn, 409) == %{"error" => "own_account"}
      assert Accounts.get_user!(admin.id).status == :active
      assert token_count(admin) == 1
      assert audit_events("user.disabled") == []
    end
  end

  describe "DELETE /api/admin/users/:id/sessions" do
    test "ends the sessions of that user only", %{conn: conn, admin: admin} do
      user = user_fixture()
      target = signed_in(user)
      {_token, _session} = session_fixture(user)
      other = signed_in(user_fixture())

      conn = json_request(conn, :delete, "/api/admin/users/#{user.id}/sessions")

      assert response(conn, 204) == ""
      assert token_count(user) == 0
      assert json_response(next_answer(target), 401) == %{"error" => "unauthenticated"}
      assert json_response(next_answer(other), 200)
      assert token_count(admin) == 1

      event = assert_audit("sessions.ended", admin, user)
      assert event.details == %{"count" => 2}
    end
  end

  describe "DELETE /api/admin/sessions" do
    test "leaves no session row, including the acting admin's", %{conn: conn, admin: admin} do
      others = for _ <- 1..2, do: signed_in(user_fixture())
      assert session_count() == 3

      response = json_request(conn, :delete, "/api/admin/sessions")

      assert response(response, 204) == ""
      assert session_count() == 0

      for other <- others do
        assert json_response(next_answer(other), 401) == %{"error" => "unauthenticated"}
      end

      assert conn |> json_request(:get, "/api/admin/users") |> json_response(401) ==
               %{"error" => "unauthenticated"}

      assert [%AuditEvent{actor_id: actor_id, details: %{"count" => 3}}] =
               audit_events("sessions.ended_all")

      assert actor_id == admin.id
    end
  end

  describe "POST /api/admin/users/:id/reset-factors" do
    setup do
      user = user_fixture()
      passkey_fixture(user)
      totp_fixture(user)
      recovery_codes_fixture(user)
      {_token, _session} = session_fixture(user)
      email_token_fixture(user, :recovery_email)

      for _ <- 1..FailureCounters.disable_at(),
          do: FailureCounters.record_failure(user, :password)

      assert FailureCounters.check(user, :password) == :disabled
      %{user: user}
    end

    test "removes every factor, counter and token row of a local user and invites it again",
         %{conn: conn, admin: admin, user: user, spec: spec} do
      assert factor_count(user) > 0
      target = signed_in(user)

      conn =
        json_request(conn, :post, "/api/admin/users/#{user.id}/reset-factors", %{
          identity_verified: true
        })

      body = json_response(conn, 200)
      assert_schema(body, "AdminFactorResetResult", spec)
      assert body == %{"invitation_sent" => true}

      assert factor_count(user) == 0
      assert token_count(user) == 0
      assert Accounts.get_user!(user.id).hashed_password == nil
      assert FailureCounters.check(user, :password) == :ok

      assert %FailureCounter{consecutive_failures: 0, locked_until: nil, disabled_at: nil} =
               Repo.get_by!(FailureCounter, user_id: user.id, authenticator: :password)

      assert Enum.sort(mail_kinds(user)) == ["factors_reset", "invitation"]
      assert json_response(next_answer(target), 401) == %{"error" => "unauthenticated"}

      event = assert_audit("user.factors_reset", admin, user)
      assert event.details == %{"identity_verified" => true}
      assert_audit("user.invitation_resent", admin, user)
    end

    test "enqueues only factors_reset for a user with an external identity",
         %{conn: conn, admin: admin, user: user} do
      external_identity_fixture(user)

      conn =
        json_request(conn, :post, "/api/admin/users/#{user.id}/reset-factors", %{
          identity_verified: true
        })

      assert json_response(conn, 200) == %{"invitation_sent" => false}
      assert factor_count(user) == 0
      assert token_count(user) == 0
      assert mail_kinds(user) == ["factors_reset"]
      assert_audit("user.factors_reset", admin, user)
      assert audit_events("user.invitation_resent") == []
    end

    test "answers 422 identity_verification_required without identity_verified: true",
         %{conn: conn, user: user} do
      before = factor_count(user)

      for body <- [%{}, %{identity_verified: false}] do
        response = json_request(conn, :post, "/api/admin/users/#{user.id}/reset-factors", body)
        assert json_response(response, 422) == %{"error" => "identity_verification_required"}
      end

      assert factor_count(user) == before
      assert token_count(user) == 2
      assert FailureCounters.check(user, :password) == :disabled
      assert mail_kinds(user) == []
      assert audit_events("user.factors_reset") == []
    end

    test "answers 422 validation_failed for a body with an extra member",
         %{conn: conn, user: user} do
      conn =
        json_request(conn, :post, "/api/admin/users/#{user.id}/reset-factors", %{
          identity_verified: true,
          send_invitation: false
        })

      assert json_response(conn, 422)["error"] == "validation_failed"
      assert factor_count(user) > 0
    end

    test "answers 409 own_account for the acting admin", %{conn: conn, admin: admin} do
      conn =
        json_request(conn, :post, "/api/admin/users/#{admin.id}/reset-factors", %{
          identity_verified: true
        })

      assert json_response(conn, 409) == %{"error" => "own_account"}
      assert factor_count(admin) == 1
      assert token_count(admin) == 1
      assert audit_events("user.factors_reset") == []
    end
  end

  describe "POST /api/admin/users/:id/reset-failure-counters" do
    test "clears disabled_at on the counter rows with the user's user_id",
         %{conn: conn, admin: admin} do
      user = user_fixture()
      for _ <- 1..FailureCounters.disable_at(), do: FailureCounters.record_failure(user, :totp)
      for _ <- 1..5, do: FailureCounters.record_failure(user, :password)
      assert FailureCounters.check(user, :totp) == :disabled

      conn = json_request(conn, :post, "/api/admin/users/#{user.id}/reset-failure-counters")

      assert response(conn, 204) == ""

      for counter <- Repo.all(from c in FailureCounter, where: c.user_id == ^user.id) do
        assert %FailureCounter{consecutive_failures: 0, locked_until: nil, disabled_at: nil} =
                 counter
      end

      assert FailureCounters.check(user, :totp) == :ok
      assert_audit("user.failure_counters_reset", admin, user)
    end
  end

  describe "directory counters" do
    setup do
      config = LdapConnHelpers.put_ldap_provider()
      user = user_fixture()
      subject = Ecto.UUID.generate()

      identity =
        external_identity_fixture(user, %{
          provider_key: config.key,
          issuer: "ldap:" <> config.key,
          subject: subject
        })

      now = DateTime.utc_now(:second)

      # The row of a directory account: no user_id, the subject_hash of the
      # identity's hash input, disabled after the fiftieth failure.
      counter =
        Repo.insert!(%FailureCounter{
          authenticator: :ldap,
          provider_key: config.key,
          subject_hash:
            ExternalIdentity.hash_input(identity.issuer, identity.tenant_id, identity.subject),
          consecutive_failures: FailureCounters.disable_at(),
          disabled_at: now,
          user_id: nil
        })

      assert reserve(config, subject) == {:error, :counter_disabled}
      %{config: config, user: user, subject: subject, counter: counter}
    end

    test "reset-failure-counters deletes the directory counter",
         %{conn: conn, admin: admin, config: config, user: user, subject: subject} = context do
      conn = json_request(conn, :post, "/api/admin/users/#{user.id}/reset-failure-counters")

      assert response(conn, 204) == ""
      assert Repo.get(FailureCounter, context.counter.id) == nil
      assert {:ok, %{count: 1}} = reserve(config, subject)

      event = assert_audit("failure_counter.reset", admin, user)
      assert event.details == %{"provider_key" => config.key}
      assert_audit("user.failure_counters_reset", admin, user)
    end

    test "reset-factors deletes the directory counter",
         %{conn: conn, admin: admin, config: config, user: user, subject: subject} = context do
      conn =
        json_request(conn, :post, "/api/admin/users/#{user.id}/reset-factors", %{
          identity_verified: true
        })

      assert json_response(conn, 200) == %{"invitation_sent" => false}
      assert Repo.get(FailureCounter, context.counter.id) == nil
      assert {:ok, %{count: 1}} = reserve(config, subject)
      assert mail_kinds(user) == ["factors_reset"]

      event = assert_audit("failure_counter.reset", admin, user)
      assert event.details == %{"provider_key" => config.key}
      assert_audit("user.factors_reset", admin, user)
    end
  end

  describe "an unknown user id" do
    test "answers 404 not_found on every route with a user id", %{conn: conn} do
      id = Ecto.UUID.generate()

      for {method, path, body} <- [
            {:post, "/api/admin/users/#{id}/invitation", nil},
            {:post, "/api/admin/users/#{id}/disable", nil},
            {:delete, "/api/admin/users/#{id}/sessions", nil},
            {:post, "/api/admin/users/#{id}/reset-factors", %{identity_verified: true}},
            {:post, "/api/admin/users/#{id}/reset-failure-counters", nil}
          ] do
        response = json_request(conn, method, path, body)
        assert json_response(response, 404) == %{"error" => "not_found"}, path
      end
    end
  end
end
