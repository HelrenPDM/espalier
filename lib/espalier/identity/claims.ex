defmodule Espalier.Identity.Claims do
  @moduledoc "Maps role claim values to platform roles (`AUTH_<KEY>_ROLE_MAP`)."

  @doc """
  Returns the platform roles whose mapped values appear in `values`, each
  once and in the order of the role map.
  """
  @spec map_roles([String.t()], [{atom(), String.t()}]) :: [atom()]
  def map_roles(values, role_map) when is_list(values) and is_list(role_map) do
    role_map
    |> Enum.filter(fn {_role, value} -> value in values end)
    |> Enum.map(fn {role, _value} -> role end)
    |> Enum.uniq()
  end
end
