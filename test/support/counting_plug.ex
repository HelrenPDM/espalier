defmodule Espalier.Test.CountingPlug do
  @moduledoc """
  A plug that counts its requests in a `:counters` reference and answers
  200 with `{}`. The transport test of task 0006 serves it over TLS.
  """
  @behaviour Plug

  @impl Plug
  def init(counter), do: counter

  @impl Plug
  def call(conn, counter) do
    :counters.add(counter, 1, 1)
    Plug.Conn.send_resp(conn, 200, "{}")
  end
end
