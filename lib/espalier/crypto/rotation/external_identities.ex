defmodule Espalier.Crypto.Rotation.ExternalIdentities do
  @moduledoc "Rotation-only schema of the table `external_identities` (`Espalier.Crypto.Rotation`)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "external_identities" do
    field :subject, Espalier.Encrypted.Binary, redact: true
  end
end
