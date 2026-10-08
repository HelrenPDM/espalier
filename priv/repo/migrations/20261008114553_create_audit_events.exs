defmodule Espalier.Repo.Migrations.CreateAuditEvents do
  use Ecto.Migration

  def change do
    create table(:audit_events, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :action, :string
      add :subject_type, :string
      add :subject_id, :uuid
      add :details, :map
      add :at, :utc_datetime
      add :actor_id, references(:users, on_delete: :nilify_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:audit_events, [:actor_id])
    create index(:audit_events, [:at])
    create index(:audit_events, [:action])
  end
end
