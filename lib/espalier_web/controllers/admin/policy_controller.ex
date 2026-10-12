defmodule EspalierWeb.Admin.PolicyController do
  @moduledoc """
  Policies of the admin area (task 0015, step 2), generated with
  `mix phx.gen.json Policies Policy policies ... --no-context --no-schema
  --no-scope --web Admin`. Reads pipe through `:admin`, changes through
  `:admin_write`. Every signed-in user reads the current versions through
  `GET /api/policies` of task 0013.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Policies
  alias Espalier.Policies.Policy
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: policies"]

  @id [id: [in: :path, required: true, description: "The policy id.", schema: Fields.uuid()]]

  operation :index,
    summary: "List the policies",
    security: Responses.session(),
    responses:
      Map.merge(
        %{200 => {"The policies", "application/json", Admin.PolicyList}},
        Responses.errors(Responses.admin_read())
      )

  def index(conn, _params) do
    render(conn, :index, policies: Policies.list_policies())
  end

  operation :create,
    summary: "Create a policy",
    security: Responses.session_and_csrf(),
    request_body: {"The policy", "application/json", Admin.PolicyRequest, required: true},
    responses:
      Map.merge(
        %{201 => {"The policy", "application/json", Admin.Policy}},
        Responses.errors(Responses.admin_write([{422, ["validation_failed"]}]))
      )

  def create(conn, _params) do
    %{policy: policy_params} = conn.body_params

    with {:ok, %Policy{} = policy} <-
           Policies.create_policy(conn.assigns.current_scope, policy_params) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/admin/policies/#{policy}")
      |> render(:show, policy: policy)
    end
  end

  operation :show,
    summary: "Read a policy",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{200 => {"The policy", "application/json", Admin.Policy}},
        Responses.errors(
          Responses.admin_read([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def show(conn, %{id: id}) do
    policy = Policies.get_policy!(id)
    render(conn, :show, policy: policy)
  end

  operation :update,
    summary: "Change a policy",
    description: "A policy with a published version keeps its key (409 `policy_in_use`).",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body:
      {"The changed fields", "application/json", Admin.PolicyUpdateRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The policy", "application/json", Admin.Policy}},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["policy_in_use"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def update(conn, %{id: id}) do
    %{policy: policy_params} = conn.body_params
    policy = Policies.get_policy!(id)

    with {:ok, %Policy{} = policy} <-
           Policies.update_policy(conn.assigns.current_scope, policy, policy_params) do
      render(conn, :show, policy: policy)
    end
  end

  operation :delete,
    summary: "Delete a policy",
    description:
      "Deletes a policy together with its drafts. A policy with a published version " <>
        "answers 409 `policy_in_use`.",
    security: Responses.session_and_csrf(),
    parameters: @id,
    responses:
      Map.merge(
        %{204 => "The policy is deleted"},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["policy_in_use"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def delete(conn, %{id: id}) do
    policy = Policies.get_policy!(id)

    with {:ok, %Policy{}} <- Policies.delete_policy(conn.assigns.current_scope, policy) do
      send_resp(conn, :no_content, "")
    end
  end
end
