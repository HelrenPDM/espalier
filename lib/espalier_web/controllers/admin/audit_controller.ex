defmodule EspalierWeb.Admin.AuditController do
  @moduledoc """
  The audit log of the admin area (task 0015, step 8): pages of
  `Espalier.Audit.list_events/2`, newest first, 50 events per page,
  filtered by action and actor id. Each event names its actor by id and
  display name.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.{Accounts, Audit}
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, Fields}
  alias OpenApiSpex.Schema

  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: audit"]

  operation :index,
    summary: "List audit events",
    security: Responses.session(),
    parameters: [
      action: [
        in: :query,
        required: false,
        description: "An action, such as `user.disabled`.",
        schema: %Schema{type: :string, minLength: 1, maxLength: 100}
      ],
      actor_id: [in: :query, required: false, description: "An actor.", schema: Fields.uuid()],
      page: [
        in: :query,
        required: false,
        description: "The page, from 1; 50 events per page.",
        schema: %Schema{type: :integer, minimum: 1, maximum: 100_000}
      ]
    ],
    responses:
      Map.merge(
        %{200 => {"One page of events", "application/json", Admin.AuditEventList}},
        Responses.errors(Responses.admin_read([{422, ["validation_failed"]}]))
      )

  def index(conn, params) do
    scope = conn.assigns.current_scope
    page = Map.get(params, :page, 1)
    filters = %{action: params[:action], actor_id: params[:actor_id], page: page}

    with {:ok, events} <- Audit.list_events(scope, filters),
         {:ok, names} <- Accounts.display_names(scope, Enum.map(events, & &1.actor_id)) do
      json(conn, %{
        events:
          Enum.map(events, fn event ->
            %{
              id: event.id,
              at: event.at,
              action: event.action,
              actor_id: event.actor_id,
              actor_display_name: Map.get(names, event.actor_id),
              subject_type: event.subject_type,
              subject_id: event.subject_id,
              details: event.details
            }
          end),
        page: page,
        per_page: Audit.per_page()
      })
    end
  end
end
