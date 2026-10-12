defmodule EspalierWeb.Admin.PolicyVersionController do
  @moduledoc """
  Drafts and publication of policy versions (task 0015, step 3). Drafts are
  created through `Policies.create_version/3` of task 0013 and changed
  through `Policies.update_version/3`; `publish` stores `requires_refresher`
  and publishes in one transaction (`Policies.publish_draft/3`, ASVS 2.3.3).

  A published version answers 409 `published` to every change, and a draft
  whose policy has a published version with a higher number answers the
  publish with 409 `superseded`. `GET /api/admin/policy-versions/:id`
  carries `refresh_due_count`, the credentials that a publication with
  `requires_refresher` would move to `refresh_due` now.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.{Credentials, Policies}
  alias EspalierWeb.Admin.PolicyVersionJSON
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: policies"]

  @id [id: [in: :path, required: true, description: "The version id.", schema: Fields.uuid()]]

  operation :index,
    summary: "List the versions of a policy",
    security: Responses.session(),
    parameters: [
      policy_id: [in: :query, required: true, description: "The policy.", schema: Fields.uuid()]
    ],
    responses:
      Map.merge(
        %{200 => {"The versions", "application/json", Admin.PolicyVersionList}},
        Responses.errors(
          Responses.admin_read([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def index(conn, %{policy_id: policy_id}) do
    policy = Policies.get_policy!(policy_id)

    with {:ok, versions} <- Policies.list_versions(conn.assigns.current_scope, policy) do
      json(conn, PolicyVersionJSON.index(%{versions: versions}))
    end
  end

  operation :show,
    summary: "Read a policy version",
    security: Responses.session(),
    parameters: @id,
    responses:
      Map.merge(
        %{200 => {"The version", "application/json", Admin.PolicyVersion}},
        Responses.errors(
          Responses.admin_read([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def show(conn, %{id: id}) do
    with {:ok, version} <- Policies.get_version(conn.assigns.current_scope, id) do
      render_version(conn, version)
    end
  end

  operation :create,
    summary: "Create a draft version",
    security: Responses.session_and_csrf(),
    request_body: {"The draft", "application/json", Admin.PolicyVersionRequest, required: true},
    responses:
      Map.merge(
        %{201 => {"The draft", "application/json", Admin.PolicyVersion}},
        Responses.errors(
          Responses.admin_write([{404, ["not_found"]}, {422, ["validation_failed"]}])
        )
      )

  def create(conn, _params) do
    {policy_id, attrs} = Map.pop!(conn.body_params, :policy_id)
    scope = conn.assigns.current_scope
    policy = Policies.get_policy!(policy_id)

    with {:ok, version} <- Policies.create_version(scope, policy, attrs),
         {:ok, version} <- Policies.get_version(scope, version.id) do
      conn
      |> put_status(:created)
      |> put_resp_header("location", ~p"/api/admin/policy-versions/#{version}")
      |> render_version(version)
    end
  end

  operation :update,
    summary: "Change a draft",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body:
      {"The changed fields", "application/json", Admin.PolicyVersionUpdateRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The draft", "application/json", Admin.PolicyVersion}},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["published"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def update(conn, %{id: id}) do
    scope = conn.assigns.current_scope

    with {:ok, version} <- Policies.get_version(scope, id),
         {:ok, version} <- Policies.update_version(scope, version, conn.body_params) do
      render_version(conn, version)
    end
  end

  operation :publish,
    summary: "Publish a draft",
    description:
      "Stores `requires_refresher` and publishes in one transaction. A published version " <>
        "answers 409 `published`, a draft below a published version 409 `superseded`.",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body:
      {"The publication", "application/json", Admin.PolicyVersionPublishRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The published version", "application/json", Admin.PolicyVersion}},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["published", "superseded"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def publish(conn, %{id: id}) do
    %{requires_refresher: requires_refresher} = conn.body_params
    scope = conn.assigns.current_scope

    with {:ok, version} <- Policies.get_version(scope, id),
         {:ok, published} <- Policies.publish_draft(scope, version, requires_refresher),
         {:ok, published} <- Policies.get_version(scope, published.id) do
      render_version(conn, published)
    end
  end

  defp render_version(conn, version) do
    count = Credentials.count_affected_by_policy(version.policy.key)
    json(conn, PolicyVersionJSON.show(%{version: version, refresh_due_count: count}))
  end
end
