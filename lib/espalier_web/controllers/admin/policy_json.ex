defmodule EspalierWeb.Admin.PolicyJSON do
  @moduledoc "The views of `EspalierWeb.Admin.PolicyController` (task 0015), generated with `mix phx.gen.json`."
  alias Espalier.Policies.Policy

  @doc """
  Renders a list of policies.
  """
  def index(%{policies: policies}) do
    %{data: for(policy <- policies, do: data(policy))}
  end

  @doc """
  Renders a single policy.
  """
  def show(%{policy: policy}) do
    %{data: data(policy)}
  end

  defp data(%Policy{} = policy) do
    %{
      id: policy.id,
      key: policy.key,
      title: policy.title
    }
  end
end
