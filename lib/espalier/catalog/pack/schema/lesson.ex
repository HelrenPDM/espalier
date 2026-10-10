defmodule Espalier.Catalog.Pack.Schema.Lesson do
  @moduledoc """
  The front matter of a lesson file `modules/<directory>/lessons/<key>.md`:
  `title` and `position` (at least 1). The blocks of the body follow
  `Espalier.Catalog.Pack.Schema.Block`.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :title, :string
    field :position, :integer
  end

  @type t :: %__MODULE__{}

  @doc "Casts the front matter of a lesson file."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(lesson, attrs) do
    lesson
    |> Cast.cast(attrs, required: [:title, :position])
    |> Cast.validate_max_length(:title)
    |> Cast.validate_min(:position, 1)
  end
end
