defmodule Espalier.Repo.Migrations.CreateMediaAssets do
  use Ecto.Migration

  # The media library of task 0018 (step 3). Media are course content and
  # belong to no learner record, so the table has no user_id; created_by_id
  # names the uploader as audit_events.actor_id names an actor.
  def change do
    create table(:media_assets, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :status, :string, null: false
      add :failure, :string
      add :failure_detail, :string
      add :title, :string, null: false
      add :source_name, :string
      add :source_sha256, :string, size: 64, null: false
      add :sha256, :string, size: 64
      add :ext, :string
      add :bytes, :bigint
      add :width, :integer
      add :height, :integer
      add :duration_ms, :integer
      add :has_audio, :boolean, default: false, null: false
      add :animated, :boolean, default: false, null: false
      add :has_alpha, :boolean, default: false, null: false
      add :poster_sha256, :string, size: 64
      add :poster_bytes, :bigint
      add :incoming_bytes, :bigint, default: 0, null: false
      add :progress, :integer, default: 0, null: false
      add :origin, :string, null: false
      add :created_by_id, references(:users, on_delete: :nilify_all, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:media_assets, [:created_by_id])
    create unique_index(:media_assets, [:source_sha256])
    # Two sources can convert to the same bytes, and two videos can share a
    # poster; such assets share one stored file.
    create index(:media_assets, [:sha256])
    create index(:media_assets, [:poster_sha256])
    create index(:media_assets, [:status, :updated_at])
  end
end
