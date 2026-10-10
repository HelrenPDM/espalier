defmodule EspalierWeb.Schemas.PasswordChangeRequest do
  @moduledoc """
  The body of `PUT /api/me/password` (README section 8). An enrollment or
  recovery session sets the password without `current_password`.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          current_password: Fields.request_string(128, "The current password."),
          password: %{
            Fields.request_string(128, "The new password, 15 to 128 code points after NFC.")
            | minLength: 15
          }
        },
        optional: [:current_password]
      ),
      %{title: "PasswordChangeRequest", description: "Changes the password."}
    ),
    struct?: false,
    derive?: false
  )
end
