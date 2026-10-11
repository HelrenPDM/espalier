defmodule EspalierWeb.Schemas.ExternalNextStep do
  @moduledoc """
  The next sign-in step after an OIDC or directory first factor (tasks
  0006 and 0007, README section 6.12): the second factor of an enrolled
  user, or the enrollment of a first second factor.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{next: Fields.enum(~w(second_factor enroll_second_factor))}),
      %{
        title: "ExternalNextStep",
        description:
          "`second_factor` opens the pending state; `enroll_second_factor` an enrollment " <>
            "session."
      }
    ),
    struct?: false,
    derive?: false
  )
end
