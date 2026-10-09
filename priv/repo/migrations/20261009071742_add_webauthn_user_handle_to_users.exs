defmodule Espalier.Repo.Migrations.AddWebauthnUserHandleToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :webauthn_user_handle, :binary
    end

    create unique_index(:users, [:webauthn_user_handle])
  end
end
