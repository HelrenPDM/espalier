defmodule Espalier.FakeLdapServer do
  @moduledoc """
  An in-process LDAP server for the tests of task 0007 (step 22). It speaks
  LDAPv3 through the ASN.1 module `:ELDAPv3` of the `eldap` application and
  writes the record tuples by hand, with the field order of `ELDAPv3.asn1`
  (RFC 4511), so the real `:eldap` client runs against it.

  `start!/1` starts it under the test supervisor and returns its port.
  Every decoded request arrives at the test process as
  `{:fake_ldap, :request, message_id, op}`; each connection runs in its own
  process, so both connections of one sign-in reach the fake.

  ## Options

    * `:transport` - `:ldap` (default, plain TCP, also for StartTLS) or
      `:ldaps`.
    * `:server_tls` - the server TLS options, `server_config` of
      `tls_fixture/1`; required for `:ldaps` and StartTLS.
    * `:binds` - the bind result per DN, a result code atom such as
      `:success` or `:invalidCredentials`, `{:referral, urls}`, or a
      function of the decoded authentication choice that returns one of
      these. `:default_bind` (`:invalidCredentials`) answers other DNs.
    * `:entries` - `[{dn, [{attribute, [value]}]}]` with binaries, the
      answer to every subtree search.
    * `:members` - `%{user_dn => [group_dn]}`, the members of the groups
      for the base searches with a `memberOf` filter.
    * `:search` - a function of `%{base:, scope:, filter:, attributes:}`
      that returns `{:ok, entries}`, `{:error, code}` or
      `{:referral, urls}` and replaces the defaults above.
    * `:start_tls` - the result code of a StartTLS request (`:success`),
      or `{:referral, urls}`.
    * `:silent` - when true, the fake never answers.
  """
  use GenServer

  @start_tls_oid ~c"1.3.6.1.4.1.1466.20037"
  @referral [~c"ldap://other.example.org/"]

  @doc "Starts the fake under the test supervisor and returns its port."
  def start!(opts) do
    opts = Keyword.put_new(opts, :test_pid, self())

    server =
      ExUnit.Callbacks.start_supervised!(
        Supervisor.child_spec({__MODULE__, opts}, id: make_ref())
      )

    port(server)
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "The port the fake listens on (127.0.0.1)."
  def port(server), do: GenServer.call(server, :port)

  @doc """
  Builds an EC P-256 test chain with `:public_key.pkix_test_data/1` and
  returns `%{server_config: opts, cacerts: [der]}`. `dns_name` goes into
  the subject alternative name of the server certificate.
  """
  def tls_fixture(dns_name \\ "localhost") do
    key = [key: {:namedCurve, :secp256r1}, digest: :sha256]
    san = {:Extension, {2, 5, 29, 17}, false, [dNSName: String.to_charlist(dns_name)]}

    %{server_config: server_config, client_config: client_config} =
      :public_key.pkix_test_data(%{
        server_chain: %{root: key, intermediates: [], peer: key ++ [extensions: [san]]},
        client_chain: %{root: key, intermediates: [], peer: key}
      })

    %{server_config: server_config, cacerts: Keyword.fetch!(client_config, :cacerts)}
  end

  @impl true
  def init(opts) do
    listen_opts = [:binary, packet: :asn1, active: false, reuseaddr: true, ip: {127, 0, 0, 1}]

    {:ok, listen} =
      case Keyword.get(opts, :transport, :ldap) do
        :ldaps -> :ssl.listen(0, listen_opts ++ Keyword.fetch!(opts, :server_tls))
        :ldap -> :gen_tcp.listen(0, listen_opts)
      end

    {:ok, {_address, port}} =
      case Keyword.get(opts, :transport, :ldap) do
        :ldaps -> :ssl.sockname(listen)
        :ldap -> :inet.sockname(listen)
      end

    server = self()
    acceptor = spawn_link(fn -> accept_loop(server, listen, opts) end)
    {:ok, %{listen: listen, port: port, acceptor: acceptor}}
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  ## Connections

  defp accept_loop(server, listen, opts) do
    accept(Keyword.get(opts, :transport, :ldap), listen, opts)
    accept_loop(server, listen, opts)
  end

  defp accept(:ldaps, listen, opts) do
    with {:ok, socket} <- :ssl.transport_accept(listen) do
      handler = spawn(fn -> handshake_and_serve(socket, opts) end)
      :ok = :ssl.controlling_process(socket, handler)
      send(handler, :go)
    end
  end

  defp accept(:ldap, listen, opts) do
    with {:ok, socket} <- :gen_tcp.accept(listen) do
      handler = spawn(fn -> receive(do: (:go -> serve(:gen_tcp, socket, opts))) end)
      :ok = :gen_tcp.controlling_process(socket, handler)
      send(handler, :go)
    end
  end

  defp handshake_and_serve(socket, opts) do
    receive do
      :go ->
        case :ssl.handshake(socket, 5_000) do
          {:ok, socket} -> serve(:ssl, socket, opts)
          {:error, _reason} -> :ok
        end
    end
  end

  defp serve(transport, socket, opts) do
    case transport.recv(socket, 0) do
      {:ok, packet} -> handle_packet(packet, transport, socket, opts)
      {:error, _reason} -> :ok
    end
  end

  defp handle_packet(packet, transport, socket, opts) do
    {:ok, {:LDAPMessage, id, op, _controls}} = :ELDAPv3.decode(:LDAPMessage, packet)
    send(Keyword.fetch!(opts, :test_pid), {:fake_ldap, :request, id, op})

    if Keyword.get(opts, :silent, false),
      do: serve(transport, socket, opts),
      else: respond(op, id, transport, socket, opts)
  end

  defp respond(op, id, transport, socket, opts) do
    case answer(op, id, transport, socket, opts) do
      {:continue, transport, socket} -> serve(transport, socket, opts)
      :stop -> transport.close(socket)
    end
  end

  defp answer({:bindRequest, {:BindRequest, _version, name, auth}}, id, transport, socket, opts) do
    {code, referral} = result(bind_result(opts, to_binary(name), auth))

    reply(
      transport,
      socket,
      id,
      {:bindResponse, {:BindResponse, code, ~c"", ~c"", referral, :asn1_NOVALUE}}
    )

    {:continue, transport, socket}
  end

  defp answer({:searchRequest, request}, id, transport, socket, opts) do
    {:SearchRequest, base, scope, _deref, _size, _time, _types_only, filter, attributes} = request

    search = %{
      base: to_binary(base),
      scope: scope,
      filter: filter,
      attributes: Enum.map(attributes, &to_binary/1)
    }

    {code, referral} =
      case search_result(opts, search) do
        {:ok, entries} ->
          for {dn, attrs} <- entries do
            reply(transport, socket, id, {:searchResEntry, entry(dn, attrs)})
          end

          {:success, :asn1_NOVALUE}

        other ->
          result(other)
      end

    reply(transport, socket, id, {:searchResDone, {:LDAPResult, code, ~c"", ~c"", referral}})
    {:continue, transport, socket}
  end

  defp answer(
         {:extendedReq, {:ExtendedRequest, @start_tls_oid, _value}},
         id,
         transport,
         socket,
         opts
       ) do
    {code, referral} = result(Keyword.get(opts, :start_tls, :success))

    reply(
      transport,
      socket,
      id,
      {:extendedResp,
       {:ExtendedResponse, code, ~c"", ~c"", referral, :asn1_NOVALUE, :asn1_NOVALUE}}
    )

    if code == :success do
      tls = Keyword.fetch!(opts, :server_tls) ++ [packet: :asn1, active: false, mode: :binary]

      case :ssl.handshake(socket, tls, 5_000) do
        {:ok, tls_socket} -> {:continue, :ssl, tls_socket}
        {:error, _reason} -> :stop
      end
    else
      {:continue, transport, socket}
    end
  end

  defp answer({:unbindRequest, _null}, _id, _transport, _socket, _opts), do: :stop
  defp answer(_op, _id, transport, socket, _opts), do: {:continue, transport, socket}

  defp bind_result(opts, dn, auth) do
    case Map.get(
           Keyword.get(opts, :binds, %{}),
           dn,
           Keyword.get(opts, :default_bind, :invalidCredentials)
         ) do
      fun when is_function(fun, 1) -> fun.(auth)
      result -> result
    end
  end

  defp search_result(opts, search) do
    case Keyword.fetch(opts, :search) do
      {:ok, fun} -> fun.(search)
      :error -> default_search(opts, search)
    end
  end

  defp default_search(opts, %{scope: :wholeSubtree}), do: {:ok, Keyword.get(opts, :entries, [])}

  defp default_search(opts, %{scope: :baseObject, base: base, filter: filter}) do
    case member_filter(filter) do
      nil ->
        {:ok, [{base, []}]}

      group_dn ->
        if group_dn in Map.get(Keyword.get(opts, :members, %{}), base, []),
          do: {:ok, [{base, []}]},
          else: {:error, :noSuchObject}
    end
  end

  defp default_search(_opts, _search), do: {:ok, []}

  defp member_filter({:equalityMatch, {:AttributeValueAssertion, _type, value}}),
    do: to_binary(value)

  defp member_filter({:extensibleMatch, {:MatchingRuleAssertion, _rule, _type, value, _dn}}),
    do: to_binary(value)

  defp member_filter(_filter), do: nil

  defp result({:referral, urls}), do: {:referral, Enum.map(urls, &to_charlist/1)}
  defp result(:referral), do: {:referral, @referral}
  defp result({:error, code}), do: {code, :asn1_NOVALUE}
  defp result(code) when is_atom(code), do: {code, :asn1_NOVALUE}

  defp entry(dn, attrs) do
    {:SearchResultEntry, to_list(dn),
     for {type, values} <- attrs do
       {:PartialAttribute, to_list(type), Enum.map(values, &to_list/1)}
     end}
  end

  defp reply(transport, socket, id, op) do
    {:ok, bytes} = :ELDAPv3.encode(:LDAPMessage, {:LDAPMessage, id, op, :asn1_NOVALUE})
    transport.send(socket, bytes)
  end

  defp to_binary(value) when is_binary(value), do: value
  defp to_binary(value) when is_list(value), do: :erlang.list_to_binary(value)

  defp to_list(value) when is_binary(value), do: :erlang.binary_to_list(value)
  defp to_list(value) when is_list(value), do: value
end
