defmodule Espalier.Policies.DemoTest do
  @moduledoc """
  The demo seed of task 0013 (spec step 9): `Espalier.Policies.Demo.seed/0`
  inserts `usage-policy` with one published version and three approved
  tools, skips every row whose policy key or tool name exists, and lets the
  demo learner reach the credential `basics`; `mix espalier.seed_demo` runs
  it.
  """
  # The Mix task test replaces the Mix shell, which the whole node shares.
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Accounts.Scope
  alias Espalier.Policies
  alias Espalier.Policies.{ApprovedTool, Demo, Policy, PolicyVersion}
  alias Mix.Tasks.Espalier.SeedDemo

  @key "usage-policy"

  test "the policy key is usage-policy" do
    assert Demo.policy_key() == @key
  end

  test "seed inserts usage-policy with one published version and three approved tools" do
    assert {:ok, %{policies: 1, tools: 3}} = Demo.seed()

    policy = Policies.get_policy_by_key(@key)
    assert [version] = Repo.all(from v in PolicyVersion, where: v.policy_id == ^policy.id)
    assert version.number == 1
    assert %DateTime{} = version.published_at
    assert version.requires_refresher == false
    assert String.trim(version.body) != ""
    assert Policies.current_version(@key).id == version.id

    tools = Policies.list_approved_tools()
    assert length(tools) == 3
    assert tools |> Enum.map(& &1.name) |> Enum.uniq() |> length() == 3
    assert Enum.map(tools, & &1.position) == Enum.sort(Enum.map(tools, & &1.position))
  end

  test "a second seed inserts nothing and changes no row" do
    {:ok, _counts} = Demo.seed()

    # Explicit past timestamps, so that an update within the same second shows.
    past = ~U[2026-01-01 00:00:00Z]

    for schema <- [Policy, PolicyVersion, ApprovedTool] do
      Repo.update_all(schema, set: [inserted_at: past, updated_at: past])
    end

    before = snapshot()

    assert {:ok, %{policies: 0, tools: 0}} = Demo.seed()
    assert snapshot() == before
  end

  test "seed skips an existing policy key and keeps its row" do
    existing = policy_fixture(%{key: @key, title: "An existing usage policy"})

    assert {:ok, %{policies: 0, tools: 3}} = Demo.seed()

    assert Repo.all(from p in Policy, where: p.key == ^@key) == [existing]
    assert Repo.all(from v in PolicyVersion, where: v.policy_id == ^existing.id) == []
    assert Policies.current_version(@key) == nil
  end

  test "seed skips an existing tool name and keeps its row" do
    {:ok, _counts} = Demo.seed()
    [kept | others] = Policies.list_approved_tools()

    Repo.delete_all(from t in ApprovedTool, where: t.id in ^Enum.map(others, & &1.id))

    kept =
      kept
      |> Ecto.Changeset.change(vendor: "A vendor set by an admin", position: 9)
      |> Repo.update!()

    assert {:ok, %{policies: 0, tools: 2}} = Demo.seed()

    assert Repo.all(from t in ApprovedTool, where: t.name == ^kept.name) == [kept]
    assert Repo.aggregate(ApprovedTool, :count) == 3
  end

  test "after the demo import and the seed, the demo learner reaches the credential basics" do
    program = publish_demo!()
    {:ok, _counts} = Demo.seed()
    seeded = Policies.current_version(@key)
    scope = Scope.for_user(user_fixture())

    credential = qualify_basics!(scope, program)

    assert credential.status == :active
    assert credential.unlocks_snapshot == qualification!(program, "basics").unlocks
    assert Map.has_key?(Policies.acknowledged_at(scope, [seeded.id]), seeded.id)
    assert Policies.current_version(@key).id == seeded.id
  end

  describe "mix espalier.seed_demo" do
    setup do
      previous = Mix.shell()
      Mix.shell(Mix.Shell.Process)
      on_exit(fn -> Mix.shell(previous) end)
    end

    test "runs the seed and reports the new rows" do
      assert :ok = SeedDemo.run([])
      assert_received {:mix_shell, :info, [message]}
      assert message =~ ~r/\b1 polic/
      assert message =~ ~r/\b3 approved tools/

      assert %PolicyVersion{number: 1} = Policies.current_version(@key)
      assert length(Policies.list_approved_tools()) == 3

      assert :ok = SeedDemo.run([])
      assert_received {:mix_shell, :info, [message]}
      assert message =~ ~r/\b0 polic/
      assert message =~ ~r/\b0 approved tools/
    end
  end

  defp snapshot do
    for schema <- [Policy, PolicyVersion, ApprovedTool],
        do: Repo.all(from r in schema, order_by: r.id)
  end
end
