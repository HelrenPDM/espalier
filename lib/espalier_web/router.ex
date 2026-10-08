defmodule EspalierWeb.Router do
  use EspalierWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", EspalierWeb do
    get "/health", HealthController, :index
  end

  scope "/api", EspalierWeb do
    pipe_through :api
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:espalier, :dev_routes) do
    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # The SPA catch-all stays the last route.
  scope "/", EspalierWeb do
    get "/*path", SpaController, :index
  end
end
