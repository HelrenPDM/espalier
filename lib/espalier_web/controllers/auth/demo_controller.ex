defmodule EspalierWeb.Auth.DemoController do
  @moduledoc """
  Demo sign-in for test sessions (`AUTH_DEMO=true`). The session has the
  strength `demo` and the methods `[:demo]`; the row carries no
  `provider_key`, and the security events carry the provider `demo`.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts.Demo
  alias EspalierWeb.Plugs.RateLimit
  alias EspalierWeb.{SessionController, UserAuth}

  action_fallback EspalierWeb.FallbackController

  plug :require_demo
  plug RateLimit, [bucket: :demo_ip] when action in [:create]

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
