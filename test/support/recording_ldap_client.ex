defmodule Espalier.Identity.Ldap.RecordingClient do
  @moduledoc """
  An `Espalier.Identity.Ldap.Client` for the integration tests of task 0007:
  it calls `Espalier.Identity.Ldap.Eldap` and sends `{:ldap_call, name}` to
  the test process, which it finds through `$callers`.
  """
  @behaviour Espalier.Identity.Ldap.Client

  alias Espalier.Identity.Ldap.Eldap

  @impl true
  def open(hosts, opts), do: record(:open, fn -> Eldap.open(hosts, opts) end)

  @impl true
  def start_tls(handle, tls_opts, timeout),
    do: record(:start_tls, fn -> Eldap.start_tls(handle, tls_opts, timeout) end)

  @impl true
  def simple_bind(handle, dn, password),
    do: record(:simple_bind, fn -> Eldap.simple_bind(handle, dn, password) end)

  @impl true
  def search(handle, opts), do: record(:search, fn -> Eldap.search(handle, opts) end)

  @impl true
  def close(handle), do: record(:close, fn -> Eldap.close(handle) end)

  defp record(name, fun) do
    test_pid = :"$callers" |> Process.get([self()]) |> List.last()
    send(test_pid, {:ldap_call, name})
    fun.()
  end
end
