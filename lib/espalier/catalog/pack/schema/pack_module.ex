defmodule Espalier.Catalog.Pack.Schema.PackModule do
  @moduledoc """
  The schema of `modules/<directory>/module.yaml`: `number` (at least 1),
  `title`, `summary`, `phases`, `domains` (strings in the key format),
  `single_path`, `refresher_unit` and the optional `areas_elsewhere`
  (`Espalier.Catalog.Pack.Schema.AreasElsewhere`).
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.{AreasElsewhere, Cast}

  @phases [:orient, :understand, :apply, :anchor, :update]

  @primary_key false
  embedded_schema do
    field :number, :integer
    field :title, :string
    field :summary, :string
    field :phases, {:array, Ecto.Enum}, values: @phases
    field :domains, {:array, :string}
    field :single_path, :boolean
    field :refresher_unit, :boolean
    embeds_one :areas_elsewhere, AreasElsewhere
  end

  @type t :: %__MODULE__{}

  @doc "Casts the data of `module.yaml`."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(module, attrs) do
    module
    |> Cast.cast(attrs, required: [:number, :title, :summary, :single_path, :refresher_unit])
    |> Cast.validate_min(:number, 1)
    |> Cast.validate_max_length(:title)
    |> Cast.validate_unique(:phases)
    |> Cast.validate_keys(:domains)
    |> Cast.validate_unique(:domains)
  end
end
