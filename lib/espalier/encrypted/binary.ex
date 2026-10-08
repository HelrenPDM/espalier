defmodule Espalier.Encrypted.Binary do
  @moduledoc """
  Ecto type that stores a string as AES-256-GCM ciphertext through
  `Espalier.Vault`.

  Rules (AGENTS.md, `docs/security/crypto-inventory.md`):

    * the column type is `:binary` (`bytea` in PostgreSQL);
    * the field carries `redact: true`;
    * the type never appears inside `embedded_schema`, `embeds_one` or
      `embeds_many`, because Cloak types embed as plaintext JSON;
    * every table with such a field has a rotation-only schema registered in
      `Espalier.Crypto.Rotation.schemas/0`.

  SQL cannot sort, range-filter or search the column. Lookups go through a
  keyed hash column of type `Espalier.Hashed.HMAC`.
  """
  use Cloak.Ecto.Binary, vault: Espalier.Vault
end
