defmodule Espalier.Accounts.RolesTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures

  alias Espalier.Accounts
  alias Espalier.Accounts.{RoleGrant, Scope}
  alias Espalier.Audit.AuditEvent

  setup do
    user = user_fixture()
    {token, _session} = session_fixture(user)
    %{user: user, token: token}
  end

  test "every user holds learner without a stored grant", %{user: user} do
    assert Accounts.roles_for(user) == [:learner]
    assert Scope.for_user(user).roles == [:learner]
  end

  test "grant_role/3 requires admin, writes an audit event and ends the sessions",
       %{user: user, token: token} do
    assert Accounts.grant_role(user_scope_fixture(), user, :author) == {:error, :forbidden}

    ref = attach_security_events()

    assert {:ok, %RoleGrant{role: :author, source: :manual}} =
             Accounts.grant_role(Scope.system(), user, :author)

    assert Accounts.roles_for(user) == [:learner, :author]

    assert [%AuditEvent{action: "role.granted", details: %{"role" => "author"}}] =
             Repo.all(AuditEvent)

    assert Accounts.get_session_by_token(token) == {:error, :not_found}
    assert_received {^ref, %{name: :privilege_permissions_changed}}
  end

  test "revoke_role/3 removes a manual grant and ends the sessions", %{user: user} do
    {:ok, _grant} = Accounts.grant_role(Scope.system(), user, :analyst)
    {token, _session} = session_fixture(user)

    assert {:ok, :analyst} = Accounts.revoke_role(Scope.system(), user, :analyst)
    assert Accounts.roles_for(user) == [:learner]
    assert Accounts.get_session_by_token(token) == {:error, :not_found}
    assert Accounts.revoke_role(Scope.system(), user, :analyst) == {:error, :not_found}
    assert Repo.exists?(from e in AuditEvent, where: e.action == "role.revoked")
  end

  describe "replace_idp_role_grants/3" do
    test "keeps manual grants and writes role.synced when the set changes",
         %{user: user, token: token} do
      {:ok, _grant} = Accounts.grant_role(Scope.system(), user, :facilitator)
      {token, _session} = session_fixture(user, replaces: token)

      assert {:ok, :changed} = Accounts.replace_idp_role_grants(user, "entra", [:author, :admin])
      assert Enum.sort(Accounts.roles_for(user)) == [:admin, :author, :facilitator, :learner]
      assert Accounts.get_session_by_token(token) == {:error, :not_found}

      assert %AuditEvent{details: details, actor_id: nil} =
               Repo.one(from e in AuditEvent, where: e.action == "role.synced")

      assert details == %{
               "provider_key" => "entra",
               "added" => ["admin", "author"],
               "removed" => []
             }

      assert [%RoleGrant{provider_key: "entra"}, %RoleGrant{provider_key: "entra"}] =
               Repo.all(from g in RoleGrant, where: g.source == :idp_claim)
    end

    test "an unchanged set writes nothing and keeps the sessions", %{user: user} do
      {:ok, :changed} = Accounts.replace_idp_role_grants(user, "entra", [:author])
      {token, _session} = session_fixture(user)
      events = Repo.aggregate(AuditEvent, :count)

      assert Accounts.replace_idp_role_grants(user, "entra", [:author]) == {:ok, :unchanged}
      assert {:ok, _user, _session} = Accounts.get_session_by_token(token)
      assert Repo.aggregate(AuditEvent, :count) == events
    end

    test "removes grants that the provider no longer sends", %{user: user} do
      {:ok, :changed} = Accounts.replace_idp_role_grants(user, "entra", [:author])
      assert {:ok, :changed} = Accounts.replace_idp_role_grants(user, "entra", [])
      assert Accounts.roles_for(user) == [:learner]
    end
  end

  test "Scope.for_session/3 always includes learner", %{user: user, token: token} do
    {:ok, _grant} = Accounts.grant_role(Scope.system(), user, :admin)
    {_token, session} = session_fixture(user, replaces: token)
    scope = Scope.for_session(user, session, Accounts.list_role_grants(user))
    assert scope.roles == [:learner, :admin]
    assert Scope.admin?(scope)
    refute Scope.has_role?(scope, :author)
  end
end
