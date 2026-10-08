defmodule Espalier.Audit.AuditEvent do
  @moduledoc """
  One administrative action. `details` holds role names, provider keys and
  counts, and no personal data. Rows are append-only.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "audit_events" do
    field :action, :string
    field :subject_type, :string
    field :subject_id, Ecto.UUID
    field :details, :map, default: %{}
    field :at, :utc_datetime
    field :actor_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(audit_event, attrs) do
    audit_event
    |> cast(attrs, [:action, :subject_type, :subject_id, :details, :at, :actor_id])
    |> validate_required([:action, :at])
  end
end
