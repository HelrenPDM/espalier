defmodule EspalierWeb.SessionController do
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.SessionPayload

  # OpenAPI operations of task 0009 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0004.
  tags ["Session"]

  alias Espalier.Accounts.{Scope, UserToken}
  alias Espalier.Identity
  alias Espalier.Identity.Oidc
  alias EspalierWeb.UserAuth

  operation :show,
    summary: "Read the session payload",
    description:
      "The user, roles, session strength, CSRF token, providers and flags; `user`, " <>
        "`session` and `pending` are `null` when absent.",
    security: Responses.public(),
    responses:
      Map.merge(
        %{200 => {"The session payload", "application/json", SessionPayload}},
        Responses.errors([{403, ["cross_site_request"]}])
      )

  def show(conn, _params) do
    render_session(conn)
  end

  @doc """
  Signs out. For a session of an OIDC provider with an end-session endpoint
  on its allowed hosts, the answer is 200 with the RP-initiated logout URL
  (task 0006, step 13); every other sign-out answers 204.
  """
  operation :delete,
    summary: "Sign out",
    security: Responses.csrf(),
    responses:
      Map.merge(
        %{204 => "Signed out"},
        Responses.errors([{403, ["csrf", "cross_site_request"]}])
      )

  def delete(conn, _params) do
    logout_url = rp_logout_url(conn.assigns[:current_scope])
    conn = UserAuth.log_out_user(conn)

    case logout_url do
      nil -> send_resp(conn, :no_content, "")
      url -> json(conn, %{logout_url: url})
    end
  end

  # The URL carries client_id and post_logout_redirect_uri and no
  # id_token_hint, because the platform keeps no ID token. The Erlang
  # function is called, because Oidcc.Logout.initiate_url/3 of oidcc 3.9.0
  # raises for :undefined.
  defp rp_logout_url(%Scope{session: %UserToken{provider_key: key}}) when is_binary(key) do
    with {:ok, provider} <- Identity.fetch_oidc_provider(key),
         {:ok, configuration} <- Oidc.provider_configuration(provider),
         :ok <- Oidc.check_endpoints(provider, configuration),
         {:ok, client_context} <-
           Oidcc.ClientContext.from_configuration_worker(
             provider.worker,
             provider.client_id,
             :unauthenticated,
             %{}
           ),
         {:ok, url} <-
           :oidcc_logout.initiate_url(
             :undefined,
             Oidcc.ClientContext.struct_to_record(client_context),
             %{post_logout_redirect_uri: signed_out_url()}
           ) do
      IO.chardata_to_string(url)
    else
      _ -> nil
    end
  catch
    # The worker call exits while the worker waits for a slow provider; the
    # sign-out then ends the platform session only.
    :exit, _reason -> nil
  end

  defp rp_logout_url(_scope), do: nil

  defp signed_out_url do
    String.trim_trailing(Application.fetch_env!(:espalier, :public_url), "/") <> "/signed-out"
  end

  @doc """
  Renders the session payload for the scope and the pending state of
  `conn`, merged with `extra` (such as `recent_auth_until`).
  """
  def render_session(conn, status \\ :ok, extra \\ %{}) do
    conn
    |> put_status(status)
    |> json(Map.merge(session_payload(conn), extra))
  end

  @doc "Returns the session payload of `conn` as a map."
  def session_payload(conn) do
    pending =
      case UserAuth.fetch_pending_second_factor(conn) do
        {:ok, pending} -> pending
        :error -> nil
      end

    EspalierWeb.SessionJSON.show(%{scope: conn.assigns[:current_scope], pending: pending})
  end
end
