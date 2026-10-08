defmodule Espalier.Crypto.Rotation do
  @moduledoc """
  Re-encrypts stored values under the current key and reports which cipher tag
  each encrypted column holds.

  The rotation walks the tables through rotation-only schemas. Such a schema
  maps an existing table with its primary key and its encrypted fields and
  nothing else, so a write through it leaves `updated_at` and the hash columns
  untouched. Each task that creates an encrypted column adds its schema in
  `lib/espalier/crypto/rotation/<table>.ex` (module
  `Espalier.Crypto.Rotation.<Table>`) to `schemas/0` in the same change. The
  schema is written by hand; `mix phx.gen.schema` would add a migration,
  timestamps and a `user_id` field.

  `Espalier.Release.rotate_encryption/0` and `encryption_status/0` call this
  module; the runbook is `docs/security/key-management.md`.
  """

  import Ecto.Query

  alias Ecto.Changeset

  @default_batch_size 500

  @doc "Returns the registered rotation-only schemas."
  @spec schemas() :: [module()]
  def schemas, do: []

  @doc """
  Raises `ArgumentError` unless `schema` has exactly one primary key field and
  otherwise only encrypted fields.
  """
  @spec validate!(module()) :: module()
  def validate!(schema) do
    pk = schema.__schema__(:primary_key)
    others = schema.__schema__(:fields) -- pk
    rejected = Enum.reject(others, &encrypted_type?(schema.__schema__(:type, &1)))

    cond do
      length(pk) != 1 ->
        raise ArgumentError, "#{inspect(schema)} needs exactly one primary key field"

      rejected != [] ->
        raise ArgumentError,
              "#{inspect(schema)} is no rotation-only schema: #{inspect(rejected)} are no encrypted fields"

      schema.__schema__(:associations) != [] or schema.__schema__(:embeds) != [] ->
        raise ArgumentError,
              "#{inspect(schema)} is no rotation-only schema: it has associations or embeds"

      true ->
        schema
    end
  end

  @doc """
  Rewrites every encrypted value of each schema's table under the first
  cipher of the vault and returns `%{schema => rows_updated}`.

  Each table is walked in primary-key order, in batches of
  `opts[:batch_size]` rows (default #{@default_batch_size}). Each batch is one
  transaction that locks its rows with `FOR UPDATE`, so a concurrent write
  waits. The batches run one after another on one connection.
  """
  @spec run(Ecto.Repo.t(), [module()], keyword()) :: %{module() => non_neg_integer()}
  def run(repo, schemas, opts \\ []) do
    Enum.each(schemas, &validate!/1)
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)

    repo.checkout(fn ->
      Map.new(schemas, fn schema -> {schema, rotate(repo, schema, batch_size, nil, 0)} end)
    end)
  end

  @doc """
  Returns `%{{table, column} => %{tag => count}}` for every encrypted field of
  the schemas, read from the tag that prefixes each stored value.
  """
  @spec tag_counts(Ecto.Repo.t(), [module()]) :: %{
          {String.t(), String.t()} => %{String.t() => non_neg_integer()}
        }
  def tag_counts(repo, schemas) do
    for schema <- schemas, field <- encrypted_fields(schema), into: %{} do
      table = schema.__schema__(:source)
      column = field_source(schema, field)
      %{rows: rows} = repo.query!(tag_count_sql(schema, column), [])
      {{table, column}, Map.new(rows, fn [tag, count] -> {tag, count} end)}
    end
  end

  @doc """
  Returns every `{table, column}` of an encrypted field in `schema_modules`
  that no rotation schema with the same source covers.
  """
  @spec uncovered([module()], [module()]) :: [{String.t(), String.t()}]
  def uncovered(schema_modules, rotation_schemas) do
    covered = rotation_schemas |> Enum.flat_map(&columns/1) |> MapSet.new()

    schema_modules
    |> Enum.flat_map(&columns/1)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(covered, &1))
  end

  @doc "Returns the fields of `schema` whose type is a Cloak encryption type."
  @spec encrypted_fields(module()) :: [atom()]
  def encrypted_fields(schema) do
    Enum.filter(schema.__schema__(:fields), &encrypted_type?(schema.__schema__(:type, &1)))
  end

  defp rotate(repo, schema, batch_size, last_id, count) do
    [pk] = schema.__schema__(:primary_key)
    fields = encrypted_fields(schema)

    {:ok, {rows, rewritten}} =
      repo.transact(fn ->
        rows = repo.all(batch_query(schema, pk, batch_size, last_id))
        {:ok, {rows, Enum.count(rows, &rewrite(repo, &1, fields))}}
      end)

    count = count + rewritten

    if length(rows) < batch_size do
      count
    else
      rotate(repo, schema, batch_size, rows |> List.last() |> Map.fetch!(pk), count)
    end
  end

  defp batch_query(schema, pk, batch_size, nil) do
    from(r in schema, order_by: field(r, ^pk), limit: ^batch_size, lock: "FOR UPDATE")
  end

  defp batch_query(schema, pk, batch_size, last_id) do
    from(r in batch_query(schema, pk, batch_size, nil), where: field(r, ^pk) > ^last_id)
  end

  # Loading decrypted each value with the cipher of its tag; forcing the
  # change dumps it again with the first cipher of the vault.
  defp rewrite(repo, row, fields) do
    changeset =
      Enum.reduce(fields, Changeset.change(row), fn field, changeset ->
        case Map.fetch!(row, field) do
          nil -> changeset
          value -> Changeset.force_change(changeset, field, value)
        end
      end)

    if changeset.changes == %{} do
      false
    else
      repo.update!(changeset)
      true
    end
  end

  defp columns(schema) do
    case schema.__schema__(:source) do
      nil -> []
      table -> for field <- encrypted_fields(schema), do: {table, field_source(schema, field)}
    end
  end

  defp field_source(schema, field), do: to_string(schema.__schema__(:field_source, field))

  # A Cloak value starts with <<1, tag_length, tag::binary>>. Table and
  # column names come from the schema and are quoted as identifiers; the
  # query takes no input.
  defp tag_count_sql(schema, column) do
    col = quote_ident(column)

    table =
      [schema.__schema__(:prefix), schema.__schema__(:source)]
      |> Enum.reject(&is_nil/1)
      |> Enum.map_join(".", &quote_ident/1)

    "SELECT convert_from(substring(#{col} from 3 for get_byte(#{col}, 1)), 'UTF8'), count(*) " <>
      "FROM #{table} WHERE #{col} IS NOT NULL GROUP BY 1"
  end

  defp quote_ident(name), do: ~s(") <> String.replace(to_string(name), ~s("), ~s("")) <> ~s(")

  defp encrypted_type?({:parameterized, {module, _params}}), do: encrypted_type?(module)

  defp encrypted_type?(type) when is_atom(type) do
    Code.ensure_loaded?(type) and function_exported?(type, :__cloak__, 0)
  end

  defp encrypted_type?(_type), do: false
end
