defmodule Espalier.Catalog.Pack.Schema.AreasElsewhere do
  @moduledoc """
  The `areas_elsewhere` mapping of a `module.yaml`: the competence areas that a module covers in another place.

  `areas_elsewhere` is an optional member of the mapping in
  `modules/<directory>/module.yaml` (see `Espalier.Catalog.Pack.Schema.PackModule`).
  Every module needs each of the four competence areas, either as an objective
  of its own in `objectives.yaml` or as an entry here. The key of an entry is
  the area, and its value names the place that covers the area, see
  `Espalier.Catalog.Pack.Schema.Elsewhere`.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `subject` | mapping | no | An entry with `where` and `reason`. |
  | `method` | mapping | no | An entry with `where` and `reason`. |
  | `self` | mapping | no | An entry with `where` and `reason`. |
  | `social` | mapping | no | An entry with `where` and `reason`. |

  Any other key is an error. A key with the value `null` counts as absent. A
  module names an area here only when its own objectives leave the area out,
  but the validator resolves every `where` that is present, also for an area in
  which the module has objectives.

  ## Example

  A module with objectives in `subject` and `method` that covers `self` and
  `social` in a workshop and in another module:

  ```yaml
  self:
    where: format:workshop
    reason: The workshop practises deciding which of one's own tasks an assistant may support.
  social:
    where: module:1
    reason: Module 1 agrees with the team how the use of an assistant is made visible.
  ```

  The block shows the value of `areas_elsewhere`; in `module.yaml` it sits below
  the key `areas_elsewhere:`. The schema checks the form of each `where`. The
  validator then resolves it against the formats and modules of the pack, so the
  example is valid for this schema alone and valid in a pack only when the
  format `workshop` and the module `1` exist.

  ## Checks

    * `` unknown competence area `x` in `areas_elsewhere` `` for a key other than the four areas;
    * `` `areas_elsewhere` must be a map `` when the value is no mapping, and `` `self` must be a map `` (and the same for the other areas) when an area holds no mapping;
    * the errors of `Espalier.Catalog.Pack.Schema.Elsewhere` for the entries, reported with the path `areas_elsewhere`, the area and the field;
    * the alignment check (check 3 of `Espalier.Catalog.Alignment.check/1`): an area without an objective in the module needs an entry whose `where` names a format or a module that has an objective of that area. Otherwise the finding is an error with `alignment: strict` (the default) and a warning with `alignment: warn`. It sits at the line of the area in `areas_elsewhere`, or at line 1 of `module.yaml` when the area is not named.

  ## See also

    * [Content packs](content-packs.md), the section "Constructive alignment"
    * `Espalier.Catalog.Pack.Schema.PackModule`, the `module.yaml`
    * `Espalier.Catalog.Pack.Schema.Elsewhere`, one entry
    * `Espalier.Catalog.Pack.Schema.Objective`, which sets the area of an objective
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

  @typedoc "The cast contents of `areas_elsewhere`, with one `Espalier.Catalog.Pack.Schema.Elsewhere` or `nil` for each area."
  @type t :: %__MODULE__{}

  @doc "Returns the four competence areas as atoms, in the order `subject`, `method`, `self`, `social`."
  @spec areas() :: [atom()]
  def areas, do: @areas

  @doc """
  Casts the mapping of `areas_elsewhere`.

  Returns a changeset; a key that is no competence area is an error.
  """
  @spec changeset(t(), term()) :: Ecto.Changeset.t()
  def changeset(areas_elsewhere, attrs) do
    Cast.cast(areas_elsewhere, attrs,
      unknown: &"unknown competence area `#{&1}` in `areas_elsewhere`"
    )
  end
end
