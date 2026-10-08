defmodule Espalier.Test.CryptoSample do
  @moduledoc """
  Full schema on the temporary table `crypto_samples` of `Espalier.CryptoCase`,
  with one field of each encrypted and hashed type. The `Ecto.Enum` field and
  the timestamps give the table the shape on which `mix cloak.migrate.ecto`
  crashes and changes `updated_at`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "crypto_samples" do
    field :email, Espalier.Encrypted.Binary, redact: true
    field :email_hash, Espalier.Hashed.HMAC, redact: true
    field :profile, Espalier.Encrypted.Map, redact: true
    field :secret, Espalier.Encrypted.ClosureBinary, redact: true
    field :status, Ecto.Enum, values: [:active, :disabled]
    timestamps(type: :utc_datetime)
  end

  def changeset(sample, attrs) do
    sample
    |> cast(attrs, [:email, :profile, :secret, :status])
    |> then(&put_change(&1, :email_hash, get_field(&1, :email)))
    |> unique_constraint(:email, name: :crypto_samples_email_hash_index)
  end
end

defmodule Espalier.Test.CryptoSampleRotation do
  @moduledoc "Rotation-only schema of the table `crypto_samples`."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "crypto_samples" do
    field :email, Espalier.Encrypted.Binary, redact: true
    field :profile, Espalier.Encrypted.Map, redact: true
    field :secret, Espalier.Encrypted.ClosureBinary, redact: true
  end
end
