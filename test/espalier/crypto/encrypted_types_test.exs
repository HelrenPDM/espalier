defmodule Espalier.Crypto.EncryptedTypesTest do
  use Espalier.CryptoCase, async: true

  alias Espalier.Hashed.HMAC

  @email "a@example.org"
  @secret "JBSWY3DPEHPK3PXPJBSWY3DP"
  @hmac_secret String.duplicate("s", 32)

  setup do
    sample =
      %CryptoSample{}
      |> CryptoSample.changeset(%{
        email: @email,
        profile: %{name: "Ada", units: ["north"]},
        secret: @secret,
        status: :active
      })
      |> Repo.insert!()

    %{sample: sample}
  end

  test "every type reads back its value", %{sample: sample} do
    loaded = Repo.get!(CryptoSample, sample.id)
    assert loaded.email == @email
    assert loaded.profile == %{"name" => "Ada", "units" => ["north"]}
    assert is_function(loaded.secret, 0)
    assert loaded.secret.() == @secret
    assert loaded.status == :active
  end

  test "the column holds tagged ciphertext without the plaintext", %{sample: sample} do
    raw = raw_column("email", sample.id)
    assert <<1, 10, "AES.GCM.V1", _rest::binary>> = raw
    assert :binary.match(raw, @email) == :nomatch
    assert byte_size(raw) == byte_size(@email) + 40

    assert :binary.match(raw_column("secret", sample.id), @secret) == :nomatch
    assert :binary.match(raw_column("profile", sample.id), "Ada") == :nomatch
  end

  test "the keyed hash finds the row and is case-sensitive", %{sample: sample} do
    raw_hash = raw_column("email_hash", sample.id)
    assert raw_hash == :crypto.mac(:hmac, :sha256, @hmac_secret, @email)
    assert HMAC.hash(@email) == raw_hash

    assert %CryptoSample{id: id} = Repo.get_by(CryptoSample, email_hash: @email)
    assert id == sample.id
    assert Repo.get_by(CryptoSample, email_hash: "A@example.org") == nil

    loaded = Repo.get!(CryptoSample, sample.id)
    assert loaded.email_hash == raw_hash
  end

  test "the type hashes a loaded hash again", %{sample: sample} do
    loaded = Repo.get!(CryptoSample, sample.id)

    copy =
      %CryptoSample{}
      |> Ecto.Changeset.change(email_hash: loaded.email_hash)
      |> Repo.insert!()

    assert raw_column("email_hash", copy.id) == HMAC.hash(HMAC.hash(@email))
  end

  test "a second row with the same address violates the unique index" do
    assert {:error, changeset} =
             %CryptoSample{}
             |> CryptoSample.changeset(%{email: @email})
             |> Repo.insert()

    assert {_message, opts} = changeset.errors[:email]
    assert opts[:constraint_name] == "crypto_samples_email_hash_index"
  end

  test "inspect shows neither the address nor the secret", %{sample: sample} do
    for struct <- [sample, Repo.get!(CryptoSample, sample.id)] do
      output = inspect(struct)
      refute output =~ @email
      refute output =~ @secret
      refute output =~ "Ada"
    end
  end

  test "the HMAC type uses SHA-256 whatever the configuration says" do
    valid = Base.encode64(@hmac_secret)
    assert {:ok, config} = HMAC.init(secret: valid, algorithm: :md5)
    assert config[:algorithm] == :sha256
    assert config[:secret] == @hmac_secret
  end
end
