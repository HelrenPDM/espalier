defmodule Espalier.Catalog.Pack.Schema.Elsewhere do
  @moduledoc """
  An entry of `areas_elsewhere`: the place that covers one competence area of a module, with the reason.

  The entry is the value of one area key (`subject`, `method`, `self` or
  `social`) in the `areas_elsewhere` mapping of a `module.yaml`, see
  `Espalier.Catalog.Pack.Schema.AreasElsewhere`. It names a companion format
  of the pack (`formats.yaml`) or another module of the pack, and it says what
  that place covers. The alignment check of the module counts the area as
  covered when the named place has an objective of the area.

  ## Fields

  | Field | Type | Required | Rules |
  |---|---|---|---|
  | `where` | string | yes | `format:<format key>` or `module:<module number>`. The format key has the key format `^[a-z0-9][a-z0-9-]*$`, and the module number is an integer of 1 or more without a leading zero. |
  | `reason` | string | yes | Not empty. A text that states what the named place covers. |

  The schema checks the form of `where`. The validator checks across files that
  a named format or module exists.

  ## Example

  ```yaml
  where: format:workshop
  reason: The workshop practises deciding which of one's own tasks an assistant may support.
  ```

  A module as the place:

  ```yaml
  where: module:1
  reason: Module 1 teaches how to run the release checks on a generated text.
  ```

  Both blocks show the value of one area; in `module.yaml` they sit below the
  area key, for example `social:` below `areas_elsewhere:`. The second block
  is valid in a pack only when module 1 is another module of the pack and has
  an objective in the area that it covers.

  ## Checks

  The schema reports:

    * `` missing field `where` `` and `` missing field `reason` ``;
    * `` unknown field `x` `` for any other field;
    * `` `where` must have the form `format:<format key>` or `module:<module number>` `` for a value such as `workshop`, `format:Workshop` or `module:0`.

  The validator reports, at the line of `where`:

    * `` unknown format `x` in `where` `` when `formats.yaml` has no format with that key;
    * `` unknown module `3` in `where` `` when no module has that number;
    * `` `where` names the module's own number `2` `` when the entry names the module in whose `module.yaml` it sits.

  The alignment check reports an area that the named place does not carry:
  `` no objective of module 2 has the area `self`, and `format:workshop` named in `areas_elsewhere` carries no `self` objective ``. A format carries an area when it names an objective of that area in its `objectives`, whether or not `attendance_counts` is `true`.

  ## See also

    * [Content packs](content-packs.md), the section "Constructive alignment"
    * `Espalier.Catalog.Pack.Schema.AreasElsewhere`, the mapping that holds the entries
    * `Espalier.Catalog.Pack.Schema.Format`, the companion formats that `format:<format key>` names
    * `Espalier.Catalog.Pack.Schema.PackModule`, the `module.yaml`
  """
  use Ecto.Schema

  alias Espalier.Catalog.Pack.Schema.Cast

  @where_regex ~r/\A(format:[a-z0-9][a-z0-9-]*|module:[1-9][0-9]*)\z/

  @primary_key false
  embedded_schema do
    field :where, :string
    field :reason, :string
  end

  @typedoc "The cast contents of an entry of `areas_elsewhere`."
  @type t :: %__MODULE__{}

  @doc """
  Casts one entry of `areas_elsewhere`.

  Returns a changeset that is valid when `where` and `reason` are present and
  `where` has the form `format:<format key>` or `module:<module number>`.
  """
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
