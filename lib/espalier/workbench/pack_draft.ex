defmodule Espalier.Workbench.PackDraft do
  @moduledoc """
  A draft of the pack workbench (task 0016a, step 2): the working copy of a
  content pack that authors edit in the admin area.

  A draft is a working copy of an author and belongs to no learner record:
  `created_by_id` names the author who started it, as `audit_events.actor_id`
  does, and becomes `nil` when that account is deleted. The table holds no
  encrypted and no keyed-hash column; a draft holds course content, the data
  class of the catalog tables and of `pack_imports.payload`.

  `Espalier.Workbench` alone sets `title`, `pack_key`, `lock_version` and
  `created_by_id` on the struct or in its queries; no request casts them
  (ASVS 15.3.3). `lock_version` grows by one with each file change, so a
  change sent with an older version answers `stale_draft`.

  `file_count` and `bytes` are virtual: `Espalier.Workbench` fills them from
  an aggregate query or from the files it loads.
  """
  use Ecto.Schema

  alias Espalier.Workbench.{PackDraftFile, PackDraftMedia}

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pack_drafts" do
    field :title, :string
    field :pack_key, :string
    field :lock_version, :integer, default: 1
    field :created_by_id, :binary_id
    field :file_count, :integer, virtual: true
    field :bytes, :integer, virtual: true
    has_many :files, PackDraftFile
    has_many :media, PackDraftMedia

    timestamps(type: :utc_datetime)
  end
end
