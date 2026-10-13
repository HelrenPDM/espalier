defmodule EspalierWeb.Schemas.Admin.PackDraftList do
  @moduledoc "The drafts of the pack workbench, newest change first (task 0016a, step 9)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{data: Fields.array(EspalierWeb.Schemas.Admin.PackDraft)}),
      %{title: "AdminPackDraftList", description: "The drafts, without files."}
    ),
    struct?: false,
    derive?: false
  )
end
