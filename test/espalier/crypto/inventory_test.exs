defmodule Espalier.Crypto.InventoryTest do
  use ExUnit.Case, async: true

  alias Espalier.Crypto.SchemaRules

  @inventory "docs/security/crypto-inventory.md"

  test "every encrypted, hashed and password-hash field of the application is in the inventory" do
    assert missing(SchemaRules.app_schemas(), File.read!(@inventory)) == []
  end

  test "the check finds protected fields by type and by name" do
    assert missing([Espalier.Test.CryptoSample], "") == [
             "crypto_samples.email",
             "crypto_samples.email_hash",
             "crypto_samples.profile",
             "crypto_samples.secret"
           ]

    assert missing([Espalier.Test.CryptoSample], "`crypto_samples.email`") == [
             "crypto_samples.email_hash",
             "crypto_samples.profile",
             "crypto_samples.secret"
           ]
  end

  # The name rule covers the plain :binary columns of the levels `keyed hash`,
  # `hash` and `password hash`, which no Cloak type marks.
  defp missing(schemas, inventory) do
    for schema <- schemas,
        table = schema.__schema__(:source),
        table != nil,
        field <- schema.__schema__(:fields),
        protected?(schema, field),
        column = "#{table}.#{schema.__schema__(:field_source, field)}",
        not String.contains?(inventory, "`#{column}`"),
        do: column
  end

  defp protected?(schema, field) do
    name = Atom.to_string(field)

    SchemaRules.cloak_type?(schema.__schema__(:type, field)) or
      String.ends_with?(name, ["_hash", "_hmac"]) or name == "hashed_password"
  end
end
