defmodule Espalier.Identity.Ldap.Eldap do
  @moduledoc """
  The production `Espalier.Identity.Ldap.Client`: one `:eldap` call per
  callback, without any option of its own.
  """
  @behaviour Espalier.Identity.Ldap.Client

  @impl true
  def open(hosts, opts), do: :eldap.open(hosts, opts)

  @impl true
  def start_tls(handle, tls_opts, timeout), do: :eldap.start_tls(handle, tls_opts, timeout)

  @impl true
  def simple_bind(handle, dn, password), do: :eldap.simple_bind(handle, dn, password)

  @impl true
  def search(handle, opts), do: :eldap.search(handle, opts)

  @impl true
  def close(handle), do: :eldap.close(handle)
end
