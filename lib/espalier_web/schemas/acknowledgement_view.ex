defmodule EspalierWeb.Schemas.AcknowledgementView do
  @moduledoc "The answer of `POST /api/policy-versions/{id}/acknowledgements`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{policy_version_id: Fields.uuid(), acknowledged_at: Fields.datetime()}),
      %{
        title: "AcknowledgementView",
        description: "The acknowledgement of a policy version by the signed-in user."
      }
    ),
    struct?: false,
    derive?: false
  )
end
