defmodule Espalier.Encrypted.Map do
  @moduledoc """
  Ecto type that stores a map as JSON in AES-256-GCM ciphertext through
  `Espalier.Vault`. Structured personal data goes into one column of this
  type. The map is stored as JSON, so atom keys load as string keys.

  Rules (AGENTS.md, `docs/security/crypto-inventory.md`):

    * the column type is `:binary` (`bytea` in PostgreSQL);
    * the field carries `redact: true`;
    * the type never appears inside `embedded_schema`, `embeds_one` or
      `embeds_many`, because Cloak types embed as plaintext JSON;
    * every table with such a field has a rotation-only schema registered in
      `Espalier.Crypto.Rotation.schemas/0`.
  """
  use Cloak.Ecto.Map, vault: Espalier.Vault
end
