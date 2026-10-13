defmodule Espalier.Workbench.PackDraftFile do
  @moduledoc """
  A file of a draft of the pack workbench (task 0016a, step 2): a path of
  the pack layout (`Espalier.Workbench.Paths`) and its text.

  `changeset/2` casts `path` and `content` only (ASVS 15.3.3); the draft is
  set on the struct by `Espalier.Workbench`. A draft holds each path once,
  and a content may be empty (a new YAML file starts empty). `bytes` is
  virtual: the reads that leave out the content fill it with
  `octet_length(content)`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Workbench.PackDraft

  @type t :: %__MODULE__{}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pack_draft_files" do
    field :path, :string
    field :content, :string
    field :bytes, :integer, virtual: true
    belongs_to :pack_draft, PackDraft

    timestamps(type: :utc_datetime)
  end

  @doc "The changeset of a new file or of a change of its path or content."
  def changeset(%__MODULE__{} = file, attrs) do
    file
    |> cast(attrs, [:path, :content], empty_values: [])
    |> validate_required([:path])
    |> unique_constraint([:pack_draft_id, :path])
  end
end
