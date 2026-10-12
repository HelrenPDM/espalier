defmodule EspalierWeb.Admin.WebhookController do
  @moduledoc """
  Webhooks of the admin area (task 0015, step 2), generated with
  `mix phx.gen.json Credentials Webhook webhooks ... --no-context
  --no-schema --no-scope --web Admin`. Reads pipe through `:admin`, changes
  through `:admin_write`.

  The `Webhook` changeset of task 0013 admits an `https` URL of a host and
  port in `WEBHOOK_ALLOWED_HOSTS` (422 with `host_not_allowed` on `url`
  otherwise), the four credential events and a `secret_env` with the prefix
  `WEBHOOK_SECRET_`. The controller also answers 422 `secret_env_unset` when
  the named variable is unset or empty, so that an admin sees a missing
  secret before the first delivery. An update checks a new `secret_env`, and
  the stored one while the webhook stays or becomes active, so that a webhook
  whose variable is gone can still be switched off.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Credentials
  alias Espalier.Credentials.Webhook
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: webhooks"]

  @id [id: [in: :path, required: true, description: "The webhook id.", schema: Fields.uuid()]]

  operation :index,
    summary: "List the webhooks",
    security: Responses.session(),
    responses:
      Map.merge(
        %{200 => {"The webhooks", "application/json", Admin.WebhookList}},
        Responses.errors(Responses.admin_read())
      )

  def index(conn, _params) do
    with {:ok, webhooks} <- Credentials.list_webhooks(conn.assigns.current_scope) do
      render(conn, :index, webhooks: webhooks)
    end
  end

  operation :create,
    summary: "Create a webhook",
    security: Responses.session_and_csrf(),
    request_body: {"The webhook", "application/json", Admin.WebhookRequest, required: true},
    responses:
      Map.merge(
        %{201 => {"The webhook", "application/json", Admin.Webhook}},
        Responses.errors(
          Responses.admin_write([{422, ["validation_failed", "secret_env_unset"]}])
        )
      )

  def create(conn, _params) do
    %{webhook: webhook_params} = conn.body_params

    with :ok <- check_secret(webhook_params[:secret_env]),
         {:ok, %Webhook{} = webhook} <-
           Credentials.create_webhook(conn.assigns.current_scope, webhook_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/admin/webhooks/#{webhook}")
      |> render(:show, webhook: webhook)
    end
  end

  operation :show,
    summary: "Read a webhook",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{200 => {"The webhook", "application/json", Admin.Webhook}},
        Responses.errors(
          Responses.admin_read([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def show(conn, %{id: id}) do
    with {:ok, webhook} <- Credentials.get_webhook(conn.assigns.current_scope, id) do
      render(conn, :show, webhook: webhook)
    end
  end

  operation :update,
    summary: "Change a webhook",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body:
      {"The changed fields", "application/json", Admin.WebhookUpdateRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The webhook", "application/json", Admin.Webhook}},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {422, ["validation_failed", "secret_env_unset"]}
          ])
        )
      )

  def update(conn, %{id: id}) do
    %{webhook: webhook_params} = conn.body_params
    scope = conn.assigns.current_scope

    with {:ok, webhook} <- Credentials.get_webhook(scope, id),
         :ok <- check_update_secret(webhook, webhook_params),
         {:ok, %Webhook{} = webhook} <-
           Credentials.update_webhook(scope, webhook, webhook_params) do
      render(conn, :show, webhook: webhook)
    end
  end

  operation :delete,
    summary: "Delete a webhook",
    security: Responses.session_and_csrf(),
    parameters: @id,
    responses:
      Map.merge(
        %{204 => "The webhook is deleted"},
        Responses.errors(
          Responses.admin_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def delete(conn, %{id: id}) do
    scope = conn.assigns.current_scope

    with {:ok, webhook} <- Credentials.get_webhook(scope, id),
         {:ok, %Webhook{}} <- Credentials.delete_webhook(scope, webhook) do
      send_resp(conn, :no_content, "")
    end
  end

  # Only names that the request schema admits (WEBHOOK_SECRET_*) reach this
  # check, so it never reads another variable of the environment.
  defp check_secret("WEBHOOK_SECRET_" <> _rest = name) do
    case System.get_env(name) do
      value when is_binary(value) and value != "" -> :ok
      _unset -> {:error, :secret_env_unset}
    end
  end

  defp check_secret(_name), do: :ok

  # An update checks a new secret_env, and the stored one while the webhook
  # stays or becomes active, so that an admin can always switch off a
  # webhook whose variable is gone.
  defp check_update_secret(_webhook, %{secret_env: name}), do: check_secret(name)

  defp check_update_secret(webhook, params) do
    if Map.get(params, :active, webhook.active), do: check_secret(webhook.secret_env), else: :ok
  end
end
