defmodule Espalier.Crypto.StrictAESGCM do
  @moduledoc """
  Cloak.Ciphers.AES.GCM that returns :error when GCM authentication fails.
  The wrapped cipher returns {:ok, :error} for a tampered value or a wrong key.

  This is the only module that names a Cloak cipher, and the only cipher that
  `Espalier.Vault` holds. It keeps the byte format of the wrapped cipher, so a
  value written with either module can be read by the other.
  """
  @behaviour Cloak.Cipher
  alias Cloak.Ciphers.AES.GCM

  @impl Cloak.Cipher
  defdelegate encrypt(plaintext, opts), to: GCM

  @impl Cloak.Cipher
  defdelegate can_decrypt?(ciphertext, opts), to: GCM

  @impl Cloak.Cipher
  def decrypt(ciphertext, opts) do
    case GCM.decrypt(ciphertext, opts) do
      {:ok, plaintext} when is_binary(plaintext) -> {:ok, plaintext}
      _ -> :error
    end
  end
end
