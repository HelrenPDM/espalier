defmodule Espalier.Catalog.Pack.Schema.Cast do
  @moduledoc """
  Strict casting for the embedded schemas of a content pack (task 0008,
  step 8). Every schema under `Espalier.Catalog.Pack.Schema` casts its data
  with `cast/3` and the validations of this module.

  `cast/3` validates positively:

    * a key that is no field of the schema is an error (`unknown field`);
    * a value must have the type of its field: a non-empty string without a
      NUL character for `:string`, an integer of at most 2147483647 for
      `:integer`, `true` or `false` for `:boolean`, one of the values for
      `Ecto.Enum`, a list of such values for an array, a map for `:map` and
      for `embeds_one`, and a list of maps for `embeds_many`. YAML strings
      that look like numbers or booleans are not converted;
    * a required field must be present with a value. A `null` value counts as
      absent.

  The bounds keep every value storable: PostgreSQL rejects a NUL character
  in `text`, `varchar` and `jsonb` values, and an `integer` column holds at
  most 2147483647. `validate_key/2`, `validate_keys/2`, `validate_cite/2`
  and `validate_max_length/2` bound the strings that the publisher writes
  to `varchar(255)` columns.

  Each error carries the path of the offending value relative to the cast
  data, which `errors/1` returns, so that the validator finds its line in
  the line index. The cast creates no atoms: field names come from the
  schema, and unknown keys stay strings.
  """

  import Ecto.Changeset

  alias Ecto.Changeset
  alias Espalier.Catalog.Pack.LineIndex

  # `\A` and `\z` anchor at the ends of the whole value; `$` would also match
  # before a final newline.
  @key_regex ~r/\A[a-z0-9][a-z0-9-]*\z/
  @cite_regex ~r/\A[a-z0-9][a-z0-9-]*#\S(.*\S)?\z/
  @date_regex ~r/\A\d{4}-\d{2}-\d{2}\z/

  # The length of a varchar(255) column, in characters (code points).
  @max_length 255
  # The largest value of an integer (int4) column.
  @max_integer 2_147_483_647
  # The integers of a JSON value: 2^53 - 1, the largest integer that a
  # JavaScript number holds exactly.
  @max_json_integer 9_007_199_254_740_991

  @typedoc "An error with the path of the offending value."
  @type error :: {LineIndex.path(), String.t()}

  @doc "The format of keys, slugs and codes: `^[a-z0-9][a-z0-9-]*$`, matched against the whole value."
  @spec key_regex() :: Regex.t()
  def key_regex, do: @key_regex

  @doc "Returns true when `value` is a string in the key format."
  @spec key?(term()) :: boolean()
  def key?(value), do: is_binary(value) and Regex.match?(@key_regex, value)

  @doc "The largest number of characters of a string that lands in a `varchar(255)` column."
  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @doc "The largest integer that an `integer` column holds."
  @spec max_integer() :: pos_integer()
  def max_integer, do: @max_integer

  @doc """
  Returns true when the string `value` fits a `varchar(255)` column: it has
  at most 255 characters. PostgreSQL counts code points, so a letter with a
  combining accent counts twice.
  """
  @spec fits_column?(String.t()) :: boolean()
  def fits_column?(value) when is_binary(value),
    do: byte_size(value) <= @max_length or length(String.codepoints(value)) <= @max_length

  @doc """
  Casts `attrs` into `struct` strictly, as the moduledoc describes.

  Options:

    * `:required` - the fields that must be present;
    * `:unknown` - a function from an unknown key to its message.
  """
  @spec cast(struct(), term(), keyword()) :: Changeset.t()
  def cast(struct, attrs, opts \\ [])

  def cast(%module{} = struct, attrs, opts) when is_map(attrs) do
    embeds = module.__schema__(:embeds)
    fields = (module.__schema__(:fields) -- embeds) ++ module.__schema__(:virtual_fields)
    known = Map.new(fields ++ embeds, &{Atom.to_string(&1), &1})

    {clean, errors} =
      Enum.reduce(attrs, {%{}, []}, fn {key, value}, acc ->
        check_member(module, known, key, value, acc, opts)
      end)

    struct
    |> Changeset.cast(clean, fields, empty_values: [])
    |> cast_embeds(embeds, clean)
    |> add_errors(errors)
    |> validate_present(attrs, Keyword.get(opts, :required, []), errors)
  end

  def cast(struct, _attrs, _opts) do
    struct |> change() |> add_error(:__entry__, "an entry must be a map", pack: [])
  end

  @doc """
  Returns the errors of `changeset` and of its embedded changesets, each with
  the path of the offending value relative to the cast data.
  """
  @spec errors(Changeset.t()) :: [error()]
  def errors(%Changeset{} = changeset) do
    own = Enum.map(changeset.errors, &own_error/1)
    nested = Enum.flat_map(changeset.changes, &nested_errors/1)
    own ++ nested
  end

  @doc """
  Adds an error at `field`. `suffix` is the path below the field, and `[]`
  places the error at the field itself.
  """
  @spec add(Changeset.t(), atom(), LineIndex.path(), String.t()) :: Changeset.t()
  def add(changeset, field, suffix \\ [], message),
    do: add_error(changeset, field, message, pack: suffix)

  @doc "Adds an error at the cast data itself, or at `suffix` below it."
  @spec add_entry_error(Changeset.t(), LineIndex.path(), String.t()) :: Changeset.t()
  def add_entry_error(changeset, suffix \\ [], message),
    do: add_error(changeset, :__entry__, message, pack: suffix)

  @doc "Returns true when `changeset` has an error at `field`."
  @spec errored?(Changeset.t(), atom()) :: boolean()
  def errored?(changeset, field), do: Keyword.has_key?(changeset.errors, field)

  @doc "Validates that the string at `field` is in the key format and has at most 255 characters."
  @spec validate_key(Changeset.t(), atom()) :: Changeset.t()
  def validate_key(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      value ->
        case key_error(value) do
          nil -> changeset
          :format -> add(changeset, field, key_message(field, value))
          :length -> add(changeset, field, length_message(field))
        end
    end
  end

  @doc """
  Validates that every string of the list at `field` is in the key format and
  has at most 255 characters.
  """
  @spec validate_keys(Changeset.t(), atom()) :: Changeset.t()
  def validate_keys(changeset, field) do
    changeset
    |> list_change(field)
    |> Enum.reduce(changeset, fn {value, index}, changeset ->
      case key_error(value) do
        nil -> changeset
        :format -> add(changeset, field, [index], key_message(field, value))
        :length -> add(changeset, field, [index], "entries of #{length_message(field)}")
      end
    end)
  end

  @doc """
  Validates that the string at `field`, or every string of the list at
  `field`, has at most 255 characters, so that it fits a `varchar(255)`
  column.
  """
  @spec validate_max_length(Changeset.t(), atom()) :: Changeset.t()
  def validate_max_length(changeset, field) do
    case get_change(changeset, field) do
      value when is_binary(value) ->
        if fits_column?(value),
          do: changeset,
          else: add(changeset, field, length_message(field))

      values when is_list(values) ->
        values
        |> Enum.with_index()
        |> Enum.reject(fn {value, _index} -> not is_binary(value) or fits_column?(value) end)
        |> Enum.reduce(changeset, fn {_value, index}, changeset ->
          add(changeset, field, [index], "entries of #{length_message(field)}")
        end)

      _ ->
        changeset
    end
  end

  @doc "Validates that the list at `field` holds no value twice."
  @spec validate_unique(Changeset.t(), atom()) :: Changeset.t()
  def validate_unique(changeset, field) do
    changeset
    |> list_change(field)
    |> duplicates(fn {value, _index} -> value end)
    |> Enum.reduce(changeset, fn {value, index}, changeset ->
      add(changeset, field, [index], "duplicate entry `#{display(value)}` in `#{field}`")
    end)
  end

  @doc "Validates that the entries of the embedded list `field` have unique values of `key_field`."
  @spec validate_unique_by(Changeset.t(), atom(), atom()) :: Changeset.t()
  def validate_unique_by(changeset, field, key_field) do
    changeset
    |> get_field(field)
    |> List.wrap()
    |> Enum.with_index()
    |> Enum.reject(fn {entry, _index} -> is_nil(Map.get(entry, key_field)) end)
    |> duplicates(fn {entry, _index} -> Map.get(entry, key_field) end)
    |> Enum.reduce(changeset, fn {entry, index}, changeset ->
      value = Map.get(entry, key_field)

      add(
        changeset,
        field,
        [index, Atom.to_string(key_field)],
        "duplicate #{key_field} `#{value}` in `#{field}`"
      )
    end)
  end

  @doc "Validates that the integer at `field` is at least `min`."
  @spec validate_min(Changeset.t(), atom(), integer()) :: Changeset.t()
  def validate_min(changeset, field, min) do
    case get_change(changeset, field) do
      value when is_integer(value) and value < min ->
        add(changeset, field, "`#{field}` must be at least #{min}")

      _ ->
        changeset
    end
  end

  @doc """
  Validates that the list at `field` holds at least `min` entries when the
  field is present. A required field that is absent has the error of `cast/3`.
  """
  @spec validate_length(Changeset.t(), atom(), pos_integer(), String.t()) :: Changeset.t()
  def validate_length(changeset, field, min, message) do
    entries = changeset |> get_field(field) |> List.wrap()

    if Map.has_key?(changeset.params || %{}, Atom.to_string(field)) and length(entries) < min,
      do: add(changeset, field, message),
      else: changeset
  end

  @doc """
  Validates that every entry of the list at `field` has the form
  `source-key#locator` and a locator of at most 255 characters, the length
  of `citations.locator`.
  """
  @spec validate_cite(Changeset.t(), atom()) :: Changeset.t()
  def validate_cite(changeset, field) do
    changeset
    |> list_change(field)
    |> Enum.reduce(changeset, fn {value, index}, changeset ->
      case cite_error(field, value) do
        nil -> changeset
        message -> add(changeset, field, [index], message)
      end
    end)
  end

  @doc """
  Validates that the string at `field` is a valid date in the ISO 8601 form
  `YYYY-MM-DD` (`2026-05-30`), with exactly four digits for the year and no
  sign, so that the string equals `Date.to_iso8601/1` of its date.
  """
  @spec validate_date(Changeset.t(), atom()) :: Changeset.t()
  def validate_date(changeset, field) do
    case get_change(changeset, field) do
      value when is_binary(value) ->
        if Regex.match?(@date_regex, value) and match?({:ok, _date}, Date.from_iso8601(value)),
          do: changeset,
          else:
            add(
              changeset,
              field,
              "`#{field}` must be a date in the form `YYYY-MM-DD`, got `#{shown(value)}`"
            )

      _ ->
        changeset
    end
  end

  @doc "Validates that the string at `field` matches `regex`."
  @spec validate_regex(Changeset.t(), atom(), Regex.t(), String.t()) :: Changeset.t()
  def validate_regex(changeset, field, regex, message) do
    case get_change(changeset, field) do
      value when is_binary(value) ->
        if Regex.match?(regex, value), do: changeset, else: add(changeset, field, message)

      _ ->
        changeset
    end
  end

  @doc """
  Validates that the map at `field` holds JSON values that survive a `jsonb`
  column unchanged: string keys, strings, integers, booleans, `null`, lists
  and maps. A float is an error, because `jsonb` stores numbers as
  `numeric` and gives `1.0e3` back as the integer `1000`. An integer
  outside -9,007,199,254,740,991 to 9,007,199,254,740,991 is an error,
  because `jsonb` limits the digits of a number and a JavaScript client
  reads larger integers inexactly. A string or a key with a NUL character is
  an error, because `jsonb` rejects it.
  """
  @spec validate_json(Changeset.t(), atom()) :: Changeset.t()
  def validate_json(changeset, field) do
    case get_change(changeset, field) do
      nil ->
        changeset

      value ->
        value
        |> json_errors([])
        |> Enum.reduce(changeset, fn {suffix, reason}, changeset ->
          add(changeset, field, suffix, json_message(field, reason))
        end)
    end
  end

  @doc """
  Casts the raw map at `field` with `module.changeset/2` and replaces the
  change with the cast struct, or adds the errors of the nested changeset
  below `field`.
  """
  @spec cast_nested(Changeset.t(), atom(), module()) :: Changeset.t()
  def cast_nested(changeset, field, module) do
    nested = module.changeset(struct(module), get_change(changeset, field))

    if nested.valid? do
      put_change(changeset, field, apply_changes(nested))
    else
      nested
      |> errors()
      |> Enum.reduce(changeset, fn {suffix, message}, changeset ->
        add(changeset, field, suffix, message)
      end)
    end
  end

  # cast/3

  defp check_member(module, known, key, value, {clean, errors}, opts) do
    case Map.fetch(known, key) do
      :error ->
        message = Keyword.get(opts, :unknown, &"unknown field `#{&1}`").(display(key))
        {clean, [{:__entry__, [display(key)], message} | errors]}

      {:ok, _field} when is_nil(value) ->
        {clean, errors}

      {:ok, field} ->
        case type_errors(module, field, value) do
          [] ->
            {Map.put(clean, key, value), errors}

          found ->
            {clean,
             Enum.map(found, fn {suffix, message} -> {field, suffix, message} end) ++ errors}
        end
    end
  end

  defp type_errors(module, field, value) do
    name = Atom.to_string(field)

    case module.__schema__(:embed, field) do
      %Ecto.Embedded{cardinality: :one} ->
        map_errors(name, value)

      %Ecto.Embedded{cardinality: :many} ->
        list_errors(name, value, &map_entry_errors(name, &1, &2))

      nil ->
        value_errors(module, field, name, field_type(module, field), value)
    end
  end

  defp field_type(module, field),
    do: module.__schema__(:type, field) || module.__schema__(:virtual_type, field)

  defp value_errors(_module, _field, name, :string, value), do: string_errors(name, value)

  defp value_errors(_module, _field, _name, :integer, value)
       when is_integer(value) and value <= @max_integer,
       do: []

  defp value_errors(_module, _field, name, :integer, value) when is_integer(value),
    do: [{[], "`#{name}` must be at most #{@max_integer}"}]

  defp value_errors(_module, _field, name, :integer, _value),
    do: [{[], "`#{name}` must be an integer"}]

  defp value_errors(_module, _field, _name, :boolean, value) when is_boolean(value), do: []

  defp value_errors(_module, _field, name, :boolean, _value),
    do: [{[], "`#{name}` must be `true` or `false`"}]

  defp value_errors(_module, _field, name, :map, value), do: map_errors(name, value)
  defp value_errors(_module, _field, _name, :any, _value), do: []

  defp value_errors(module, field, name, {:parameterized, {Ecto.Enum, _params}}, value),
    do: enum_errors(name, value, Ecto.Enum.dump_values(module, field))

  defp value_errors(module, field, name, {:array, inner}, value) do
    list_errors(name, value, &array_entry_errors(module, field, name, inner, &1, &2))
  end

  defp string_errors(name, value) when is_binary(value) do
    cond do
      String.trim(value) == "" -> [{[], "`#{name}` must not be empty"}]
      nul?(value) -> [{[], "`#{name}` must not contain a NUL character"}]
      true -> []
    end
  end

  defp string_errors(name, _value), do: [{[], "`#{name}` must be a string"}]

  defp map_errors(_name, value) when is_map(value), do: []
  defp map_errors(name, _value), do: [{[], "`#{name}` must be a map"}]

  defp enum_errors(name, value, values) do
    if is_binary(value) and value in values,
      do: [],
      else: [{[], "`#{name}` must be one of #{Enum.map_join(values, ", ", &"`#{&1}`")}"}]
  end

  defp list_errors(_name, value, entry_errors) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} -> entry_errors.(entry, index) end)
  end

  defp list_errors(name, _value, _entry_errors), do: [{[], "`#{name}` must be a list"}]

  defp map_entry_errors(_name, entry, _index) when is_map(entry), do: []
  defp map_entry_errors(name, _entry, index), do: [{[index], "entries of `#{name}` must be maps"}]

  defp array_entry_errors(_module, _field, name, :string, entry, index) do
    cond do
      not is_binary(entry) or String.trim(entry) == "" ->
        [{[index], "entries of `#{name}` must be non-empty strings"}]

      nul?(entry) ->
        [{[index], "entries of `#{name}` must not contain a NUL character"}]

      true ->
        []
    end
  end

  defp array_entry_errors(_module, _field, name, :integer, entry, index) do
    cond do
      not is_integer(entry) -> [{[index], "entries of `#{name}` must be integers"}]
      entry > @max_integer -> [{[index], "entries of `#{name}` must be at most #{@max_integer}"}]
      true -> []
    end
  end

  defp array_entry_errors(
         module,
         field,
         name,
         {:parameterized, {Ecto.Enum, _params}},
         entry,
         index
       ) do
    values = Ecto.Enum.dump_values(module, field)

    if is_binary(entry) and entry in values,
      do: [],
      else: [
        {[index],
         "entries of `#{name}` must be one of #{Enum.map_join(values, ", ", &"`#{&1}`")}"}
      ]
  end

  defp cast_embeds(changeset, embeds, clean) do
    Enum.reduce(embeds, changeset, fn embed, changeset ->
      if Map.has_key?(clean, Atom.to_string(embed)),
        do: cast_embed(changeset, embed),
        else: changeset
    end)
  end

  defp add_errors(changeset, errors) do
    errors
    |> Enum.reverse()
    |> Enum.reduce(changeset, fn {field, suffix, message}, changeset ->
      add_error(changeset, field, message, pack: suffix)
    end)
  end

  defp validate_present(changeset, attrs, required, errors) do
    failed = MapSet.new(errors, fn {field, _suffix, _message} -> field end)

    Enum.reduce(required, changeset, fn field, changeset ->
      name = Atom.to_string(field)

      cond do
        MapSet.member?(failed, field) -> changeset
        not Map.has_key?(attrs, name) -> add(changeset, field, "missing field `#{name}`")
        is_nil(Map.get(attrs, name)) -> add(changeset, field, "`#{name}` has no value")
        true -> changeset
      end
    end)
  end

  # errors/1

  defp own_error({:__entry__, {message, opts}}), do: {Keyword.get(opts, :pack, []), message}

  defp own_error({field, {message, opts}}) do
    case Keyword.fetch(opts, :pack) do
      {:ok, suffix} -> {[Atom.to_string(field) | suffix], message}
      :error -> {[Atom.to_string(field)], "`#{field}` " <> interpolate(message, opts)}
    end
  end

  defp interpolate(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, message ->
      String.replace(message, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  defp nested_errors({field, %Changeset{} = child}),
    do: prefix(errors(child), [Atom.to_string(field)])

  defp nested_errors({field, [%Changeset{} | _] = children}) do
    children
    |> Enum.with_index()
    |> Enum.flat_map(fn {child, index} ->
      prefix(errors(child), [Atom.to_string(field), index])
    end)
  end

  defp nested_errors(_change), do: []

  defp prefix(errors, path),
    do: Enum.map(errors, fn {suffix, message} -> {path ++ suffix, message} end)

  # helpers

  defp list_change(changeset, field) do
    changeset |> get_change(field) |> List.wrap() |> Enum.with_index()
  end

  defp duplicates(entries, value_of) do
    {found, _seen} =
      Enum.reduce(entries, {[], MapSet.new()}, fn entry, {found, seen} ->
        value = value_of.(entry)

        if MapSet.member?(seen, value),
          do: {[entry | found], seen},
          else: {found, MapSet.put(seen, value)}
      end)

    Enum.reverse(found)
  end

  defp key_error(value) do
    cond do
      not key?(value) -> :format
      not fits_column?(value) -> :length
      true -> nil
    end
  end

  defp key_message(field, value),
    do: "`#{field}` value `#{shown(value)}` does not match the key format `^[a-z0-9][a-z0-9-]*$`"

  defp length_message(field), do: "`#{field}` must have at most #{@max_length} characters"

  defp cite_error(field, value) do
    if Regex.match?(@cite_regex, value) do
      [_source, locator] = String.split(value, "#", parts: 2)

      if fits_column?(locator),
        do: nil,
        else: "the locator of a `#{field}` entry must have at most #{@max_length} characters"
    else
      "`#{field}` entry `#{shown(value)}` does not have the form `source-key#locator`"
    end
  end

  defp nul?(value), do: String.contains?(value, <<0>>)

  defp json_errors(value, path) when is_binary(value),
    do: if(nul?(value), do: [{path, :nul}], else: [])

  defp json_errors(value, path) when is_integer(value) and abs(value) > @max_json_integer,
    do: [{path, :integer_range}]

  defp json_errors(value, _path) when is_integer(value) or is_boolean(value) or is_nil(value),
    do: []

  defp json_errors(value, path) when is_float(value), do: [{path, :float}]

  defp json_errors(value, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {entry, index} -> json_errors(entry, path ++ [index]) end)
  end

  defp json_errors(value, path) when is_map(value) and not is_struct(value) do
    Enum.flat_map(value, fn
      {key, entry} when is_binary(key) ->
        if nul?(key), do: [{path ++ [key], :nul}], else: json_errors(entry, path ++ [key])

      {_key, _entry} ->
        [{path, :not_json}]
    end)
  end

  defp json_errors(_value, path), do: [{path, :not_json}]

  defp json_message(field, :not_json), do: "`#{field}` holds a value that is not a JSON value"
  defp json_message(field, :nul), do: "`#{field}` must not contain a NUL character"

  defp json_message(field, :integer_range),
    do: "`#{field}` holds an integer beyond #{@max_json_integer} or below -#{@max_json_integer}"

  defp json_message(field, :float),
    do:
      "`#{field}` holds a number with a fraction or an exponent; use an integer or a quoted string"

  defp display(value) when is_binary(value), do: value
  defp display(value), do: inspect(value)

  # A value inside a message: a string with a control character, such as a
  # trailing newline, is shown escaped, so that the message stays one line.
  defp shown(value) when is_binary(value) do
    if String.match?(value, ~r/[\x00-\x1f\x7f]/), do: inspect(value), else: value
  end

  defp shown(value), do: inspect(value)
end
