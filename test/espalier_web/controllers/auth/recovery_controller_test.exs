defmodule EspalierWeb.Auth.RecoveryControllerTest do
  # put_rate_limit/2 changes the bucket map of the node.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query

  alias Espalier.Accounts.{FailureCounters, MailWorker, Recovery, RecoveryCodes, UserToken}
  alias Espalier.Repo
  alias Espalier.SoftAuthenticator

  setup do
    user = user_fixture()
    {authenticator, credential} = passkey_fixture(user)
    codes = recovery_codes_fixture(user)
    %{user: user, authenticator: authenticator, credential: credential, codes: codes}
  end

  defp start(conn, email),
    do: api_request(conn, :post, "/api/auth/recovery/start", %{email: email})

  defp verify(conn, token, code, opts \\ []) do
    api_request(
      conn,
      :post,
      "/api/auth/recovery/verify",
      %{token: token, recovery_code: code},
      opts
    )
  end

  # Runs the mail jobs and returns the token of the recovery link.
  defp mailed_token do
    Oban.drain_queue(queue: :mail)
    assert_received {:email, %Swoosh.Email{text_body: body} = email}
    assert body =~ "/recover#token="
    extract_link_token(email)
  end

  defp recovery_session(conn, user, code) do
    start(conn, user.email)
    conn = verify(conn, mailed_token(), code)
    assert json_response(conn, 200)["session"]["strength"] == "recovery"
    conn
  end

  test "the start answers the same for known and unknown addresses", %{conn: conn, user: user} do
    without_codes = user_fixture()

    responses =
      for email <- [user.email, unique_user_email(), without_codes.email] do
        conn = start(conn, email)
        {conn.status, json_response(conn, 202)}
      end

    assert Enum.uniq(responses) == [{202, %{"status" => "accepted"}}]

    jobs = all_enqueued(worker: MailWorker)

    assert Enum.map(jobs, & &1.args["kind"]) |> Enum.sort() ==
             ["none", "recovery_instructions", "recovery_unavailable"]

    for job <- jobs, do: assert(Map.keys(job.args) -- ["kind", "user_id"] == [])
    refute Enum.any?(jobs, &(inspect(&1.args) =~ user.email))

    Oban.drain_queue(queue: :mail)
    assert_received {:email, first}
    assert_received {:email, second}
    refute_received {:email, _third}

    {[link_mail], [reset_mail]} = Enum.split_with([first, second], &(&1.text_body =~ "#token="))
    assert link_mail.to == [{"", user.email}]
    assert reset_mail.to == [{"", without_codes.email}]
    assert reset_mail.text_body =~ "administrator to reset"
    refute reset_mail.text_body =~ "http"
  end

  test "only the link of the latest request works", %{conn: conn, user: user, codes: [code | _]} do
    start(conn, user.email)
    first = mailed_token()
    start(conn, user.email)
    second = mailed_token()

    conn = verify(api_conn(), first, code)
    assert json_response(conn, 401) == %{"error" => "authentication_failed"}

    conn = verify(api_conn(), second, code)
    body = json_response(conn, 200)
    assert body["session"]["strength"] == "recovery"
    assert body["session"]["auth_methods"] == ["recovery_code", "email_code"]

    assert Repo.all(
             from t in UserToken, where: t.user_id == ^user.id and t.context == :recovery_email
           ) == []

    assert RecoveryCodes.remaining(user) == 9

    assert_enqueued(
      worker: MailWorker,
      args: %{"kind" => "recovery_used", "user_id" => user.id, "count" => 9}
    )
  end

  test "a wrong code fails, counts and leaves the token valid",
       %{conn: conn, user: user, codes: [code | _]} do
    start(conn, user.email)
    token = mailed_token()

    conn = verify(conn, token, "AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AA")
    assert json_response(conn, 401) == %{"error" => "authentication_failed"}

    assert Repo.get_by(Espalier.Accounts.FailureCounter, user_id: user.id).consecutive_failures ==
             1

    conn = verify(api_conn(), token, code)
    assert json_response(conn, 200)["session"]["strength"] == "recovery"
  end

  test "the eleventh verification for one user within 15 minutes answers 429",
       %{conn: conn, user: user} do
    put_rate_limit(:recovery_verify_user, {:timer.minutes(15), 10})
    start(conn, user.email)
    token = mailed_token()

    for _ <- 1..10 do
      conn = verify(api_conn(), token, "AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AA", ip: unique_ip())
      assert json_response(conn, 401)
    end

    conn = verify(api_conn(), token, "AAAA-AAAA-AAAA-AAAA-AAAA-AAAA-AA", ip: unique_ip())
    assert json_response(conn, 429) == %{"error" => "rate_limited"}
    assert [_seconds] = get_resp_header(conn, "retry-after")
  end

  test "a recovery session reaches only the enrollment routes",
       %{conn: conn, user: user, credential: credential, codes: [code | _]} do
    conn = recovery_session(conn, user, code)

    conn = api_request(conn, :delete, "/api/me/passkeys/#{credential.id}")
    assert json_response(conn, 403) == %{"error" => "enrollment_required"}

    conn = api_request(conn, :get, "/api/me/sessions")
    assert json_response(conn, 403) == %{"error" => "enrollment_required"}

    conn = api_request(conn, :get, "/api/me/security")
    assert json_response(conn, 200)["recovery_codes"]["remaining"] == 9
  end

  test "a passkey registration completes the recovery",
       %{conn: conn, user: user, codes: [code | earlier]} do
    session_fixture(user)
    session_fixture(user)
    conn = recovery_session(conn, user, code)

    conn = api_request(conn, :post, "/api/me/passkeys/options")
    options = json_response(conn, 200)
    authenticator = SoftAuthenticator.new() |> SoftAuthenticator.put_user_handle(options)

    conn =
      api_request(conn, :post, "/api/me/passkeys", %{
        credential: SoftAuthenticator.attest(authenticator, options),
        nickname: "Laptop"
      })

    body = json_response(conn, 200)
    assert length(body["recovery_codes"]) == 10
    assert body["session"]["session"]["strength"] == "mfa"

    assert body["session"]["session"]["auth_methods"] == [
             "recovery_code",
             "email_code",
             "passkey"
           ]

    assert body["passkey"]["nickname"] == "Laptop"
    assert body["other_sessions"] == 2

    for old <- earlier, do: assert(RecoveryCodes.use(user, old) == {:error, :invalid_code})
    assert RecoveryCodes.use(user, hd(body["recovery_codes"])) == {:ok, 9}
  end

  test "a TOTP confirmation completes the recovery and re-enables a disabled factor",
       %{conn: conn, user: user, codes: [code | _]} do
    totp_fixture(user)
    now = DateTime.utc_now()
    for _ <- 1..50, do: FailureCounters.record_failure(user, :totp, now)
    assert FailureCounters.check(user, :totp, now) == :disabled

    conn = recovery_session(conn, user, code)

    conn = api_request(conn, :post, "/api/me/totp")
    secret = json_response(conn, 200)["secret_base32"] |> Base.decode32!(padding: false)

    assert_enqueued(
      worker: MailWorker,
      args: %{"kind" => "factor_removed", "user_id" => user.id, "factor" => "totp"}
    )

    conn = api_request(conn, :post, "/api/me/totp/confirm", %{code: totp_code(secret)})
    body = json_response(conn, 200)
    assert body["session"]["session"]["auth_methods"] == ["recovery_code", "email_code", "totp"]
    assert body["session"]["session"]["strength"] == "mfa"
    assert length(body["recovery_codes"]) == 10
    assert body["totp"]["enabled"]

    assert FailureCounters.check(user, :totp, DateTime.utc_now()) == :ok
  end

  test "the recovery link lives 10 minutes", %{conn: conn, user: user, codes: [code | _]} do
    start(conn, user.email)
    token = mailed_token()

    assert {:ok, resolved, %UserToken{context: :recovery_email}} = Recovery.resolve_token(token)
    assert resolved.id == user.id

    assert {:ok, ^resolved, _row} =
             Recovery.resolve_token(token, DateTime.add(DateTime.utc_now(), 9, :minute))

    assert Recovery.resolve_token(token, DateTime.add(DateTime.utc_now(), 11, :minute)) == :error

    row = Repo.get_by!(UserToken, user_id: user.id, context: :recovery_email)
    assert_in_delta DateTime.diff(row.expires_at, DateTime.utc_now()), 600, 5

    Repo.update_all(from(t in UserToken, where: t.id == ^row.id),
      set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1)]
    )

    conn = verify(api_conn(), token, code)
    assert json_response(conn, 401) == %{"error" => "authentication_failed"}
  end

  test "of two concurrent verifications of one link exactly one opens a session",
       %{conn: conn, user: user, codes: [first, second | _]} do
    start(conn, user.email)
    {:ok, user, row} = Recovery.resolve_token(mailed_token())

    results =
      [first, second]
      |> Enum.map(fn code -> Task.async(fn -> Recovery.verify(user, row, code, %{}) end) end)
      |> Enum.map(&Task.await/1)

    assert [{:error, :invalid_token}, {:ok, 9}] = Enum.sort(results)
    assert RecoveryCodes.remaining(user) == 9
  end

  test "a job that runs after a newer request of the same user sends no link",
       %{conn: conn, user: user, codes: [code | _]} do
    start(conn, user.email)
    start(conn, user.email)

    [older, newer] =
      Repo.all(
        from j in Oban.Job, where: j.worker == "Espalier.Accounts.MailWorker", order_by: j.id
      )

    # The newer job runs first, as after a retry of the older one.
    assert :ok = MailWorker.perform(newer)
    assert_received {:email, newer_mail}
    assert :ok = MailWorker.perform(older)
    refute_received {:email, _older_mail}

    assert [_one] =
             Repo.all(
               from t in UserToken, where: t.user_id == ^user.id and t.context == :recovery_email
             )

    conn = verify(api_conn(), extract_link_token(newer_mail), code)
    assert json_response(conn, 200)["session"]["strength"] == "recovery"
  end

  test "a token of another context or a malformed request fails", %{conn: conn, user: user} do
    {invite, _row} = email_token_fixture(user, :invite)
    conn = verify(conn, invite, "AAAA")
    assert json_response(conn, 401) == %{"error" => "authentication_failed"}

    conn = api_request(api_conn(), :post, "/api/auth/recovery/verify", %{token: "x"})
    assert json_response(conn, 400) == %{"error" => "bad_request"}
  end
end
