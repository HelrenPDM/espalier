defmodule EspalierWeb.Me.CredentialController do
  @moduledoc """
  The credentials of the signed-in user. Another user's credential answers
  404 (ASVS 8.2.2).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Credentials
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.CredentialJSON
  alias EspalierWeb.Schemas.{CredentialList, CredentialView, Fields}

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Credentials"]
  security Responses.session()

  operation :index,
    summary: "List the own credentials",
    responses:
      Map.merge(
        %{200 => {"The credentials", "application/json", CredentialList}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]}
        ])
      )

  def index(conn, _params) do
    scope = conn.assigns.current_scope

    json(
      conn,
      CredentialJSON.index(%{
        credentials: Credentials.list_credentials(scope),
        holder: scope.user
      })
    )
  end

  operation :show,
    summary: "Read an own credential",
    parameters: [
      id: [in: :path, required: true, description: "The credential id.", schema: Fields.uuid()]
    ],
    responses:
      Map.merge(
        %{200 => {"The credential", "application/json", CredentialView}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "cross_site_request"]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def show(conn, %{id: id}) do
    scope = conn.assigns.current_scope

    case Credentials.get_credential(scope, id) do
      nil -> {:error, :not_found}
      credential -> json(conn, CredentialJSON.show(%{credential: credential, holder: scope.user}))
    end
  end
end
