defmodule Espalier.Accounts.CoseKey do
  @moduledoc """
  Ecto type of the COSE public key of a passkey (`webauthn_credentials.cose_key`).

  `wax_` returns the key as a map with integer keys (RFC 9052). The column
  stores it with `:erlang.term_to_binary/1`, and loading accepts only such a
  map from `Plug.Crypto.non_executable_binary_to_term/2` with `[:safe]`, so a
  stored term that contains a function or creates atoms never loads.
  """
  use Ecto.Type

  @impl Ecto.Type
  def type, do: :binary

  @impl Ecto.Type
  def cast(value) do
    if cose_map?(value), do: {:ok, value}, else: :error
  end

  @impl Ecto.Type
  def dump(value) do
    if cose_map?(value), do: {:ok, :erlang.term_to_binary(value)}, else: :error
  end

  @impl Ecto.Type
  def load(binary) when is_binary(binary) do
    term = Plug.Crypto.non_executable_binary_to_term(binary, [:safe])
    if cose_map?(term), do: {:ok, term}, else: :error
  rescue
    ArgumentError -> :error
  end

  def load(_value), do: :error

  defp cose_map?(value) when is_map(value) and not is_struct(value) do
    map_size(value) > 0 and Enum.all?(Map.keys(value), &is_integer/1)
  end

  defp cose_map?(_value), do: false
end
