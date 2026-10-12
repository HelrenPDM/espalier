defmodule EspalierWeb.Schemas.Admin.FactorResetRequest do
  @moduledoc """
  The body of `POST /api/admin/users/{id}/reset-factors` (task 0015,
  decision D11).
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          identity_verified:
            Fields.boolean(
              "Must be true: the organization has verified the person's identity. " <>
                "Without it the route answers 422 identity_verification_required."
            )
        },
        optional: [:identity_verified]
      ),
      %{title: "AdminFactorResetRequest", description: "The confirmation of the identity check."}
    ),
    struct?: false,
    derive?: false
  )
end
