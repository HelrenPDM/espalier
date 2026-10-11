defmodule EspalierWeb.Schemas.FinishSession do
  @moduledoc """
  The session answer of `POST /api/auth/finish` (task 0006, README section
  6.12): a full session, a step-up, or a link with `linked: true`.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, SessionPayload}

  OpenApiSpex.schema(
    SessionPayload.with_members(
      "FinishSession",
      "The session after an OIDC sign-in, step-up or link.",
      %{linked: %{Fields.boolean("Only after a link: `true`.") | enum: [true]}},
      [:linked]
    ),
    struct?: false,
    derive?: false
  )
end
