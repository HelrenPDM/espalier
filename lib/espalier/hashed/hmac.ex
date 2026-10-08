defmodule Espalier.Hashed.HMAC do
  @moduledoc """
  Ecto type that stores HMAC-SHA256 of a string under `CLOAK_HMAC_SECRET`, for
  equality lookups of encrypted values.

  Rules (AGENTS.md, `docs/security/crypto-inventory.md`):

    * the column type is `:binary` (`bytea` in PostgreSQL);
    * the field carries `redact: true`, because after `put_change/3` and an
      insert the struct still holds the plaintext;
    * the type never appears inside `embedded_schema`, `embeds_one` or
      `embeds_many`, because Cloak types embed as plaintext JSON.

  The lookup is case-sensitive, so the caller normalizes the value before it
  is hashed, both when it writes and when it queries.

  `dump/1` hashes every binary it receives, and `load/1` returns the stored
  hash. A hash loaded from one row and written into another row through this
  type is therefore hashed a second time and matches no lookup. A keyed hash
  that is copied from row to row, or carried through the session or a sign-in
  ticket, lives in a plain `:binary` field with `redact: true`, filled once
  with `hash/1` of the normalized plaintext; every copy takes the stored bytes
  unchanged, and every lookup compares with `hash/1` of the presented value.

  The hash function is SHA-256 whatever the configuration says.
  """
  use Cloak.Ecto.HMAC, otp_app: :espalier

  alias Espalier.Crypto.Keys

  @impl Cloak.Ecto.HMAC
  def init(config) do
    secret = Keys.decode!("CLOAK_HMAC_SECRET", config[:secret])
    {:ok, Keyword.merge(config, algorithm: :sha256, secret: secret)}
  end

  @doc "Returns the keyed hash that dump/1 stores, for plain :binary columns and for comparisons outside a query."
  @spec hash(binary()) :: binary()
  def hash(value) when is_binary(value) do
    {:ok, digest} = dump(value)
    digest
  end
end
