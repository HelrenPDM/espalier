defmodule EspalierWeb.PolicyJSON do
  @moduledoc """
  Views of the Policies context (task 0013). Every view names its members
  explicitly.
  """

  @doc "Renders the current versions with the acknowledgement of the user."
  def index(%{entries: entries}) do
    %{
      policies:
        Enum.map(entries, fn %{version: version, acknowledged_at: acknowledged_at} ->
          %{
            id: version.id,
            key: version.policy.key,
            title: version.policy.title,
            number: version.number,
            effective_from: version.effective_from,
            body: version.body,
            acknowledged_at: acknowledged_at
          }
        end)
    }
  end

  @doc "Renders an acknowledgement."
  def acknowledgement(%{acknowledgement: acknowledgement}) do
    %{
      policy_version_id: acknowledgement.policy_version_id,
      acknowledged_at: acknowledgement.acknowledged_at
    }
  end

  @doc "Renders the approved tool list."
  def tools(%{tools: tools}) do
    %{
      tools:
        Enum.map(tools, fn tool ->
          %{
            id: tool.id,
            name: tool.name,
            vendor: tool.vendor,
            status: tool.status,
            conditions: tool.conditions,
            reviewed_on: tool.reviewed_on,
            position: tool.position
          }
        end)
    }
  end
end
