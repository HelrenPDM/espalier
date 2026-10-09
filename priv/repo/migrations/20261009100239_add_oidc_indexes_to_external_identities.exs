defmodule Espalier.Repo.Migrations.AddOidcIndexesToExternalIdentities do
  use Ecto.Migration

  # One identity per provider and account (task 0006, step 6).
  def change do
    create unique_index(:external_identities, [:user_id, :provider_key])
  end
end
