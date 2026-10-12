defmodule EspalierWeb.Admin.CredentialAdminController do
  @moduledoc """
  The revocation of a credential by an admin (task 0015, step 6). Admins see
  no credential list (README section 10: "revoke only"); the admin receives
  the id from the holder, whose credential page `/me/credentials/:id`
  carries it, or from the `credential_id` of a webhook event.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Credentials
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, EmptyRequest, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: credentials"]

  operation :revoke,
    summary: "Revoke a credential",
    security: Responses.session_and_csrf(),
    parameters: [
      id: [in: :path, required: true, description: "The credential id.", schema: Fields.uuid()]
    ],
    request_body: {"No members", "application/json", EmptyRequest, required: false},
    responses:
      Map.merge(
        %{200 => {"The revoked credential", "application/json", Admin.RevokedCredential}},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["already_revoked"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def revoke(conn, %{id: id}) do
    scope = conn.assigns.current_scope

    with {:ok, credential} <- Credentials.get_any_credential(scope, id),
         {:ok, revoked} <- Credentials.revoke(scope, credential) do
      json(conn, %{
        id: revoked.id,
        qualification_code: credential.qualification.code,
        status: revoked.status
      })
    end
  end
end
