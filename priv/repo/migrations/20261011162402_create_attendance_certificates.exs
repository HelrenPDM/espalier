defmodule Espalier.Repo.Migrations.CreateAttendanceCertificates do
  use Ecto.Migration

  def change do
    create table(:attendance_certificates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :held_on, :date, null: false

      add :companion_format_id,
          references(:companion_formats, on_delete: :nothing, type: :binary_id),
          null: false

      add :issued_by_id, references(:users, on_delete: :nilify_all, type: :binary_id)
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:attendance_certificates, [:user_id])

    create index(:attendance_certificates, [:companion_format_id])
    create index(:attendance_certificates, [:issued_by_id])
    # The default name exceeds the 63 bytes of a PostgreSQL identifier.
    create unique_index(:attendance_certificates, [:user_id, :companion_format_id, :held_on],
             name: :attendance_certificates_user_format_day_index
           )
  end
end
