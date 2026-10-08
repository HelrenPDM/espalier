defmodule Espalier.Vault do
  @moduledoc """
  Cloak vault with one AES-256-GCM cipher per key version.

  The keys come from `config :espalier, Espalier.Vault, keys: [{version, base64}]`
  (`CLOAK_KEY_V<n>` in production, `config/runtime.exs`). The highest version
  encrypts every new value; the other versions only decrypt. A failed
  decryption raises `Espalier.Crypto.DecryptError` in `decrypt!/1` and makes
  the load of an Ecto field raise.

  The vault must run before anything dumps or loads an encrypted field, so it
  starts before `Espalier.Repo`, and a data migration starts it with
  `start_link/0`.
  """
  use Cloak.Vault, otp_app: :espalier

  alias Espalier.Crypto.{DecryptError, Keys, StrictAESGCM}

  @impl GenServer
  def init(config) do
    ciphers =
      config
      |> Keyword.get(:keys, [])
      |> Keys.cipher_keys!()
      |> Enum.with_index()
      |> Enum.map(fn {{version, key}, index} ->
        label = if index == 0, do: :current, else: :retired
        {label, {StrictAESGCM, tag: Keys.tag(version), key: key, iv_length: 12}}
      end)

    {:ok, config |> Keyword.delete(:keys) |> Keyword.put(:ciphers, ciphers)}
  end

  @impl Cloak.Vault
  def decrypt!(ciphertext) do
    case decrypt(ciphertext) do
      {:ok, plaintext} -> plaintext
      {:error, exception} -> raise exception
      :error -> raise DecryptError
    end
  end

  @impl GenServer
  def format_status(%{state: config} = status) do
    %{status | state: Keyword.update(config, :ciphers, [], &redact_keys/1)}
  end

  def format_status(status), do: status

  defp redact_keys(ciphers) do
    for {label, {module, opts}} <- ciphers,
        do: {label, {module, Keyword.put(opts, :key, :redacted)}}
  end
end
