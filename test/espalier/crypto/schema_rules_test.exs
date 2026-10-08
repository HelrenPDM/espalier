defmodule Espalier.Crypto.SchemaRulesTest do
  use ExUnit.Case, async: true

  alias Espalier.Crypto.SchemaRules

  # Neither schema carries `redact: true`: Ecto would derive Inspect for it,
  # which the consolidated protocols of the test run ignore with a warning.
  defmodule EmbeddedContact do
    use Ecto.Schema

    embedded_schema do
      field :phone, Espalier.Encrypted.Binary
      field :phone_hash, Espalier.Hashed.HMAC
      field :label, :string
    end
  end

  defmodule UnredactedContact do
    use Ecto.Schema

    schema "contacts" do
      field :phone, Espalier.Encrypted.Binary
      field :label, :string
    end
  end

  test "no schema of the application breaks a rule" do
    schemas = SchemaRules.app_schemas()
    assert SchemaRules.embedded_cloak_fields(schemas) == []
    assert SchemaRules.unredacted_cloak_fields(schemas) == []
  end

  test "app_schemas/0 leaves out test schemas" do
    refute Espalier.Test.CryptoSample in SchemaRules.app_schemas()
  end

  test "reports encrypted and hashed fields inside an embedded schema" do
    assert SchemaRules.embedded_cloak_fields([EmbeddedContact, UnredactedContact]) ==
             [{EmbeddedContact, :phone}, {EmbeddedContact, :phone_hash}]
  end

  test "reports encrypted and hashed fields without redact: true" do
    assert SchemaRules.unredacted_cloak_fields([EmbeddedContact, UnredactedContact]) ==
             [
               {EmbeddedContact, :phone},
               {EmbeddedContact, :phone_hash},
               {UnredactedContact, :phone}
             ]

    assert SchemaRules.unredacted_cloak_fields([Espalier.Test.CryptoSample]) == []
  end

  test "cloak_type?/1 recognizes Cloak types, also nested" do
    for type <- [
          Espalier.Encrypted.Binary,
          Espalier.Encrypted.Map,
          Espalier.Encrypted.ClosureBinary,
          Espalier.Hashed.HMAC,
          Cloak.Ecto.SHA256,
          {:array, Espalier.Encrypted.Binary},
          {:map, Espalier.Hashed.HMAC},
          {:parameterized, {Espalier.Encrypted.Binary, %{}}}
        ] do
      assert SchemaRules.cloak_type?(type), inspect(type)
    end

    for type <- [
          :string,
          :binary,
          :binary_id,
          {:array, :string},
          {:parameterized, {Ecto.Enum, %{}}}
        ] do
      refute SchemaRules.cloak_type?(type), inspect(type)
    end
  end
end
