defmodule Espalier.Repo.Migrations.AddOidcFieldsToUsersTokens do
  use Ecto.Migration

  # Sign-in tickets and OIDC intents (task 0006, step 6). binding_hash holds a
  # keyed hash and link_identity an encrypted value, both on ticket and
  # intent rows only.
  def change do
    alter table(:users_tokens) do
      add :purpose, :string
      add :binding_hash, :binary
      add :idp_amr, {:array, :string}
      add :link_identity, :binary
    end
  end
end
