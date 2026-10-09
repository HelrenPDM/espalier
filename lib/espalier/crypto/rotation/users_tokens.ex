defmodule Espalier.Crypto.Rotation.UsersTokens do
  @moduledoc "Rotation-only schema of the table `users_tokens` (`Espalier.Crypto.Rotation`)."
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  schema "users_tokens" do
    field :new_email, Espalier.Encrypted.Binary, redact: true
    field :link_identity, Espalier.Encrypted.Binary, redact: true
  end
end
