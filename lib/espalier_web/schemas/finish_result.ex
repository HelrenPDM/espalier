defmodule EspalierWeb.Schemas.FinishResult do
  @moduledoc "The answer of `POST /api/auth/finish` (task 0006, README section 6.12)."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{ExternalNextStep, FinishSession}

  OpenApiSpex.schema(
    %{
      title: "FinishResult",
      description: "A next step, or the session payload without `next`.",
      oneOf: [ExternalNextStep, FinishSession]
    },
    struct?: false,
    derive?: false
  )
end
