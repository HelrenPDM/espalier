defmodule EspalierWeb.Auth.DemoController do
  @moduledoc """
  Demo sign-in for test sessions (`AUTH_DEMO=true`). The session has the
  strength `demo` and the methods `[:demo]`; the row carries no
  `provider_key`, and the security events carry the provider `demo`.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.{DemoSignInRequest, SessionPayload}

  # OpenAPI operations of task 0009 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0004.
  tags ["Session"]
  security Responses.csrf()

  alias Espalier.Accounts.Demo
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.{SessionController, UserAuth}

  action_fallback EspalierWeb.FallbackController

  plug :require_demo
  plug RateLimit, [bucket: :demo_ip] when action in [:create]

  operation :create,
    summary: "Sign in to a demo account",
    description: "Only with `AUTH_DEMO=true`; otherwise 404.",
    request_body: {"The demo slot", "application/json", DemoSignInRequest, required: true},
    responses:
      Map.merge(
        %{200 => {"The session payload", "application/json", SessionPayload}},
        Responses.errors([
          {400, ["bad_request"]},
          {403, ["csrf", "cross_site_request"]},
          {404, ["not_found"]},
          {429, ["rate_limited"]}
        ])
      )

  def create(conn, %{"slot" => slot}) when is_integer(slot) do
    if slot in Demo.slots() do
      {:ok, user} = Demo.get_or_create_user(slot)

      conn
      |> UserAuth.log_in_user(user, auth_methods: [:demo], strength: :demo, provider: :demo)
      |> SessionController.render_session()
    else
      {:error, :bad_request}
    end
  end

  def create(_conn, _params), do: {:error, :bad_request}

  defp require_demo(conn, _opts) do
    if Application.get_env(:espalier, :auth_demo, false) do
      conn
    else
      conn |> put_status(:not_found) |> json(%{error: "not_found"}) |> halt()
    end
  end
end
