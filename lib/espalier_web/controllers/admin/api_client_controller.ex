defmodule EspalierWeb.Admin.ApiClientController do
  @moduledoc """
  Machine clients of the integration API (task 0015, step 3). The token of
  a new client appears once in the 201 answer; the table stores its
  SHA-256 hash (`Accounts.create_api_client/2` of task 0004), and every
  answer under `/api/admin` carries `cache-control: no-store` (ASVS 14.3.2).
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Accounts
  alias Espalier.Accounts.ApiClient
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: API clients"]

  operation :index,
    summary: "List the API clients",
    security: Responses.session(),
    responses:
      Map.merge(
        %{200 => {"The clients", "application/json", Admin.ApiClientList}},
        Responses.errors(Responses.admin_read())
      )

  def index(conn, _params) do
    with {:ok, clients} <- Accounts.list_api_clients(conn.assigns.current_scope) do
      json(conn, %{clients: Enum.map(clients, &client/1)})
    end
  end

  operation :create,
    summary: "Create an API client",
    description: "The answer carries the token once.",
    security: Responses.session_and_csrf(),
    request_body: {"The client", "application/json", Admin.ApiClientRequest, required: true},
    responses:
      Map.merge(
        %{201 => {"The client with its token", "application/json", Admin.ApiClientCreated}},
        Responses.errors(Responses.admin_write([{422, ["validation_failed"]}]))
      )

  def create(conn, _params) do
    with {:ok, {client, token}} <-
           Accounts.create_api_client(conn.assigns.current_scope, conn.body_params) do
      conn |> put_status(:created) |> json(%{client: client(client), token: token})
    end
  end

  operation :delete,
    summary: "Delete an API client",
    security: Responses.session_and_csrf(),
    parameters: [
      id: [in: :path, required: true, description: "The client id.", schema: Fields.uuid()]
    ],
    responses:
      Map.merge(
        %{204 => "The client is deleted"},
        Responses.errors(
          Responses.admin_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def delete(conn, %{id: id}) do
    scope = conn.assigns.current_scope

    with {:ok, client} <- Accounts.get_api_client(scope, id),
         {:ok, _client} <- Accounts.delete_api_client(scope, client) do
      send_resp(conn, :no_content, "")
    end
  end

  defp client(%ApiClient{} = client) do
    %{
      id: client.id,
      name: client.name,
      scopes: client.scopes,
      inserted_at: client.inserted_at,
      last_used_at: client.last_used_at
    }
  end
end
