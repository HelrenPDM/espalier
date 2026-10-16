defmodule Espalier.Test.FunctionPlug do
  @moduledoc """
  A plug that answers through the function of one argument that it receives
  as its option. `EspalierWeb.BlockDownloadTest` and the draft download
  test of `EspalierWeb.Admin.PackDraftControllerTest` serve it with Bandit
  on an ephemeral port, so that a client reads the response from a real
  socket.
  """
  @behaviour Plug

  @impl Plug
  def init(fun) when is_function(fun, 1), do: fun

  @impl Plug
  def call(conn, fun), do: fun.(conn)
end
