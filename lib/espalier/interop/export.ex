defmodule Espalier.Interop.Export do
  @moduledoc """
  A SCORM export of one module of a published program (task 0016, step 6).

  An export is an administrative record and belongs to no learner record:
  `requested_by_id` names the requesting author, as `audit_events.actor_id`
  does, and becomes `nil` when that account is deleted. The table holds no
  encrypted and no keyed-hash column.

  The status runs from `queued` (`Espalier.Interop.request_export/3`)
  through `running` to `done` or `failed` (`Espalier.Interop.ExportWorker`).
  A `done` export carries `file_name`, the plain basename `<id>.zip` of the
  package below `EXPORT_DIR`; a `failed` export carries a short text in
  `error`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Catalog.Program

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "exports" do
    field :scorm_version, Ecto.Enum, values: [:scorm12, :scorm2004]
    field :status, Ecto.Enum, values: [:queued, :running, :done, :failed], default: :queued
    field :file_name, :string
    field :error, :string
    belongs_to :program, Program
    belongs_to :module, CatalogModule
    field :requested_by_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @typedoc "A row of the table `exports`."
  @type t :: %__MODULE__{}

  @doc """
  The changeset of a new export. `Espalier.Interop` sets the program, the
  module and the requesting author on the struct; only `scorm_version` is
  cast.
  """
  def request_changeset(%__MODULE__{} = export, attrs) do
    export
    |> cast(attrs, [:scorm_version])
    |> validate_required([:program_id, :module_id, :scorm_version, :status])
  end

  @doc "The changeset of a status change by the export worker."
  def status_changeset(%__MODULE__{} = export, attrs) do
    export
    |> cast(attrs, [:status, :file_name, :error])
    |> validate_required([:status])
  end
end
