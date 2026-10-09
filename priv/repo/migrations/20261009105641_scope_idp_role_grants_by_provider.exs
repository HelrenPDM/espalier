defmodule Espalier.Repo.Migrations.ScopeIdpRoleGrantsByProvider do
  use Ecto.Migration

  # An account can hold one identity per provider (task 0006), so the
  # idp_claim grants of each provider are kept apart. Manual grants have no
  # provider_key; NULLS NOT DISTINCT keeps them unique per role.
  def change do
    drop unique_index(:role_grants, [:user_id, :role, :source])

    create unique_index(:role_grants, [:user_id, :role, :source, :provider_key],
             nulls_distinct: false
           )
  end
end
