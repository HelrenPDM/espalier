defmodule Espalier.Catalog.Block do
  @moduledoc """
  A block of a lesson. `collapsed_on` lists the paths on which it starts
  collapsed, and a `placeholder` block names a policy in `placeholder_key`.

  A `figure` or a `video` block (task 0018) holds its attributes in `media`,
  a string-keyed map with the `media/` paths of the pack; the other kinds
  hold `nil`. The body of a figure is its caption and the body of a video
  its transcript, and both may be the empty string.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.{Citation, Lesson}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "blocks" do
    field :position, :integer

    field :kind, Ecto.Enum,
      values: [
        :text,
        :explanation,
        :example,
        :case_comparison,
        :quote,
        :callout,
        :placeholder,
        :figure,
        :video
      ]

    field :body, :string

    field :provenance, Ecto.Enum,
      values: [:invented, :sourced, :vendor_statement, :assumption, :placeholder]

    field :collapsed_on, {:array, Ecto.Enum}, values: [:short, :full], default: []
    field :placeholder_key, :string
    field :media, :map

    belongs_to :lesson, Lesson
    has_many :citations, Citation

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(block, attrs) do
    changeset =
      block
      |> cast(attrs, [
        :position,
        :kind,
        :body,
        :provenance,
        :collapsed_on,
        :placeholder_key,
        :media
      ])
      |> validate_required([:position, :kind, :provenance])

    cond do
      get_field(changeset, :kind) not in [:figure, :video] ->
        validate_required(changeset, [:body])

      get_field(changeset, :body) == nil ->
        put_change(changeset, :body, "")

      true ->
        changeset
    end
  end
end
