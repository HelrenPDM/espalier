defmodule Espalier.Catalog.Pack.Schema.Block do
  @moduledoc """
  A block of a lesson body, as `Espalier.Catalog.Pack.Directives.split/2`
  returns it: `kind`, `body`, `provenance`, `collapsed_on` (`short`, `full`),
  `cite` (`source-key#locator`), `placeholder_key` (key format) and `line`,
  the line of its opening line in the lesson file.

  A `quote` block cites at least one source, and the provenance
  `placeholder` belongs to `placeholder` blocks only (README principle 4).
  """
  use Ecto.Schema

  import Ecto.Changeset, only: [get_field: 2]

  alias Espalier.Catalog.Pack.Schema.Cast

  @primary_key false
  embedded_schema do
    field :kind, Ecto.Enum,
      values: [:text, :explanation, :example, :case_comparison, :quote, :callout, :placeholder]

    field :body, :string

    field :provenance, Ecto.Enum,
      values: [:invented, :sourced, :vendor_statement, :assumption, :placeholder]

    field :collapsed_on, {:array, Ecto.Enum}, values: [:short, :full]
    field :cite, {:array, :string}
    field :placeholder_key, :string
    field :line, :integer, virtual: true
  end

  @type t :: %__MODULE__{}

  @doc "Casts a block of a lesson body."
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(block, attrs) do
    block
    |> Cast.cast(attrs, required: [:kind, :body, :provenance, :line])
    |> Cast.validate_unique(:collapsed_on)
    |> Cast.validate_cite(:cite)
    |> Cast.validate_unique(:cite)
    |> Cast.validate_key(:placeholder_key)
    |> validate_quote()
    |> validate_provenance()
  end

  defp validate_quote(changeset) do
    if get_field(changeset, :kind) == :quote and List.wrap(get_field(changeset, :cite)) == [],
      do: Cast.add_entry_error(changeset, "a `quote` block cites at least one source"),
      else: changeset
  end

  defp validate_provenance(changeset) do
    kind = get_field(changeset, :kind)

    if get_field(changeset, :provenance) == :placeholder and not is_nil(kind) and
         kind != :placeholder,
       do:
         Cast.add(
           changeset,
           :provenance,
           "the provenance `placeholder` belongs to `placeholder` blocks only"
         ),
       else: changeset
  end
end
