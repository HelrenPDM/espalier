defmodule Espalier.Accounts.DemoTest do
  use Espalier.DataCase, async: true

  alias Espalier.Accounts
  alias Espalier.Accounts.{Demo, ExternalIdentity, Scope}

  test "get_or_create_user/1 returns the same user and keeps one identity per slot" do
    assert {:ok, user} = Demo.get_or_create_user(1)
    assert {:ok, again} = Demo.get_or_create_user(1)
    assert again.id == user.id
    assert user.display_name == "Test person 1"
    assert user.locale == "en"
    assert is_nil(user.email)

    identity =
      Repo.get_by(ExternalIdentity,
        provider_key: "demo",
        subject_hash: ExternalIdentity.hash_input("demo", nil, "slot-1")
      )

    assert identity.user_id == user.id
    assert identity.subject == "slot-1"
    assert Repo.aggregate(ExternalIdentity, :count) == 1
  end

  test "slots outside 1 to 20 are refused" do
    assert_raise FunctionClauseError, fn -> Demo.get_or_create_user(21) end
  end

  test "demo users hold only learner" do
    {:ok, user} = Demo.get_or_create_user(2)
    assert Accounts.grant_role(Scope.system(), user, :admin) == {:error, :demo_user}
    assert Accounts.roles_for(user) == [:learner]
  end
end
