defmodule Espalier.Accounts.SessionStrengthTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures

  alias Espalier.Accounts

  setup do
    %{user: user_fixture()}
  end

  test "enrollment sessions start from an e-mail code, OIDC or LDAP", %{user: user} do
    for methods <- [[:email_code], [:oidc], [:ldap]] do
      {_token, session} =
        Accounts.create_session(user, %{auth_methods: methods, strength: :enrollment})

      assert session.strength == :enrollment
      assert session.auth_methods == methods
    end
  end

  test "a password never opens an enrollment session", %{user: user} do
    assert_raise ArgumentError, fn ->
      Accounts.create_session(user, %{auth_methods: [:password], strength: :enrollment})
    end
  end

  test "create_session/2 stores idp_amr", %{user: user} do
    {token, session} =
      Accounts.create_session(user, %{
        auth_methods: [:oidc, :idp_mfa],
        strength: :mfa,
        mfa_at: DateTime.utc_now(:second),
        idp_amr: ["pwd", "mfa"]
      })

    assert session.idp_amr == ["pwd", "mfa"]
    assert {:ok, _user, %{idp_amr: ["pwd", "mfa"]}} = Accounts.get_session_by_token(token)

    {:ok, reissued} = Accounts.reissue_session(token, %{mfa_at: DateTime.utc_now(:second)})
    assert {:ok, _user, %{idp_amr: ["pwd", "mfa"]}} = Accounts.get_session_by_token(reissued)
  end
end
