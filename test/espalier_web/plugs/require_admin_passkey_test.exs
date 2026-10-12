defmodule EspalierWeb.Plugs.RequireAdminPasskeyTest do
  @moduledoc """
  The passkey gate of task 0015 (step 1, README section 6.11): while
  `ADMIN_REQUIRE_PASSKEY` is true, an admin without a passkey receives 403
  `{"error":"passkey_required"}`, and the plug halts and logs `authz_fail`
  with the reason `passkey_required` (ASVS 8.2.1 and 16.3.2). An admin with
  a passkey passes, and while the setting is false every admin passes.
  """
  # put_setting/2 changes the application environment.
  use EspalierWeb.ConnCase, async: false

  import Espalier.CredentialsFixtures

  alias Espalier.Accounts
  alias Espalier.Accounts.Scope
  alias EspalierWeb.Plugs.RequireAdminPasskey

  # A conn with the scope of a signed-in session of `user`, as
  # fetch_current_scope_for_user/2 assigns it, after the plug ran.
  defp call_plug(user) do
    {_token, session} = session_fixture(user)
    scope = Scope.for_session(user, session, Accounts.list_role_grants(user))

    build_conn()
    |> assign(:current_scope, scope)
    |> RequireAdminPasskey.call(RequireAdminPasskey.init([]))
  end

  describe "while ADMIN_REQUIRE_PASSKEY is true" do
    setup do
      put_setting(:admin_require_passkey, true)
    end

    test "halts with 403 passkey_required and logs authz_fail for an admin without a passkey" do
      admin = user_with_role_fixture(:admin)
      # A passkey of another user does not open the gate.
      passkey_fixture(user_with_role_fixture(:admin))
      ref = attach_security_events()

      conn = call_plug(admin)

      assert conn.halted
      assert json_response(conn, 403) == %{"error" => "passkey_required"}
      admin_id = admin.id

      assert_received {^ref, %{name: :authz_fail, reason: "passkey_required", user_id: ^admin_id}}
    end

    test "passes an admin with a passkey and logs nothing" do
      admin = user_with_role_fixture(:admin)
      passkey_fixture(admin)
      ref = attach_security_events()

      conn = call_plug(admin)

      refute conn.halted
      assert conn.state == :unset
      assert conn.status == nil
      refute_received {^ref, %{name: :authz_fail}}
    end

    test "halts a conn without a signed-in user" do
      ref = attach_security_events()

      conn =
        build_conn()
        |> assign(:current_scope, nil)
        |> RequireAdminPasskey.call(RequireAdminPasskey.init([]))

      assert conn.halted
      assert json_response(conn, 403) == %{"error" => "passkey_required"}
      assert_received {^ref, %{name: :authz_fail, reason: "passkey_required"}}
    end
  end

  describe "while ADMIN_REQUIRE_PASSKEY is false" do
    setup do
      put_setting(:admin_require_passkey, false)
    end

    test "passes an admin without a passkey and logs nothing" do
      admin = user_with_role_fixture(:admin)
      ref = attach_security_events()

      conn = call_plug(admin)

      refute conn.halted
      assert conn.state == :unset
      refute_received {^ref, %{name: :authz_fail}}
    end
  end
end
