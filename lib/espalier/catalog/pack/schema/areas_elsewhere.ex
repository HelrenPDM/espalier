defmodule Espalier.Catalog.Pack.Schema.AreasElsewhere do
  @moduledoc """
  `areas_elsewhere` of `module.yaml`: maps a competence area (`subject`,
  `method`, `self` or `social`) that the module's own objectives leave out
  to the place where it is covered (`Espalier.Catalog.Pack.Schema.Elsewhere`).
  Any other key is an error.
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.{Cast, Elsewhere}

  @areas [:subject, :method, :self, :social]

  @primary_key false
  embedded_schema do
    embeds_one :subject, Elsewhere
    embeds_one :method, Elsewhere
    embeds_one :self, Elsewhere
    embeds_one :social, Elsewhere
  end

  @type t :: %__MODULE__{}

  @doc "The four competence areas in their order."
  @spec areas() :: [atom()]
  def areas, do: @areas

  @doc "Casts `areas_elsewhere`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(areas_elsewhere, attrs) do
    Cast.cast(areas_elsewhere, attrs,
      unknown: &"unknown competence area `#{&1}` in `areas_elsewhere`"
    )
  end
end
