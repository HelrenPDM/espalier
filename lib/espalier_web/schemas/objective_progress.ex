defmodule EspalierWeb.Schemas.ObjectiveProgress do
  @moduledoc """
  The status of a learning objective, derived per request from the
  learner's own records (README section 7, domain rule 15). The SPA adds
  `practised` from its local practice state.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{key: Fields.string(), status: Fields.enum(~w(evidenced open))}),
      %{title: "ObjectiveProgress", description: "Whether the learner's records show evidence."}
    ),
    struct?: false,
    derive?: false
  )
end
