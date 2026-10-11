defmodule EspalierWeb.Auth.LdapController do
  @moduledoc """
  `POST /api/auth/ldap/:provider` with `{username, password}`: the
  directory bind as first factor (task 0007, step 19; README section 6.12).

  A directory bind alone never opens a full session (ASVS 6.3.3): a user
  with a local factor enters the pending second-factor state and gets
  `{"next": "second_factor"}`, and a user without one gets an enrollment
  session of 30 minutes and `{"next": "enroll_second_factor"}`. Every
  authentication failure answers the same 401 `invalid_credentials`.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{ExternalNextStep, Fields, LdapCredentialsRequest}

  # OpenAPI operations of task 0011 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0007.
  tags ["Session"]
  security Responses.csrf()

  alias Espalier.Accounts
  alias Espalier.Accounts.LdapSignIn
  alias Espalier.Identity.Ldap
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.UserAuth

  action_fallback EspalierWeb.FallbackController

  plug RateLimit, [bucket: :ldap_ip] when action in [:create]

  operation :create,
    summary: "Sign in with a directory account",
    description:
      "A directory bind is a first factor only: an enrolled user enters the pending " <>
        "second-factor state, a user without a local factor an enrollment session. Every " <>
        "authentication failure answers 401 `invalid_credentials`.",
    parameters: [
      provider: [
        in: :path,
        required: true,
        description: "The provider key.",
        schema: Fields.string()
      ]
    ],
    request_body:
      {"The directory credentials", "application/json", LdapCredentialsRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The next step", "application/json", ExternalNextStep}},
        Responses.errors([
          {400, ["bad_request"]},
          {401, ["invalid_credentials"]},
          {403, ["csrf", "cross_site_request"]},
          {404, ["unknown_provider"]},
          {409, ["link_required"]},
          {429, ["rate_limited"]}
        ])
      )

  def create(conn, %{"provider" => key} = params) do
    with {:ok, provider} <- fetch_provider(key),
         {:ok, username, password} <- credentials(params) do
      case LdapSignIn.sign_in(provider, username, password, %{ip: conn.remote_ip}) do
        {:ok, user} ->
          signed_in(conn, user, key)

        {:error, :rate_limited, retry_after_ms} ->
          RateLimit.too_many_requests(conn, retry_after_ms)

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp signed_in(conn, user, key) do
    if Accounts.enrolled?(user) do
      conn
      |> UserAuth.put_pending_second_factor(user, %{auth_methods: [:ldap], provider_key: key})
      |> json(%{next: "second_factor"})
    else
      conn
      |> UserAuth.log_in_user(user,
        auth_methods: [:ldap],
        strength: :enrollment,
        provider_key: key
      )
      |> json(%{next: "enroll_second_factor"})
    end
  end

  @doc false
  def fetch_provider(key) do
    case Ldap.provider(key) do
      {:ok, provider} -> {:ok, provider}
      :error -> {:error, :unknown_provider}
    end
  end

  @doc false
  def credentials(%{"username" => username, "password" => password})
      when is_binary(username) and is_binary(password),
      do: {:ok, username, password}

  def credentials(_params), do: {:error, :bad_request}
end
