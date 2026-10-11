defmodule EspalierWeb.Plugs.RegistrarEnabled do
  @moduledoc """
  Answers 404 `not_found` and halts unless `REGISTRAR_ENABLED=true`
  (`config :espalier, :registrar_enabled`, README section 10). The
  pipeline `:registrar_enabled` runs it before the role check, so that a
  disabled list answers 404 to every caller, a registrar included.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Application.get_env(:espalier, :registrar_enabled, false) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(404, ~s({"error":"not_found"}))
      |> halt()
    end
  end
end
