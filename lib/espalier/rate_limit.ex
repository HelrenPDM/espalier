defmodule Espalier.RateLimit do
  @moduledoc """
  Request throttling with Hammer's ETS backend (README section 6.10,
  `docs/security/authentication.md`).

  Buckets are `{scale_ms, limit}` pairs in `config :espalier, :rate_limits`,
  read at every check. IP keys are `{bucket, ip}` with IPv6 addresses reduced
  to their /64 prefix. Account keys are `{bucket, hmac}`, where `hmac` is
  HMAC-SHA256 of the normalized identifier under a key derived once at boot
  from `SECRET_KEY_BASE`, so the limiter never holds an address. Known and
  unknown identifiers share the same buckets.

  The window of a key starts at its first hit (`:fix_window_per_key`). The
  ETS backend counts per node; several nodes would need a shared backend.
  """
  use Hammer, backend: :ets, algorithm: :fix_window_per_key

  alias Plug.Crypto.KeyGenerator

  @key_name {__MODULE__, :key}

  @doc """
  Derives the account key from the secret key base and keeps it in
  `:persistent_term`. Runs at boot.
  """
  @spec init_key(String.t()) :: :ok
  def init_key(secret_key_base) when is_binary(secret_key_base) do
    key = KeyGenerator.generate(secret_key_base, "espalier rate limit", length: 32)
    :persistent_term.put(@key_name, key)
  end

  @doc "Counts a hit of `ip` in `bucket`."
  @spec check_ip(atom(), :inet.ip_address()) :: {:allow, pos_integer()} | {:deny, pos_integer()}
  def check_ip(bucket, ip), do: check(bucket, {bucket, ip_key(ip)})

  @doc "Counts a hit of the normalized `identifier` in `bucket`."
  @spec check_account(atom(), String.t()) :: {:allow, pos_integer()} | {:deny, pos_integer()}
  def check_account(bucket, identifier) when is_binary(identifier) do
    check(bucket, {bucket, mac(identifier)})
  end

  @doc """
  Returns the first eight lowercase hex characters of the account HMAC of
  `identifier`. Security events carry it as `account_hash` for an identifier
  that matches no account.
  """
  @spec account_hash(String.t()) :: String.t()
  def account_hash(identifier) when is_binary(identifier) do
    identifier |> mac() |> Base.encode16(case: :lower) |> binary_part(0, 8)
  end

  defp check(bucket, key) do
    {scale, limit} = Map.fetch!(Application.fetch_env!(:espalier, :rate_limits), bucket)
    hit(key, scale, limit)
  end

  defp mac(identifier) do
    :crypto.mac(:hmac, :sha256, :persistent_term.get(@key_name), normalize(identifier))
  end

  defp normalize(identifier), do: identifier |> String.trim() |> String.downcase()

  defp ip_key({a, b, c, d, _, _, _, _}), do: {a, b, c, d, 0, 0, 0, 0}
  defp ip_key(ip), do: ip
end
