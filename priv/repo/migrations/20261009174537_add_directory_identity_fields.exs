defmodule Espalier.Repo.Migrations.AddDirectoryIdentityFields do
  use Ecto.Migration

  # Task 0007, step 13: the encrypted directory attributes of an identity,
  # and directory failure counters keyed by provider key and subject hash,
  # which exist before the platform account.
  def change do
    alter table(:external_identities) do
      add :directory_dn, :binary
      add :directory_upn, :binary
      add :directory_login, :binary
    end

    execute "ALTER TABLE failure_counters ALTER COLUMN user_id DROP NOT NULL",
            "ALTER TABLE failure_counters ALTER COLUMN user_id SET NOT NULL"

    alter table(:failure_counters) do
      add :provider_key, :string
      add :subject_hash, :binary
    end

    create constraint(:failure_counters, :failure_counters_owner,
             check:
               "user_id IS NOT NULL OR (provider_key IS NOT NULL AND subject_hash IS NOT NULL)"
           )

    # The unique index on (user_id, authenticator) stays: NULL values are
    # distinct, so directory rows without user_id never conflict under it.
    create unique_index(:failure_counters, [:authenticator, :provider_key, :subject_hash],
             where: "subject_hash IS NOT NULL"
           )
  end
end
