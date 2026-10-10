defmodule Espalier.Catalog.Pack.Schema.Elsewhere do
  @moduledoc """
  An entry of `areas_elsewhere`: `where`, of the form `format:<format key>`
  or `module:<module number>`, and `reason`, a text that states what the
  named place covers. The validator resolves `where`.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @where_regex ~r/\A(format:[a-z0-9][a-z0-9-]*|module:[1-9][0-9]*)\z/

  @primary_key false
  embedded_schema do
    field :where, :string
    field :reason, :string
  end

  @type t :: %__MODULE__{}

  @doc "Casts an entry of `areas_elsewhere`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(elsewhere, attrs) do
    elsewhere
    |> Cast.cast(attrs, required: [:where, :reason])
    |> Cast.validate_regex(
      :where,
      @where_regex,
      "`where` must have the form `format:<format key>` or `module:<module number>`"
    )
  end
end
