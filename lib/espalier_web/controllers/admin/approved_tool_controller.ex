defmodule EspalierWeb.Admin.ApprovedToolController do
  @moduledoc """
  The approved tool list of the admin area (task 0015, step 2), generated
  with `mix phx.gen.json Policies ApprovedTool approved_tools ...
  --no-context --no-schema --no-scope --web Admin`. Reads pipe through
  `:admin`, changes through `:admin_write`. Every signed-in user reads the
  list through `GET /api/approved-tools` of task 0013.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Policies
  alias Espalier.Policies.ApprovedTool
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: approved tools"]

  @id [id: [in: :path, required: true, description: "The tool id.", schema: Fields.uuid()]]

  operation :index,
    summary: "List the approved tools",
    security: Responses.session(),
    responses:
      Map.merge(
        %{200 => {"The approved tool list", "application/json", Admin.ApprovedToolList}},
        Responses.errors(Responses.admin_read())
      )

  def index(conn, _params) do
    render(conn, :index, approved_tools: Policies.list_approved_tools())
  end

  operation :create,
    summary: "Add an approved tool",
    security: Responses.session_and_csrf(),
    request_body: {"The tool", "application/json", Admin.ApprovedToolRequest, required: true},
    responses:
      Map.merge(
        %{201 => {"The tool", "application/json", Admin.ApprovedTool}},
        Responses.errors(Responses.admin_write([{422, ["validation_failed"]}]))
      )

  def create(conn, _params) do
    %{approved_tool: approved_tool_params} = conn.body_params

    with {:ok, %ApprovedTool{} = approved_tool} <-
           Policies.create_approved_tool(conn.assigns.current_scope, approved_tool_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/admin/approved-tools/#{approved_tool}")
      |> render(:show, approved_tool: approved_tool)
    end
  end

  operation :show,
    summary: "Read an approved tool",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{200 => {"The tool", "application/json", Admin.ApprovedTool}},
        Responses.errors(
          Responses.admin_read([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def show(conn, %{id: id}) do
    approved_tool = Policies.get_approved_tool!(id)
    render(conn, :show, approved_tool: approved_tool)
  end

  operation :update,
    summary: "Change an approved tool",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body:
      {"The changed fields", "application/json", Admin.ApprovedToolUpdateRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The tool", "application/json", Admin.ApprovedTool}},
        Responses.errors(
          Responses.admin_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def update(conn, %{id: id}) do
    %{approved_tool: approved_tool_params} = conn.body_params
    approved_tool = Policies.get_approved_tool!(id)

    with {:ok, %ApprovedTool{} = approved_tool} <-
           Policies.update_approved_tool(
             conn.assigns.current_scope,
             approved_tool,
             approved_tool_params
           ) do
      render(conn, :show, approved_tool: approved_tool)
    end
  end

  operation :delete,
    summary: "Delete an approved tool",
    security: Responses.session_and_csrf(),
    parameters: @id,
    responses:
      Map.merge(
        %{204 => "The tool is deleted"},
        Responses.errors(
          Responses.admin_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def delete(conn, %{id: id}) do
    approved_tool = Policies.get_approved_tool!(id)

    with {:ok, %ApprovedTool{}} <-
           Policies.delete_approved_tool(conn.assigns.current_scope, approved_tool) do
      send_resp(conn, :no_content, "")
    end
  end
end
