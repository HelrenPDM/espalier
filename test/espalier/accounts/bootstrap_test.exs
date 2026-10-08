defmodule Espalier.Accounts.BootstrapTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures
  import ExUnit.CaptureLog

  alias Espalier.Accounts
  alias Espalier.Accounts.{Bootstrap, MailWorker}

  test "an unknown address becomes a local admin with one invitation" do
    Bootstrap.run(["first-admin@example.org"])

    user = Accounts.get_user_by_email("first-admin@example.org")
    assert user.display_name == "first-admin"
    assert :admin in Accounts.roles_for(user)
    assert [%{args: %{"kind" => "invitation"}}] = all_enqueued(worker: MailWorker)
  end

  test "a matching local user receives the grant, also again at the next boot" do
    user = user_fixture()
    Bootstrap.run([user.email])
    assert :admin in Accounts.roles_for(user)

    {:ok, :admin} = Accounts.revoke_role(Accounts.Scope.system(), user, :admin)
    Bootstrap.run([String.upcase(user.email)])
    assert :admin in Accounts.roles_for(user)
  end

  test "a matching user with an external identity receives no grant and is logged" do
    user = user_fixture()
    external_identity_fixture(user)

    log = capture_log([level: :warning], fn -> Bootstrap.run([user.email]) end)
    assert log =~ user.id
    refute log =~ user.email
    assert Accounts.roles_for(user) == [:learner]
  end

  test "no account exists without an operator action" do
    Bootstrap.run([])
    assert Repo.aggregate(Accounts.User, :count) == 0
  end
end
