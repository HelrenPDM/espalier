defmodule EspalierWeb.Admin.RoleGrantController do
  @moduledoc """
  Role grants of the admin area (task 0015, step 3). The list names the
  users who hold a grant beyond `learner` with role, source and provider key
  of each grant; one user is found by the exact address through
  `POST /api/admin/user-lookups`, because the encrypted display name cannot
  be searched (README section 6.9).

  `Accounts.grant_role/3` and `Accounts.revoke_role/3` of task 0004 change
  `manual` grants only and end every session of the affected user (README
  section 6.5). An `idp_claim` grant answers 409 `idp_claim` on delete, and
  a demo user answers 409 `demo_user`.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Accounts
  alias Espalier.Accounts.User
  alias EspalierWeb.Admin.UserAdminJSON
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Admin, Fields}

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: roles"]

  # The roles an admin grants, mapped without creating atoms.
  @roles %{
    "facilitator" => :facilitator,
    "author" => :author,
    "registrar" => :registrar,
    "analyst" => :analyst,
    "admin" => :admin
  }

  operation :index,
    summary: "List the users with role grants",
    security: Responses.session(),
    responses:
      Map.merge(
        %{200 => {"The users with grants", "application/json", Admin.GrantHolderList}},
        Responses.errors(Responses.admin_read())
      )

  def index(conn, _params) do
    with {:ok, entries} <- Accounts.list_grant_holders(conn.assigns.current_scope) do
      json(conn, UserAdminJSON.holders(%{entries: entries}))
    end
  end

  operation :create,
    summary: "Grant a role",
    description: "Ends every session of the user.",
    security: Responses.session_and_csrf(),
    request_body: {"The grant", "application/json", Admin.RoleGrantRequest, required: true},
    responses:
      Map.merge(
        %{201 => {"The grant", "application/json", Admin.RoleGrant}},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["demo_user"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def create(conn, _params) do
    %{user_id: user_id, role: role} = conn.body_params

    with %User{} = user <- Accounts.get_user(user_id) || {:error, :not_found},
         {:ok, grant} <-
           Accounts.grant_role(conn.assigns.current_scope, user, Map.fetch!(@roles, role)) do
      conn |> put_status(:created) |> json(UserAdminJSON.grant(grant))
    end
  end

  operation :delete,
    summary: "Revoke a manual grant",
    description: "Ends every session of the user. An `idp_claim` grant answers 409 `idp_claim`.",
    security: Responses.session_and_csrf(),
    parameters: [
      id: [in: :path, required: true, description: "The grant id.", schema: Fields.uuid()]
    ],
    responses:
      Map.merge(
        %{204 => "The grant is revoked"},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["idp_claim", "demo_user"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def delete(conn, %{id: id}) do
    scope = conn.assigns.current_scope

    with {:ok, {grant, user}} <- Accounts.get_role_grant(scope, id),
         :ok <- manual(grant),
         {:ok, _role} <- Accounts.revoke_role(scope, user, grant.role) do
      send_resp(conn, :no_content, "")
    end
  end

  defp manual(%{source: :manual}), do: :ok
  defp manual(%{source: :idp_claim}), do: {:error, :idp_claim}
end
