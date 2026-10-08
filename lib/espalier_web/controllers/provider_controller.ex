defmodule EspalierWeb.ProviderController do
  use EspalierWeb, :controller

  # The public entries of the external providers in configured order
  # (Espalier.Identity.Config.public_entry/1).
  def index(conn, _params) do
    json(conn, %{providers: Application.get_env(:espalier, :auth_providers, [])})
  end
end
