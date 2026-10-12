defmodule EspalierWeb.Admin.UserAdminController do
  @moduledoc """
  User administration (task 0015, step 4; README section 8). Every action
  passes the admin scope to `Espalier.Accounts`, whose functions write an
  audit event and a security event.

  The list pages by `inserted_at`, because the encrypted display name cannot
  be sorted in SQL, and the lookup takes the exact address in the JSON body
  (ASVS 14.2.1); no route takes an address in its URL. `disable` and
  `reset-factors` on the acting admin's own account answer 409
  `own_account`, so that no admin locks themselves out through the admin
  area; operators keep the release functions of task 0004.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Espalier.Accounts
  alias Espalier.Accounts.{Scope, User}
  alias EspalierWeb.Admin.UserAdminJSON
  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{Accepted, Admin, EmailLookupRequest, EmptyRequest, Fields}
  alias OpenApiSpex.Schema

  plug EspalierWeb.Plugs.JsonObjectBody
  plug OpenApiSpex.Plug.CastAndValidate, render_error: EspalierWeb.CastErrorRenderer
  action_fallback EspalierWeb.FallbackController

  tags ["Admin: users"]

  @id [id: [in: :path, required: true, description: "The user id.", schema: Fields.uuid()]]
  @not_found [{404, ["not_found"]}, {422, ["validation_failed"]}]

  operation :index,
    summary: "List the users",
    security: Responses.session(),
    parameters: [
      page: [
        in: :query,
        required: false,
        description: "The page, from 1; 50 users per page.",
        schema: %Schema{type: :integer, minimum: 1, maximum: 100_000}
      ]
    ],
    responses:
      Map.merge(
        %{200 => {"One page of users", "application/json", Admin.UserList}},
        Responses.errors(Responses.admin_read([{422, ["validation_failed"]}]))
      )

  def index(conn, params) do
    page = Map.get(params, :page, 1)

    with {:ok, %{entries: entries, total: total}} <-
           Accounts.list_users(conn.assigns.current_scope, page) do
      json(
        conn,
        UserAdminJSON.index(%{
          entries: entries,
          page: page,
          per_page: Accounts.users_per_page(),
          total: total
        })
      )
    end
  end

  operation :lookup,
    summary: "Find a user by e-mail address",
    description:
      "The address travels in the body, so no URL carries it. The route changes no state.",
    security: Responses.session_and_csrf(),
    request_body: {"The address", "application/json", EmailLookupRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The user with its grants", "application/json", Admin.User}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403,
           [
             "forbidden",
             "enrollment_required",
             "passkey_required",
             "csrf",
             "cross_site_request"
           ]},
          {404, ["not_found"]},
          {422, ["validation_failed"]}
        ])
      )

  def lookup(conn, _params) do
    %{email: email} = conn.body_params

    with {:ok, entry} <- Accounts.lookup_user(conn.assigns.current_scope, email) do
      json(conn, UserAdminJSON.user(entry))
    end
  end

  operation :create,
    summary: "Invite a local user",
    description:
      "Sends a single-use invitation link (10 minutes). With `LOCAL_ACCOUNTS=false` the " <>
        "route answers 404, because federated users are created at their first sign-in.",
    security: Responses.session_and_csrf(),
    request_body: {"The invitation", "application/json", Admin.UserInviteRequest, required: true},
    responses:
      Map.merge(
        %{202 => {"The invitation is queued", "application/json", Accepted}},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["user_exists"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def create(conn, _params) do
    if Application.get_env(:espalier, :local_accounts, true) do
      with {:ok, _user} <- Accounts.invite_user(conn.assigns.current_scope, conn.body_params) do
        conn |> put_status(:accepted) |> json(%{status: "accepted"})
      end
    else
      {:error, :not_found}
    end
  end

  operation :resend_invitation,
    summary: "Send a new invitation",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body: {"No members", "application/json", EmptyRequest, required: false},
    responses:
      Map.merge(
        %{202 => {"The invitation is queued", "application/json", Accepted}},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["not_invitable"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def resend_invitation(conn, %{id: id}) do
    with {:ok, user} <- fetch_user(id),
         :ok <- Accounts.resend_invitation(conn.assigns.current_scope, user) do
      conn |> put_status(:accepted) |> json(%{status: "accepted"})
    end
  end

  operation :disable,
    summary: "Disable a user",
    description: "Sets the status `disabled` and deletes every token row of the user.",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body: {"No members", "application/json", EmptyRequest, required: false},
    responses:
      Map.merge(
        %{200 => {"The user", "application/json", Admin.User}},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["own_account"]},
            {422, ["validation_failed"]}
          ])
        )
      )

  def disable(conn, %{id: id}) do
    scope = conn.assigns.current_scope

    with {:ok, user} <- fetch_user(id),
         :ok <- not_own_account(scope, user),
         {:ok, user} <- Accounts.disable_user(scope, user),
         {:ok, entry} <- Accounts.admin_entry(scope, user) do
      json(conn, UserAdminJSON.user(entry))
    end
  end

  operation :end_sessions,
    summary: "End the sessions of a user",
    security: Responses.session_and_csrf(),
    parameters: @id,
    responses:
      Map.merge(
        %{204 => "The sessions are ended"},
        Responses.errors(Responses.admin_write(@not_found))
      )

  def end_sessions(conn, %{id: id}) do
    with {:ok, user} <- fetch_user(id),
         {:ok, _count} <- Accounts.end_user_sessions(conn.assigns.current_scope, user) do
      send_resp(conn, :no_content, "")
    end
  end

  operation :end_all_sessions,
    summary: "End the sessions of all users",
    description: "Also ends the session of the acting admin.",
    security: Responses.session_and_csrf(),
    responses:
      Map.merge(
        %{204 => "Every session is ended"},
        Responses.errors(Responses.admin_write())
      )

  def end_all_sessions(conn, _params) do
    with {:ok, _count} <- Accounts.end_all_sessions(conn.assigns.current_scope) do
      send_resp(conn, :no_content, "")
    end
  end

  operation :reset_factors,
    summary: "Reset the second factors of a user",
    description:
      "Decision D11: after the organization verified the person's identity, every second " <>
        "factor, every session and the failure counters of the user are removed in one " <>
        "transaction, and a local account receives a new invitation.",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body:
      {"The identity check", "application/json", Admin.FactorResetRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The result", "application/json", Admin.FactorResetResult}},
        Responses.errors(
          Responses.admin_write([
            {404, ["not_found"]},
            {409, ["own_account"]},
            {422, ["validation_failed", "identity_verification_required"]}
          ])
        )
      )

  def reset_factors(conn, %{id: id}) do
    scope = conn.assigns.current_scope

    with :ok <- identity_verified(conn.body_params),
         {:ok, user} <- fetch_user(id),
         :ok <- not_own_account(scope, user),
         {:ok, result} <- Accounts.reset_factors(scope, user) do
      json(conn, %{invitation_sent: result.invitation_sent})
    end
  end

  operation :reset_failure_counters,
    summary: "Reset the failure counters of a user",
    security: Responses.session_and_csrf(),
    parameters: @id,
    request_body: {"No members", "application/json", EmptyRequest, required: false},
    responses:
      Map.merge(
        %{204 => "The counters are reset"},
        Responses.errors(Responses.admin_write(@not_found))
      )

  def reset_failure_counters(conn, %{id: id}) do
    with {:ok, user} <- fetch_user(id),
         {:ok, _user} <- Accounts.reset_failure_counters(conn.assigns.current_scope, user) do
      send_resp(conn, :no_content, "")
    end
  end

  defp fetch_user(id) do
    case Accounts.get_user(id) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :not_found}
    end
  end

  defp not_own_account(%Scope{user: %User{id: id}}, %User{id: id}), do: {:error, :own_account}
  defp not_own_account(_scope, _user), do: :ok

  defp identity_verified(%{identity_verified: true}), do: :ok
  defp identity_verified(_body), do: {:error, :identity_verification_required}
end
