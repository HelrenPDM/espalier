defmodule Espalier.Crypto.Keys do
  @moduledoc """
  Decodes and checks the encryption keys and the HMAC secret.

  Each `CLOAK_KEY_V<n>` and `CLOAK_HMAC_SECRET` holds 32 random bytes,
  Base64-encoded with padding (`make gen-keys`). Each key version `n` defines
  the cipher tag `AES.GCM.V<n>`; the highest version encrypts new values, and
  the others only decrypt. No message, log line or exception field of this
  module contains a key or a secret.
  """

  require Logger

  alias Espalier.Crypto.InvalidKeyError

  @key_bytes 32

  @doc "Returns the cipher tag of a key version, for example `AES.GCM.V1`."
  @spec tag(pos_integer()) :: String.t()
  def tag(version), do: "AES.GCM.V#{version}"

  @doc """
  Decodes a Base64 value into a 32-byte key, or raises `InvalidKeyError` with
  a message that names `name`.
  """
  @spec decode!(String.t(), term()) :: binary()
  def decode!(name, value) when is_binary(value) do
    case value |> String.trim() |> Base.decode64() do
      {:ok, <<_::binary-size(@key_bytes)>> = key} -> key
      _ -> raise InvalidKeyError, invalid_message(name)
    end
  end

  def decode!(name, _value), do: raise(InvalidKeyError, invalid_message(name))

  @doc """
  Decodes `[{version, base64}]` and returns `[{version, key}]`, highest
  version first.

  Requires at least one entry, distinct positive integer versions and
  pairwise distinct keys.
  """
  @spec cipher_keys!([{pos_integer(), String.t()}]) :: [{pos_integer(), binary()}]
  def cipher_keys!([_ | _] = entries) do
    versions = Enum.map(entries, &version!/1)

    if Enum.uniq(versions) != versions do
      raise InvalidKeyError, "Each key version CLOAK_KEY_V<n> may appear only once"
    end

    keys =
      entries
      |> Enum.map(fn {version, value} -> {version, decode!(env_name(version), value)} end)
      |> Enum.sort_by(&elem(&1, 0), :desc)

    check_distinct!(keys)
    keys
  end

  def cipher_keys!(_entries) do
    raise InvalidKeyError, "No encryption key is configured; set CLOAK_KEY_V1"
  end

  @doc """
  Checks the keys of `Espalier.Vault` and the secret of `Espalier.Hashed.HMAC`
  from the application environment, and logs which tags encrypt and which
  only decrypt.
  """
  @spec check!() :: :ok
  def check! do
    keys =
      :espalier
      |> Application.fetch_env!(Espalier.Vault)
      |> Keyword.get(:keys, [])
      |> cipher_keys!()

    secret =
      decode!(
        "CLOAK_HMAC_SECRET",
        Application.fetch_env!(:espalier, Espalier.Hashed.HMAC)[:secret]
      )

    if Enum.any?(keys, fn {_version, key} -> key == secret end) do
      raise InvalidKeyError, "CLOAK_HMAC_SECRET must differ from every CLOAK_KEY_V<n>"
    end

    Logger.info(describe(keys))
  end

  defp version!({version, _value}) when is_integer(version) and version > 0, do: version

  defp version!(_entry) do
    raise InvalidKeyError,
          "Key versions must be positive integers (CLOAK_KEY_V1, CLOAK_KEY_V2, ...)"
  end

  defp check_distinct!(keys) do
    duplicate =
      keys
      |> Enum.group_by(fn {_version, key} -> key end, fn {version, _key} -> version end)
      |> Enum.find_value(fn {_key, versions} -> if length(versions) > 1, do: versions end)

    if duplicate do
      names = duplicate |> Enum.sort() |> Enum.map_join(" and ", &env_name/1)
      raise InvalidKeyError, "#{names} hold the same key"
    end
  end

  defp describe([{current, _key} | retired]) do
    case Enum.map(retired, fn {version, _key} -> tag(version) end) do
      [] -> "Encryption keys: #{tag(current)} encrypts"
      [one] -> "Encryption keys: #{tag(current)} encrypts, #{one} decrypts only"
      many -> "Encryption keys: #{tag(current)} encrypts, #{Enum.join(many, ", ")} decrypt only"
    end
  end

  defp env_name(version), do: "CLOAK_KEY_V#{version}"

  defp invalid_message(name), do: "#{name} must be 32 random bytes, Base64-encoded"
end
