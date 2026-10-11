defmodule Espalier.Policies.Demo do
  @moduledoc """
  The demo seed of the Policies context (task 0013, step 9): the policy
  `usage-policy` with one published version and three approved tools. The
  text, the tool names and the vendors are invented for demonstration and
  describe no real organization or product.

  `seed/0` skips every policy whose key exists and every tool whose name
  exists, so it can run after each demo import. `mix espalier.seed_demo`
  calls it, and task 0017 wraps it as `Espalier.Release.seed_demo/0`.
  """

  import Ecto.Query, warn: false
  alias Espalier.Policies.{ApprovedTool, Policy, PolicyVersion}
  alias Espalier.Repo

  @policy_key "usage-policy"

  @body """
  This usage policy is invented for the demo program and describes no real
  organization.

  1. Use only the AI writing assistants of the approved tool list for work
     tasks.
  2. Enter no personal data and no confidential information into an
     assistant.
  3. Check every output against its sources before you use it, and mark
     text that an assistant drafted when you share it with your team.
  4. You remain responsible for every text you send or publish.
  """

  @tools [
    %{
      name: "Draftwell",
      vendor: "Example Software Ltd.",
      status: :approved,
      conditions: "Approved for internal drafts without personal data.",
      reviewed_on: ~D[2026-09-01],
      position: 1
    },
    %{
      name: "Summarix",
      vendor: "Sample Systems Inc.",
      status: :restricted,
      conditions: "Only for documents classified as public; summaries are checked before use.",
      reviewed_on: ~D[2026-09-01],
      position: 2
    },
    %{
      name: "OpenChat Free",
      vendor: "Placeholder Labs",
      status: :not_approved,
      conditions: "Not approved: the terms permit training on entered content.",
      reviewed_on: ~D[2026-09-01],
      position: 3
    }
  ]

  @doc "The key of the demo policy."
  def policy_key, do: @policy_key

  @doc """
  Inserts the demo policy with its published version and the demo tools,
  skipping every row whose policy key or tool name exists. Returns
  `{:ok, %{policies: count, tools: count}}` with the numbers of new rows.
  """
  def seed do
    Repo.transact(fn ->
      policies = if seed_policy(), do: 1, else: 0
      tools = Enum.count(@tools, &seed_tool/1)
      {:ok, %{policies: policies, tools: tools}}
    end)
  end

  defp seed_policy do
    if Repo.exists?(from p in Policy, where: p.key == ^@policy_key) do
      false
    else
      policy =
        %Policy{}
        |> Policy.changeset(%{key: @policy_key, title: "Usage policy for AI assistants"})
        |> Repo.insert!()

      %PolicyVersion{policy_id: policy.id, published_at: DateTime.utc_now(:second)}
      |> PolicyVersion.changeset(%{
        number: 1,
        body: @body,
        effective_from: ~D[2026-09-01],
        requires_refresher: false
      })
      |> Repo.insert!()

      true
    end
  end

  defp seed_tool(%{name: name} = attrs) do
    if Repo.exists?(from t in ApprovedTool, where: t.name == ^name) do
      false
    else
      %ApprovedTool{} |> ApprovedTool.changeset(attrs) |> Repo.insert!()
      true
    end
  end
end
