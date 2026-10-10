defmodule EspalierWeb.Schemas.ObjectiveView do
  @moduledoc """
  A learning objective of a module view (README section 7, domain rule 14)
  with its teaching lessons and its evidence.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, ObjectiveEvidence}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        key: Fields.string(),
        statement: Fields.string(),
        area: Fields.enum(~w(subject method self social), "The CORE competence area."),
        depth: Fields.enum(~w(know apply judge)),
        phase: Fields.phase(),
        domain: Fields.nullable_string("One of the module's content domains."),
        lesson_ids: Fields.uuids("The teaching lessons, in lesson position order."),
        evidence:
          Fields.array(
            ObjectiveEvidence,
            "The evidence items ordered by key, followed by the evidence formats ordered by key."
          )
      }),
      %{title: "ObjectiveView", description: "A learning objective of the topic."}
    ),
    struct?: false,
    derive?: false
  )
end
