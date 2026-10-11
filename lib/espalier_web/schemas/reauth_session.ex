defmodule EspalierWeb.Schemas.ReauthSession do
  @moduledoc """
  The answer of `POST /api/me/reauth` (task 0005): the payload of the
  reissued session and the end of the recent-auth window.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, SessionPayload}

  OpenApiSpex.schema(
    SessionPayload.with_members(
      "ReauthSession",
      "The reissued session after a re-authentication.",
      %{recent_auth_until: Fields.datetime("The end of the 10-minute window.")}
    ),
    struct?: false,
    derive?: false
  )
end
