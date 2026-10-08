defmodule Espalier.Accounts.AdminTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures

  alias Espalier.Accounts
  alias Espalier.Accounts.{ApiClient, Scope, UserToken}
  alias Espalier.Audit
  alias Espalier.Audit.AuditEvent

  setup do
    admin = user_fixture()
    {:ok, _grant} = Accounts.grant_role(Scope.system(), admin, :admin)
    {_token, session} = session_fixture(admin)
    scope = Scope.for_session(admin, session, Accounts.list_role_grants(admin))
    %{admin: scope, learner: user_scope_fixture()}
  end

  test "every administrative function requires admin", %{learner: learner} do
    user = user_fixture()
    assert Accounts.disable_user(learner, user) == {:error, :forbidden}
    assert Accounts.end_user_sessions(learner, user) == {:error, :forbidden}
    assert Accounts.end_all_sessions(learner) == {:error, :forbidden}

    assert Accounts.create_api_client(learner, %{name: "x", scopes: ["credentials:read"]}) ==
             {:error, :forbidden}

    assert Accounts.list_api_clients(learner) == {:error, :forbidden}
    assert Accounts.resend_invitation(learner, user) == {:error, :forbidden}
    assert Audit.list_events(learner) == {:error, :forbidden}
  end

  test "disable_user/2 ends every session and blocks the sign-in", %{admin: admin} do
    user = user_fixture()
    {token, _session} = session_fixture(user)

    assert {:ok, disabled} = Accounts.disable_user(admin, user)
    assert disabled.status == :disabled
    assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
    assert Accounts.get_session_by_token(token) == {:error, :not_found}

    assert Accounts.authenticate_password(user.email, valid_user_password()) ==
             {:error, :invalid_credentials}

    assert {:ok, [%AuditEvent{actor_id: actor_id}]} =
             Audit.list_events(admin, %{action: "user.disabled"})

    assert actor_id == admin.user.id
  end

  test "end_user_sessions/2 and end_all_sessions/1", %{admin: admin} do
    user = user_fixture()
    {a, _} = session_fixture(user)
    {b, _} = session_fixture(user)
    {other, _} = session_fixture(user_fixture())

    assert {:ok, 2} = Accounts.end_user_sessions(admin, user)
    assert Accounts.get_session_by_token(a) == {:error, :not_found}
    assert Accounts.get_session_by_token(b) == {:error, :not_found}
    assert {:ok, _user, _session} = Accounts.get_session_by_token(other)

    assert {:ok, count} = Accounts.end_all_sessions(admin)
    assert count >= 2
    assert Repo.all(from t in UserToken, where: t.context == :session) == []

    assert {:ok, [%AuditEvent{details: %{"count" => ^count}}]} =
             Audit.list_events(admin, %{action: "sessions.ended_all"})
  end

  test "API clients show the 32-byte token once and store its SHA-256 hash", %{admin: admin} do
    assert {:ok, {client, token}} =
             Accounts.create_api_client(admin, %{name: "Registry", scopes: ["credentials:read"]})

    bytes = Base.url_decode64!(token, padding: false)
    assert byte_size(bytes) == 32
    assert client.token_hash == :crypto.hash(:sha256, bytes)
    assert Accounts.get_api_client_by_token(token).id == client.id
    assert Accounts.get_api_client_by_token("not valid!") == nil
    refute inspect(client) =~ Base.encode16(client.token_hash)

    assert {:error, changeset} =
             Accounts.create_api_client(admin, %{name: "Other", scopes: ["admin:write"]})

    assert %{scopes: [_]} = errors_on(changeset)

    assert {:ok, [%ApiClient{}]} = Accounts.list_api_clients(admin)
    assert {:ok, _client} = Accounts.delete_api_client(admin, client)
    assert Accounts.get_api_client_by_token(token) == nil
  end

  test "resend_invitation/2 enqueues an invitation only for an invitable user", %{admin: admin} do
    invited = unconfirmed_user_fixture()
    assert :ok = Accounts.resend_invitation(admin, invited)

    assert_enqueued(
      worker: Accounts.MailWorker,
      args: %{"kind" => "invitation", "user_id" => invited.id}
    )

    federated = user_fixture()
    external_identity_fixture(federated)
    assert Accounts.resend_invitation(admin, federated) == {:error, :not_invitable}
  end
end
