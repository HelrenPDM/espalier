defmodule Espalier.Accounts.AuthChallenge do
  @moduledoc """
  A WebAuthn challenge, stored on the server for one ceremony
  (`Espalier.Accounts.Challenges`). Its id is the ceremony id in the session
  cookie; the bytes never leave the server except in the options JSON. A
  sign-in challenge has no user.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "auth_challenges" do
    field :purpose, Ecto.Enum, values: [:registration, :sign_in, :second_factor, :reauth]
    field :challenge, :binary, redact: true
    field :expires_at, :utc_datetime
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(auth_challenge, attrs) do
    auth_challenge
    |> cast(attrs, [:purpose, :challenge, :expires_at, :user_id])
    |> validate_required([:purpose, :challenge, :expires_at])
  end
end
