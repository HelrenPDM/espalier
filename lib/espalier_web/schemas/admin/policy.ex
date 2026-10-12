defmodule EspalierWeb.Schemas.Admin.Policy do
  @moduledoc """
  The answer of the policy routes of task 0015.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        data: Fields.object(%{id: Fields.uuid(), key: Fields.string(), title: Fields.string()})
      }),
      %{title: "AdminPolicy", description: "A policy."}
    ),
    struct?: false,
    derive?: false
  )
end
