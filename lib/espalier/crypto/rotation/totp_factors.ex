defmodule Espalier.Crypto.Rotation.TotpFactors do
  @moduledoc "Rotation-only schema of the table `totp_factors` (`Espalier.Crypto.Rotation`)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "totp_factors" do
    field :secret, Espalier.Encrypted.ClosureBinary, redact: true
  end
end
