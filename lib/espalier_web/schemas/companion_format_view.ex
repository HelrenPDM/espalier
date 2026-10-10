defmodule EspalierWeb.Schemas.CompanionFormatView do
  @moduledoc """
  A companion format of the program view, so that the format evidence of an
  objective resolves to a title.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        id: Fields.uuid(),
        key: Fields.string(),
        title: Fields.string(),
        description: Fields.string(),
        phases: Fields.phases(),
        attendance_counts:
          Fields.boolean("True when an attendance certificate provides evidence.")
      }),
      %{title: "CompanionFormatView", description: "A format held outside the platform."}
    ),
    struct?: false,
    derive?: false
  )
end
