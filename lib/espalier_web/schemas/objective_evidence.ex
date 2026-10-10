defmodule EspalierWeb.Schemas.ObjectiveEvidence do
  @moduledoc """
  A piece of evidence of a learning objective: an item of the program or a
  companion format whose attendance counts (task 0008, step 13).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        kind: Fields.enum(~w(item format)),
        id: Fields.uuid("The id of the item or of the companion format.")
      }),
      %{title: "ObjectiveEvidence", description: "An item or a format that shows the objective."}
    ),
    struct?: false,
    derive?: false
  )
end
