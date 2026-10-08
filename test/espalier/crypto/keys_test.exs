defmodule Espalier.Crypto.KeysTest do
  # check!/0 reads the application environment, which some tests change.
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Espalier.Crypto.{InvalidKeyError, Keys}

  @key_a :crypto.strong_rand_bytes(32)
  @key_b :crypto.strong_rand_bytes(32)

  describe "decode!/2" do
    test "decodes a Base64 value of 32 bytes, also with surrounding whitespace" do
      assert Keys.decode!("CLOAK_KEY_V1", Base.encode64(@key_a)) == @key_a
      assert Keys.decode!("CLOAK_KEY_V1", " " <> Base.encode64(@key_a) <> "\n") == @key_a
    end

    test "raises for a missing, malformed or wrong-sized value without showing it" do
      invalid = [
        nil,
        "",
        "not base64!",
        String.trim_trailing(Base.encode64(@key_a), "="),
        Base.encode64(:crypto.strong_rand_bytes(31)),
        Base.encode64(:crypto.strong_rand_bytes(33)),
        @key_a
      ]

      for value <- invalid do
        error = assert_raise InvalidKeyError, fn -> Keys.decode!("CLOAK_KEY_V1", value) end
        assert error.message == "CLOAK_KEY_V1 must be 32 random bytes, Base64-encoded"
        refute_leak(error, value)
      end
    end
  end

  describe "cipher_keys!/1" do
    test "returns the decoded keys, highest version first" do
      entries = [{1, Base.encode64(@key_a)}, {2, Base.encode64(@key_b)}]
      assert Keys.cipher_keys!(entries) == [{2, @key_b}, {1, @key_a}]
    end

    test "names the variable of an invalid key" do
      entries = [{1, Base.encode64(@key_a)}, {2, "short"}]
      error = assert_raise InvalidKeyError, fn -> Keys.cipher_keys!(entries) end
      assert error.message =~ "CLOAK_KEY_V2"
    end

    test "raises without keys, for duplicate or invalid versions and for duplicate keys" do
      a = Base.encode64(@key_a)
      b = Base.encode64(@key_b)

      for entries <- [[], nil, [{1, a}, {1, b}], [{0, a}], [{"1", a}], [a]] do
        error = assert_raise InvalidKeyError, fn -> Keys.cipher_keys!(entries) end
        refute_leak(error, a)
        refute_leak(error, @key_a)
      end

      error = assert_raise InvalidKeyError, fn -> Keys.cipher_keys!([{1, a}, {3, b}, {2, a}]) end
      assert error.message == "CLOAK_KEY_V1 and CLOAK_KEY_V2 hold the same key"
    end
  end

  describe "check!/0" do
    setup do
      vault = Application.fetch_env!(:espalier, Espalier.Vault)
      hmac = Application.fetch_env!(:espalier, Espalier.Hashed.HMAC)
      level = Logger.level()

      on_exit(fn ->
        Application.put_env(:espalier, Espalier.Vault, vault)
        Application.put_env(:espalier, Espalier.Hashed.HMAC, hmac)
        Logger.configure(level: level)
      end)

      %{vault: vault}
    end

    test "logs which tags encrypt and decrypt, without key material", %{vault: vault} do
      Logger.configure(level: :info)
      [{1, test_key}] = vault[:keys]

      log = capture_log([level: :info], fn -> assert :ok = Keys.check!() end)
      assert log =~ "Encryption keys: AES.GCM.V1 encrypts"
      refute log =~ test_key

      Application.put_env(:espalier, Espalier.Vault,
        keys: [{1, test_key}, {2, Base.encode64(@key_b)}]
      )

      log = capture_log([level: :info], fn -> assert :ok = Keys.check!() end)
      assert log =~ "Encryption keys: AES.GCM.V2 encrypts, AES.GCM.V1 decrypts only"
      refute log =~ test_key
      refute log =~ Base.encode64(@key_b)
    end

    test "raises when the HMAC secret equals an encryption key", %{vault: vault} do
      [{1, test_key}] = vault[:keys]
      Application.put_env(:espalier, Espalier.Hashed.HMAC, secret: test_key)

      error = assert_raise InvalidKeyError, fn -> Keys.check!() end
      assert error.message == "CLOAK_HMAC_SECRET must differ from every CLOAK_KEY_V<n>"
      refute_leak(error, test_key)
    end

    test "raises when the HMAC secret is missing" do
      Application.put_env(:espalier, Espalier.Hashed.HMAC, secret: nil)

      assert_raise InvalidKeyError, ~r/\ACLOAK_HMAC_SECRET must be 32 random bytes/, fn ->
        Keys.check!()
      end
    end
  end

  defp refute_leak(_error, value) when value in [nil, ""], do: :ok

  defp refute_leak(error, value) do
    refute Exception.message(error) =~ value
    refute inspect(error) =~ value
  end
end
