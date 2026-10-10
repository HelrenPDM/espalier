defmodule Espalier.Catalog.Pack.Importer do
  @moduledoc """
  Validates a content pack directory and stores it as a `PackImport`
  (task 0008, step 9; README section 11).

  The importer runs `Espalier.Catalog.Pack.Loader.load/1` and, when the pack
  loads, `Espalier.Catalog.Pack.Validator.run/1`. An import without errors is
  `validated` and holds the normalized map of the pack in `payload`; an
  import with errors is `failed` and holds no payload. In both cases
  `report` holds the `errors` and the `warnings` of the validator with every
  member of their entries, so that the alignment entries keep `check`,
  `module` and `key`. The report is stored with string keys, so the returned
  import equals the import read back from the database.

  `Espalier.Catalog.Pack.Report.stored/2` bounds the report: at most 100
  entries per file and 1,000 per list, each followed by a closing entry for
  the entries left out, and every string member one line of at most 1,000
  characters. The report therefore stays a few MB at most, whatever the
  pack holds, and the loader bounds the decoded data of the pack, from which
  the payload is built, to 32 MiB (`Espalier.Catalog.Pack.Loader.max_pack_bytes/0`).

  `Espalier.Catalog.Pack.Publisher.publish/1` applies a validated import to
  the catalog tables. The upload of task 0015 calls `import/2` with the id of
  the signed-in author, and the mix tasks and the release function with
  `nil`.
  """

  alias Espalier.Catalog.Pack.{Loader, Report, Validator}
  alias Espalier.Catalog.Pack.Schema.Cast
  alias Espalier.Catalog.PackImport
  alias Espalier.Repo

  @typedoc "A `%Espalier.Catalog.PackImport{}`."
  @type pack_import :: Ecto.Schema.schema()

  @doc """
  Loads and validates the pack at `path` and inserts a `PackImport` with
  `imported_by_id` set to `actor_id`.

  Returns `{:ok, pack_import}` for a `validated` and for a `failed` import,
  and `{:error, changeset}` when the import cannot be stored. `pack_key` and
  `pack_version` hold the `key` and `version` of `pack.yaml` when they are
  texts of at most 255 characters without a NUL character, and stay `nil`
  otherwise, for example when `pack.yaml` cannot be read. A `validated`
  import always holds both, because the validator rejects a `key` or a
  `version` that does not fit its column.

  The insert does not rescue database errors. The validator rejects every
  value that the columns of `pack_imports` and of the catalog cannot hold
  (a NUL character, a string over 255 characters for a `varchar(255)`
  column, an integer over 2147483647), the loader rejects a pack whose
  decoded data exceeds 32 MiB, and `Espalier.Catalog.Pack.Report.stored/2`
  escapes NUL and every other control character in the report and bounds
  its size, so that the `report` and `payload` columns hold what the import
  stores.
  """
  @spec import(Path.t(), Ecto.UUID.t() | nil) ::
          {:ok, pack_import()} | {:error, Ecto.Changeset.t()}
  def import(path, actor_id) when is_binary(path) and (is_nil(actor_id) or is_binary(actor_id)) do
    %PackImport{imported_by_id: actor_id}
    |> PackImport.changeset(attrs(path))
    |> Repo.insert()
  end

  defp attrs(path) do
    case Loader.load(path) do
      {:ok, loaded} ->
        loaded
        |> Validator.run()
        |> run_attrs(loaded_meta(loaded))

      {:error, errors} ->
        failed_attrs(Loader.pack_meta(path), errors, [])
    end
  end

  defp run_attrs(%{errors: [], warnings: warnings, payload: payload}, meta)
       when is_map(payload) do
    meta
    |> meta_attrs()
    |> Map.merge(%{status: :validated, report: Report.stored([], warnings), payload: payload})
  end

  defp run_attrs(%{errors: errors, warnings: warnings}, meta),
    do: failed_attrs(meta, errors, warnings)

  defp failed_attrs(meta, errors, warnings) do
    meta
    |> meta_attrs()
    |> Map.merge(%{status: :failed, report: Report.stored(errors, warnings), payload: nil})
  end

  defp loaded_meta(%{files: %{"pack.yaml" => %{data: %{} = data}}}),
    do: %{key: data["key"], version: data["version"]}

  defp loaded_meta(_loaded), do: %{key: nil, version: nil}

  defp meta_attrs(meta) do
    %{
      pack_key: meta_value(Map.get(meta, :key)),
      pack_version: meta_value(Map.get(meta, :version))
    }
  end

  # pack_key and pack_version are varchar(255) columns, which count code
  # points and reject a NUL character.
  defp meta_value(value) when is_binary(value) do
    if String.valid?(value) and Cast.fits_column?(value) and not String.contains?(value, <<0>>),
      do: value,
      else: nil
  end

  defp meta_value(_value), do: nil
end
