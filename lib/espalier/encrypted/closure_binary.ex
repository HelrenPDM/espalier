defmodule Espalier.Encrypted.ClosureBinary do
  @moduledoc """
  Ecto type that stores a string as AES-256-GCM ciphertext through
  `Espalier.Vault` and loads it as a zero-arity function.

  The loaded value is `fn -> plaintext end`, which keeps the plaintext out of
  `inspect/1`, stack traces and JSON; call it to read the value. Casting a
  function stores its result, so a loaded value can be written back
  unchanged. Authenticator secrets such as TOTP secrets use this type.

  Rules (AGENTS.md, `docs/security/crypto-inventory.md`):

    * the column type is `:binary` (`bytea` in PostgreSQL);
    * the field carries `redact: true`;
    * the type never appears inside `embedded_schema`, `embeds_one` or
      `embeds_many`, because Cloak types embed as plaintext JSON;
    * every table with such a field has a rotation-only schema registered in
      `Espalier.Crypto.Rotation.schemas/0`.
  """
  use Cloak.Ecto.Binary, vault: Espalier.Vault, closure: true
end
