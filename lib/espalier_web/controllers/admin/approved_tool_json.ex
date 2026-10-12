defmodule EspalierWeb.Admin.ApprovedToolJSON do
  @moduledoc "The views of `EspalierWeb.Admin.ApprovedToolController` (task 0015), generated with `mix phx.gen.json`."
  alias Espalier.Policies.ApprovedTool

  @doc """
  Renders a list of approved_tools.
  """
  def index(%{approved_tools: approved_tools}) do
    %{data: for(approved_tool <- approved_tools, do: data(approved_tool))}
  end

  @doc """
  Renders a single approved_tool.
  """
  def show(%{approved_tool: approved_tool}) do
    %{data: data(approved_tool)}
  end

  defp data(%ApprovedTool{} = approved_tool) do
    %{
      id: approved_tool.id,
      name: approved_tool.name,
      vendor: approved_tool.vendor,
      status: approved_tool.status,
      conditions: approved_tool.conditions,
      reviewed_on: approved_tool.reviewed_on,
      position: approved_tool.position
    }
  end
end
