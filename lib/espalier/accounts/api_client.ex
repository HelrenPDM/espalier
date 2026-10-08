defmodule Espalier.Accounts.ApiClient do
  @moduledoc """
  A machine client of the integration API. It belongs to no user. The table
  stores the SHA-256 hash of its 32-byte token; the raw token is shown once
  at creation.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @allowed_scopes ["credentials:read"]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "api_clients" do
    field :name, :string
    field :token_hash, :binary, redact: true
    field :scopes, {:array, :string}
    field :last_used_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "The scopes a client may hold."
  def allowed_scopes, do: @allowed_scopes

  @doc false
  def changeset(api_client, attrs) do
    api_client
    |> cast(attrs, [:name, :scopes])
    |> validate_required([:name, :token_hash, :scopes])
    |> validate_length(:name, min: 1, max: 100)
    |> validate_length(:scopes, min: 1)
    |> validate_subset(:scopes, @allowed_scopes)
    |> unique_constraint(:token_hash)
  end
end
