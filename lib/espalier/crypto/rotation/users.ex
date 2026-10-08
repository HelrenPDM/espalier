defmodule Espalier.Crypto.Rotation.Users do
  @moduledoc "Rotation-only schema of the table `users` (`Espalier.Crypto.Rotation`)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "users" do
    field :email, Espalier.Encrypted.Binary, redact: true
    field :display_name, Espalier.Encrypted.Binary, redact: true
    field :org_unit, Espalier.Encrypted.Binary, redact: true
  end
end
