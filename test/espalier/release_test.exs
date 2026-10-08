defmodule Espalier.ReleaseTest do
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures
  import ExUnit.CaptureIO

  alias Espalier.{Accounts, Release}

  setup do
    oban = Application.fetch_env!(:espalier, Oban)
    on_exit(fn -> Application.put_env(:espalier, Oban, oban) end)
  end

  test "grant_role/2 grants a known role and refuses unknown roles and addresses" do
    user = user_fixture()

    capture_io(fn -> assert {:ok, _grant} = Release.grant_role("admin", user.email) end)
    assert :admin in Accounts.roles_for(user)

    capture_io(fn ->
      assert Release.grant_role("owner", user.email) == {:error, :unknown_role}
    end)

    capture_io(fn ->
      assert Release.grant_role("admin", "nobody@example.org") == {:error, :not_found}
    end)
  end

  test "invite_user/1 creates a user named after the local part and enqueues an invitation" do
    capture_io(fn -> assert {:ok, _user} = Release.invite_user("ada@example.org") end)
    user = Accounts.get_user_by_email("ada@example.org")
    assert user.display_name == "ada"

    assert_enqueued(
      worker: Accounts.MailWorker,
      args: %{"kind" => "invitation", "user_id" => user.id}
    )

    capture_io(fn -> assert :ok = Release.invite_user("ADA@example.org") end)
  end

  test "end_all_sessions/0 ends every session" do
    {token, _session} = session_fixture(user_fixture())
    capture_io(fn -> assert {:ok, _count} = Release.end_all_sessions() end)
    assert Accounts.get_session_by_token(token) == {:error, :not_found}
  end
end
