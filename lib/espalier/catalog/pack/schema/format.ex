defmodule Espalier.Catalog.Pack.Schema.Format do
  @moduledoc """
  An entry of `formats.yaml`, a companion format: `key`, `title`,
  `description`, `phases`, `attendance_counts` and the optional `objectives`,
  the keys of the objectives of the pack that the format anchors or, with
  `attendance_counts: true`, provides evidence for.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @phases [:orient, :understand, :apply, :anchor, :update]

  @primary_key false
  embedded_schema do
    field :key, :string
    field :title, :string
    field :description, :string
    field :phases, {:array, Ecto.Enum}, values: @phases
    field :attendance_counts, :boolean
    field :objectives, {:array, :string}
  end

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `formats.yaml`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(format, attrs) do
    format
    |> Cast.cast(attrs, required: [:key, :title, :description, :attendance_counts])
    |> Cast.validate_key(:key)
    |> Cast.validate_max_length(:title)
    |> Cast.validate_unique(:phases)
    |> Cast.validate_keys(:objectives)
    |> Cast.validate_unique(:objectives)
  end
end
