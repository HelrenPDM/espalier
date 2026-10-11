defmodule EspalierWeb.Schemas.SecondFactorSession do
  @moduledoc """
  The answer of `POST /api/auth/second-factor` (task 0005): the session
  payload, and after a recovery code the number of codes left.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, SessionPayload}

  OpenApiSpex.schema(
    SessionPayload.with_members(
      "SecondFactorSession",
      "The full session after the second factor.",
      %{
        recovery_codes_remaining:
          Fields.integer("Only after a recovery code: the number of unused codes.")
      },
      [:recovery_codes_remaining]
    ),
    struct?: false,
    derive?: false
  )
end
