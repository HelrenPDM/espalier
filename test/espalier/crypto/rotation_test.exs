defmodule Espalier.Crypto.RotationTest do
  # with_vault_keys/2 restarts the vault.
  use Espalier.CryptoCase, async: false

  alias Espalier.Crypto.{Rotation, SchemaRules}

  @test_key Base.encode64(String.duplicate("t", 32))
  @k2 Base.encode64(:crypto.strong_rand_bytes(32))
  @columns [
    {"crypto_samples", "email"},
    {"crypto_samples", "profile"},
    {"crypto_samples", "secret"}
  ]

  setup do
    for {email, profile} <- [
          {"a@example.org", %{"n" => 1}},
          {"b@example.org", nil},
          {"c@example.org", %{"n" => 3}}
        ] do
      %CryptoSample{}
      |> CryptoSample.changeset(%{email: email, profile: profile, secret: "secret-#{email}"})
      |> Repo.insert!()
    end

    Repo.query!("UPDATE crypto_samples SET updated_at = '2000-01-01 00:00:00'")
    :ok
  end

  test "rewrites every value under the new key and keeps updated_at" do
    assert Rotation.tag_counts(Repo, [CryptoSampleRotation]) == %{
             {"crypto_samples", "email"} => %{"AES.GCM.V1" => 3},
             {"crypto_samples", "profile"} => %{"AES.GCM.V1" => 2},
             {"crypto_samples", "secret"} => %{"AES.GCM.V1" => 3}
           }

    with_vault_keys([{2, @k2}, {1, @test_key}], fn ->
      assert Rotation.run(Repo, [CryptoSampleRotation]) == %{CryptoSampleRotation => 3}

      assert Rotation.tag_counts(Repo, [CryptoSampleRotation]) == %{
               {"crypto_samples", "email"} => %{"AES.GCM.V2" => 3},
               {"crypto_samples", "profile"} => %{"AES.GCM.V2" => 2},
               {"crypto_samples", "secret"} => %{"AES.GCM.V2" => 3}
             }

      # A second run in batches of two rewrites the rows again.
      assert Rotation.run(Repo, [CryptoSampleRotation], batch_size: 2) == %{
               CryptoSampleRotation => 3
             }
    end)

    with_vault_keys([{2, @k2}], fn ->
      samples = Repo.all(from s in CryptoSample, order_by: s.email_hash)
      assert length(samples) == 3

      for sample <- samples do
        assert sample.email in ["a@example.org", "b@example.org", "c@example.org"]
        assert sample.secret.() == "secret-#{sample.email}"
        assert sample.updated_at == ~U[2000-01-01 00:00:00Z]
      end

      assert %CryptoSample{profile: nil} = Repo.get_by(CryptoSample, email_hash: "b@example.org")

      assert %CryptoSample{profile: %{"n" => 3}} =
               Repo.get_by(CryptoSample, email_hash: "c@example.org")
    end)
  end

  test "validate!/1 accepts only a primary key and encrypted fields" do
    assert Rotation.validate!(CryptoSampleRotation) == CryptoSampleRotation

    assert_raise ArgumentError, ~r/no rotation-only schema/, fn ->
      Rotation.validate!(CryptoSample)
    end

    assert_raise ArgumentError, fn -> Rotation.run(Repo, [CryptoSample]) end
  end

  test "uncovered/2 lists encrypted columns without a rotation schema" do
    assert Rotation.uncovered([CryptoSample], []) == @columns
    assert Rotation.uncovered([CryptoSample], [CryptoSampleRotation]) == []
    assert Rotation.uncovered(SchemaRules.app_schemas(), Rotation.schemas()) == []
  end

  test "every registered rotation schema is valid" do
    for schema <- Rotation.schemas(), do: assert(Rotation.validate!(schema) == schema)
  end
end
