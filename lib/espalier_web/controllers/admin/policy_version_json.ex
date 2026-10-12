defmodule EspalierWeb.Admin.PolicyVersionJSON do
  @moduledoc "The views of `EspalierWeb.Admin.PolicyVersionController` (task 0015)."

  alias Espalier.Policies.PolicyVersion

  @doc "Renders the versions of a policy."
  def index(%{versions: versions}), do: %{versions: Enum.map(versions, &data/1)}

  @doc "Renders one version with `refresh_due_count`."
  def show(%{version: version, refresh_due_count: count}) do
    version |> data() |> Map.put(:refresh_due_count, count)
  end

  defp data(%PolicyVersion{} = version) do
    %{
      id: version.id,
      policy_id: version.policy_id,
      policy_key: version.policy.key,
      policy_title: version.policy.title,
      number: version.number,
      body: version.body,
      effective_from: version.effective_from,
      published_at: version.published_at,
      requires_refresher: version.requires_refresher
    }
  end
end
