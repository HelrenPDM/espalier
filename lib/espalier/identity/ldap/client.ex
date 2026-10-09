defmodule Espalier.Identity.Ldap.Client do
  @moduledoc """
  The `:eldap` calls of `Espalier.Identity.Ldap` (task 0007, step 3).
  `Espalier.Identity.Ldap.Eldap` implements each callback with one call to
  the `:eldap` function of the same name; the test suite replaces it with a
  Mox mock through the `client` field of the provider config.
  """

  @callback open([charlist()], keyword()) :: {:ok, pid()} | {:error, term()}
  @callback start_tls(pid(), keyword(), pos_integer()) ::
              :ok | {:ok, {:referral, list()}} | {:error, term()}
  @callback simple_bind(pid(), binary(), binary()) ::
              :ok | {:ok, {:referral, list()}} | {:error, term()}
  @callback search(pid(), keyword()) :: {:ok, tuple()} | {:error, term()}
  @callback close(pid()) :: :ok
end
