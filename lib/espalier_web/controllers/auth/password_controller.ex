defmodule EspalierWeb.Auth.PasswordController do
  @moduledoc """
  Password sign-in up to the pending second-factor state. A password alone
  never opens a session (ASVS 6.3.4). Known and unknown addresses receive
  the same answer.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{NextStep, PasswordSignInRequest}

  # OpenAPI operations of task 0009 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0004.
  tags ["Session"]
  security Responses.csrf()

  alias Espalier.Accounts
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.UserAuth

  action_fallback EspalierWeb.FallbackController

  plug :require_local_accounts
  plug RateLimit, [bucket: :auth_ip] when action in [:create]

  operation :create,
    summary: "Sign in with a password",
    description:
      "A correct password yields the pending second-factor state for five minutes and " <>
        "never a session. Known and unknown addresses receive the same answer.",
    request_body:
      {"The address and the password", "application/json", PasswordSignInRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The next step", "application/json", NextStep}},
        Responses.errors([
          {400, ["bad_request"]},
          {401, ["invalid_credentials"]},
          {403, ["csrf", "cross_site_request"]},
          {404, ["not_found"]},
          {429, ["rate_limited"]}
        ])
      )

  def create(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    conn = RateLimit.check_account(conn, :password_account, Accounts.normalize_email(email))

    if conn.halted do
      conn
    else
      case Accounts.authenticate_password(email, password, %{ip: conn.remote_ip}) do
        {:ok, user} ->
          conn
          |> UserAuth.put_pending_second_factor(user, auth_methods: [:password])
          |> json(%{next: "second_factor"})

        {:error, :invalid_credentials} = error ->
          error
      end
    end
  end

  def create(_conn, _params), do: {:error, :bad_request}

  defp require_local_accounts(conn, _opts) do
    if Application.get_env(:espalier, :local_accounts, true) do
      conn
    else
      conn |> put_status(:not_found) |> json(%{error: "not_found"}) |> halt()
    end
  end
end
