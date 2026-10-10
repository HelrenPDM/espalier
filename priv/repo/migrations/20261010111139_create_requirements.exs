defmodule Espalier.Repo.Migrations.CreateRequirements do
  use Ecto.Migration

  def change do
    create table(:requirements, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string
      add :target_key, :string

      add :qualification_id,
          references(:qualifications, on_delete: :delete_all, type: :binary_id),
          null: false

      timestamps(type: :utc_datetime)
    end

    create index(:requirements, [:qualification_id])
  end
end
