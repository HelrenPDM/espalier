defmodule EspalierWeb.Plugs.TrustedProxy do
  @moduledoc """
  Takes the client address from `X-Forwarded-For` only when the peer lies in
  `TRUSTED_PROXIES` (README section 6.10).

  The plug uses the rightmost entry, which the trusted proxy appended, and
  keeps the peer address when that entry does not parse. `Plug.RewriteOn`
  takes the leftmost entry, which a client controls behind an appending
  proxy, so it is not used. The proxy must overwrite or append the header;
  task 0017 checks the proxy example.
  """
  @behaviour Plug

  import Bitwise

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    proxies = Application.get_env(:espalier, :trusted_proxies, [])

    with true <- trusted?(conn.remote_ip, proxies),
         [_ | _] = values <- Plug.Conn.get_req_header(conn, "x-forwarded-for"),
         {:ok, ip} <- rightmost(values) do
      %{conn | remote_ip: ip}
    else
      _ -> conn
    end
  end

  defp rightmost(values) do
    values
    |> Enum.join(",")
    |> String.split(",")
    |> List.last()
    |> String.trim()
    |> String.to_charlist()
    |> :inet.parse_strict_address()
  end

  @doc "True when `ip` lies in one of the parsed `{address, prefix_length}` ranges."
  def trusted?(ip, proxies) do
    Enum.any?(proxies, fn {network, prefix} -> in_range?(ip, network, prefix) end)
  end

  defp in_range?(ip, network, prefix) when tuple_size(ip) == tuple_size(network) do
    bits = if tuple_size(ip) == 4, do: 32, else: 128
    mask = ((1 <<< prefix) - 1) <<< (bits - prefix)
    (to_integer(ip) &&& mask) == (to_integer(network) &&& mask)
  end

  defp in_range?(_ip, _network, _prefix), do: false

  defp to_integer({a, b, c, d}), do: (a <<< 24) + (b <<< 16) + (c <<< 8) + d

  defp to_integer(ip) when tuple_size(ip) == 8 do
    ip |> Tuple.to_list() |> Enum.reduce(0, fn part, acc -> (acc <<< 16) + part end)
  end
end
