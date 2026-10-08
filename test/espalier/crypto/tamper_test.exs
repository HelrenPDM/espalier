defmodule Espalier.Crypto.TamperTest do
  # with_vault_keys/2 restarts the vault.
  use Espalier.CryptoCase, async: false

  alias Espalier.Crypto.DecryptError

  @other_key Base.encode64(:crypto.strong_rand_bytes(32))

  setup do
    sample =
      %CryptoSample{}
      |> CryptoSample.changeset(%{email: "t@example.org", profile: %{"a" => 1}, secret: "s3cret"})
      |> Repo.insert!()

    %{sample: sample}
  end

  test "a changed byte in any encrypted column makes the read raise", %{sample: sample} do
    for column <- ~w(email profile secret) do
      original = raw_column(column, sample.id)
      put_raw_column(column, sample.id, flip_bit(original, byte_size(original) - 1))

      assert_raise ArgumentError, ~r/cannot load/, fn -> Repo.get!(CryptoSample, sample.id) end

      put_raw_column(column, sample.id, original)
      assert Repo.get!(CryptoSample, sample.id)
    end
  end

  test "another key under the same tag makes the read raise", %{sample: sample} do
    with_vault_keys([{1, @other_key}], fn ->
      assert_raise ArgumentError, ~r/cannot load/, fn -> Repo.get!(CryptoSample, sample.id) end
    end)

    assert Repo.get!(CryptoSample, sample.id).email == "t@example.org"
  end

  test "a value whose tag no cipher carries makes the read raise", %{sample: sample} do
    with_vault_keys([{2, @other_key}], fn ->
      assert_raise ArgumentError, ~r/cannot load/, fn -> Repo.get!(CryptoSample, sample.id) end
    end)
  end

  test "decrypt!/1 raises DecryptError for a changed value" do
    ciphertext = Espalier.Vault.encrypt!("plaintext")
    tampered = flip_bit(ciphertext, byte_size(ciphertext) - 1)

    assert Espalier.Vault.decrypt!(ciphertext) == "plaintext"
    assert_raise DecryptError, "decryption failed", fn -> Espalier.Vault.decrypt!(tampered) end
  end
end
