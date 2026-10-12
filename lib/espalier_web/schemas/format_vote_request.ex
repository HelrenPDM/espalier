defmodule EspalierWeb.Schemas.FormatVoteRequest do
  @moduledoc "The body of `POST /api/formats/{id}/votes`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{choice: Fields.enum(["would_use"], "The only choice of a vote.")}),
      %{
        title: "FormatVoteRequest",
        description: "An anonymous vote for a companion format; it cannot be changed afterwards."
      }
    ),
    struct?: false,
    derive?: false
  )
end
