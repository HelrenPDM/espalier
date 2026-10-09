defmodule EspalierWeb.Me.LdapIdentityControllerTest do
  # POST /api/me/identities/ldap/:provider with the Mox client (task 0007,
  # steps 20 and 25). The provider list is an application setting, so the
  # module runs alone.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.LdapConnHelpers
  import Mox

  alias Espalier.Accounts.{ExternalIdentity, FailureCounter, MailWorker}
  alias Espalier.Repo

  setup :verify_on_exit!

  setup %{conn: conn} do
    put_ldap_provider()
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  defp link(conn, username, password \\ directory_password()) do
    api_request(conn, :post, "/api/me/identities/ldap/ldap", %{
      username: username,
      password: password
    })
  end

  defp identities(user) do
    Repo.all(from i in ExternalIdentity, where: i.user_id == ^user.id)
  end

  test "a correct password links the directory account", %{conn: conn, user: user} do
    erin = person("erin")
    stub_people([erin])
    ref = attach_security_events()

    conn = link(conn, "erin")
    assert json_response(conn, 200) == %{"status" => "linked"}

    assert_enqueued(
      worker: MailWorker,
      args: %{"kind" => "identity_linked", "user_id" => user.id, "provider_key" => "ldap"}
    )

    assert_received {^ref, %{name: :user_updated, change: "identity_linked", provider: "ldap"}}

    assert [identity] = identities(user)
    assert identity.issuer == "ldap:ldap"
    assert identity.subject == subject(erin)
    assert identity.directory_dn == dn(erin)
    assert identity.directory_upn == "erin@example.org"
    assert identity.directory_login == "erin"

    conn = link(conn, "erin")
    assert json_response(conn, 200) == %{"status" => "already_linked"}
  end

  test "a subject of another account answers 409 identity_in_use", %{conn: conn} do
    finn = person("finn")
    stub_people([finn])

    other = user_fixture()

    external_identity_fixture(other, %{
      provider_key: "ldap",
      issuer: "ldap:ldap",
      subject: subject(finn)
    })

    assert json_response(link(conn, "finn"), 409) == %{"error" => "identity_in_use"}
  end

  test "a second identity of the same provider answers 409", %{conn: conn, user: user} do
    stub_people([person("gil")])
    external_identity_fixture(user, %{provider_key: "ldap", issuer: "ldap:ldap"})

    assert json_response(link(conn, "gil"), 409) == %{"error" => "provider_already_linked"}
  end

  test "an older second factor answers 403 reauth_required", %{user: user} do
    conn =
      log_in_user(api_conn(), user, %{
        mfa_at: DateTime.add(DateTime.utc_now(:second), -11, :minute)
      })

    assert json_response(link(conn, "gil"), 403) == %{"error" => "reauth_required"}
  end

  test "a wrong password answers 401 and raises the counter of the subject", %{conn: conn} do
    hal = person("hal")
    stub_people([hal])

    assert json_response(link(conn, "hal", "a wrong password"), 401) ==
             %{"error" => "invalid_credentials"}

    assert [%FailureCounter{consecutive_failures: 1, provider_key: "ldap", user_id: nil}] =
             Repo.all(from c in FailureCounter, where: c.authenticator == :ldap)
  end

  test "after a link the account signs in through the directory only", %{conn: conn, user: user} do
    ivy = person("ivy")
    stub_people([ivy])
    {_factor, _secret} = totp_fixture(user)

    assert json_response(link(conn, "ivy"), 200) == %{"status" => "linked"}

    password =
      api_request(api_conn(), :post, "/api/auth/password", %{
        email: user.email,
        password: valid_user_password()
      })

    assert json_response(password, 401) == %{"error" => "invalid_credentials"}

    directory =
      api_request(api_conn(), :post, "/api/auth/ldap/ldap", %{
        username: "ivy",
        password: directory_password()
      })

    assert json_response(directory, 200) == %{"next" => "second_factor"}
  end
end
