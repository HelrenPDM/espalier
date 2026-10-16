defmodule EspalierWeb.EndpointHttp2Test do
  # The endpoint serves no HTTP/2 (config/config.exs), which keeps the HTTP/2
  # stack of Bandit out of reach. Each test starts its own Bandit on an
  # ephemeral port with the endpoint's options.
  use ExUnit.Case, async: true

  alias Espalier.Test.CountingPlug

  # Over plain TCP, Bandit picks HTTP/2 when a connection opens with this
  # preface (prior knowledge, RFC 9113 section 3.3).
  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

  # recv/3 returns as soon as the answer or the close arrives; the bound only
  # leaves room for a loaded machine, on which 2 seconds were too short.
  @recv_timeout 10_000

  test "the endpoint configuration turns HTTP/2 off" do
    assert endpoint_http()[:http_2_options][:enabled] == false
  end

  test "Bandit with the endpoint options closes a connection that opens with the HTTP/2 preface" do
    {port, counter} = start_bandit(endpoint_http())
    socket = connect(port)
    :ok = :gen_tcp.send(socket, @preface)
    assert :gen_tcp.recv(socket, 0, @recv_timeout) == {:error, :closed}
    assert :counters.get(counter, 1) == 0
  end

  test "Bandit with the endpoint options answers HTTP/1.1" do
    {port, counter} = start_bandit(endpoint_http())
    socket = connect(port)
    :ok = :gen_tcp.send(socket, "GET / HTTP/1.1\r\nhost: localhost\r\n\r\n")
    assert {:ok, "HTTP/1.1 200 OK\r\n" <> _rest} = :gen_tcp.recv(socket, 0, @recv_timeout)
    assert :counters.get(counter, 1) == 1
  end

  # Control for the preface test: with HTTP/2 on, the same preface gets the
  # server's SETTINGS frame (type 4 on stream 0), so a closed connection above
  # comes from the option.
  test "Bandit with HTTP/2 on answers the preface with a SETTINGS frame" do
    {port, _counter} =
      start_bandit(Keyword.put(endpoint_http(), :http_2_options, enabled: true))

    socket = connect(port)
    :ok = :gen_tcp.send(socket, @preface)

    assert {:ok, <<_length::24, 4::8, _flags::8, 0::1, 0::31, _rest::binary>>} =
             :gen_tcp.recv(socket, 9, @recv_timeout)
  end

  defp endpoint_http do
    Application.fetch_env!(:espalier, EspalierWeb.Endpoint)[:http]
  end

  defp start_bandit(options) do
    counter = :counters.new(1, [])

    options =
      Keyword.merge(options, plug: {CountingPlug, counter}, port: 0, startup_log: false)

    pid = start_supervised!({Bandit, options})
    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    {port, counter}
  end

  defp connect(port) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false])
    on_exit(fn -> :gen_tcp.close(socket) end)
    socket
  end
end
