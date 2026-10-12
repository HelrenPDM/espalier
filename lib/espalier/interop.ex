defmodule Espalier.Interop do
  @moduledoc """
  The Interop context: the SCORM export of a published module (task 0016,
  steps 6 to 10). `Espalier.Interop.Payload` reads the content, and
  `Espalier.Interop.ExportWorker` builds the package.

  An author requests an export with `request_export/3`. The export row, its
  job in the Oban queue `exports` (one slot, so concurrent requests queue
  up; ASVS 15.2.2) and the audit event `export.requested` are written in
  one transaction, so that none of them persists without the others. The
  worker writes the package `<id>.zip` below `EXPORT_DIR` (`export_dir/0`),
  and `package_path/1` builds the path of a download from that directory
  and the stored `file_name` only, so that no request parameter names a
  file (ASVS 5.3.2 and 5.4.1).

  The worker changes the status of an export only through
  `transition_export/3`, one conditional `UPDATE` that names the statuses
  it starts from, so that the worker and `Espalier.Interop.StaleExportWorker`
  never both end one export.

  `config :espalier, :export_retention` bounds the exports that the platform
  keeps (`retention/0`, ASVS 15.2.2):

    * `max_age_days` (default 7): an export with status `done` or `failed`
      whose `updated_at` lies more days back is deleted with its files;
    * `max_packages` (default 100): of the exports with status `done`, the
      newest `max_packages` stay, and every older one is deleted with its
      package.

  `prune_exports/1` applies both rules and removes the files below
  `EXPORT_DIR` that belong to no export. The worker applies the count rule
  after each export that reaches `done`, and the sweep every rule every 15
  minutes. A deleted export answers 404 on both routes.

  The manifests come from the fixed EEx templates
  `priv/scorm/imsmanifest_12.xml.eex` and
  `priv/scorm/imsmanifest_2004.xml.eex`, compiled into this module, and
  every value enters them through `xml_escape/1` (ASVS 1.1.2, 1.2.1 and
  1.3.7).
  """

  require EEx
  require Logger

  import Ecto.Query, only: [from: 2]

  alias Ecto.Multi
  alias Espalier.Accounts.Scope
  alias Espalier.{Audit, Catalog, Repo}
  alias Espalier.Interop.{Export, ExportWorker}

  @manifest_12 Path.expand("../../priv/scorm/imsmanifest_12.xml.eex", __DIR__)
  @manifest_2004 Path.expand("../../priv/scorm/imsmanifest_2004.xml.eex", __DIR__)
  @external_resource @manifest_12
  @external_resource @manifest_2004

  EEx.function_from_file(:defp, :manifest_12, @manifest_12, [:assigns])
  EEx.function_from_file(:defp, :manifest_2004, @manifest_2004, [:assigns])

  # The characters of the production `Char` of XML 1.0; every other code
  # point has no representation in a document, not even as a reference.
  @xml_invalid ~r/[^\x{9}\x{A}\x{D}\x{20}-\x{D7FF}\x{E000}-\x{FFFD}\x{10000}-\x{10FFFF}]/u

  @xml_entities %{
    "&" => "&amp;",
    "<" => "&lt;",
    ">" => "&gt;",
    "\"" => "&quot;",
    "'" => "&apos;"
  }

  @retention_defaults [max_age_days: 7, max_packages: 100]

  # The names of the entries that the worker writes below EXPORT_DIR: the
  # build directory, the partial zip and the zip of an export id.
  @export_entry ~r/\A([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\.(?:build|zip\.part|zip)\z/

  @typedoc "A SCORM version of an export."
  @type scorm_version :: :scorm12 | :scorm2004

  @typedoc "The status of an export."
  @type export_status :: :queued | :running | :done | :failed

  ## XML

  @doc """
  Encodes `text` for an XML element or a quoted attribute value: `&`, `<`,
  `>`, `"` and `'` become their predefined entities. A code point that XML
  1.0 does not admit and an invalid UTF-8 sequence become U+FFFD, so that
  the document stays well-formed. Every text from the content passes
  through this function as the last step before a manifest template.

      iex> Espalier.Interop.xml_escape(~s(<b class="x">Tom & Jerry's</b>))
      "&lt;b class=&quot;x&quot;&gt;Tom &amp; Jerry&apos;s&lt;/b&gt;"
  """
  @spec xml_escape(String.t()) :: String.t()
  def xml_escape(text) when is_binary(text) do
    text
    |> String.replace_invalid("�")
    |> String.replace(@xml_invalid, "�")
    |> String.replace(Map.keys(@xml_entities), &Map.fetch!(@xml_entities, &1))
  end

  @doc """
  Renders `imsmanifest.xml` of `scorm_version` from its template. `assigns`
  holds `identifier` (the manifest identifier, an XML name), `title` (the
  module title) and `files` (the relative paths of every file of the
  package other than the manifest, with forward slashes). The template
  passes every value through `xml_escape/1`.
  """
  @spec manifest(scorm_version(), %{
          identifier: String.t(),
          title: String.t(),
          files: [String.t()]
        }) :: String.t()
  def manifest(:scorm12, assigns), do: manifest_12(assigns)
  def manifest(:scorm2004, assigns), do: manifest_2004(assigns)

  ## Exports

  @doc """
  Requests the export of the module `module_id` as `scorm_version`
  (`"scorm12"` or `"scorm2004"`, or the atom) and returns `{:ok, export}`
  with status `queued`, its program and its module. Requires the role
  `author`.

  The export row, its `Espalier.Interop.ExportWorker` job and the audit
  event `export.requested` are written in one `Ecto.Multi`. A module that
  is unknown, archived or part of a program that is not published answers
  `{:error, :not_found}`, also for a malformed id, and a version outside the
  two answers `{:error, changeset}`.
  """
  def request_export(%Scope{} = scope, module_id, scorm_version) do
    with :ok <- require_author(scope),
         {:ok, module} <- published_module(module_id) do
      changeset =
        Export.request_changeset(
          %Export{
            program_id: module.program_id,
            module_id: module.id,
            requested_by_id: user_id(scope)
          },
          %{scorm_version: scorm_version}
        )

      Multi.new()
      |> Multi.insert(:export, changeset)
      |> Oban.insert(:job, fn %{export: export} -> ExportWorker.new(%{export_id: export.id}) end)
      |> Multi.run(:audit, fn _repo, %{export: export} ->
        Audit.record(scope, "export.requested", export, %{
          program_slug: module.program.slug,
          module_number: module.number,
          scorm_version: export.scorm_version
        })
      end)
      |> Repo.transact()
      |> case do
        {:ok, %{export: export}} ->
          {:ok, %{export | program: module.program, module: module}}

        {:error, _operation, reason, _changes} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Returns `{:ok, export}` with its program and its module, or
  `{:error, :not_found}` for an unknown or malformed id. Requires the role
  `author`.
  """
  def get_export(%Scope{} = scope, id) do
    with :ok <- require_author(scope) do
      with {:ok, uuid} <- Ecto.UUID.cast(id),
           %Export{} = export <- Repo.get(Export, uuid) do
        {:ok, Repo.preload(export, [:program, :module])}
      else
        _other -> {:error, :not_found}
      end
    end
  end

  @doc """
  Returns `{:ok, path}` of the package of a `done` export. The path is
  built from `export_dir/0` and the stored `file_name` only, and the name
  must be a plain basename. An export in any other status answers
  `{:error, :export_not_ready}`; a `done` export whose file is gone answers
  `{:error, :not_found}`.
  """
  def package_path(%Export{status: :done, file_name: file_name}) do
    path = stored_path(file_name)

    if path && File.regular?(path), do: {:ok, path}, else: {:error, :not_found}
  end

  def package_path(%Export{}), do: {:error, :export_not_ready}

  @doc """
  The paths that the worker writes for the export `id` below `export_dir/0`:
  the build directory `<id>.build`, the partial zip `<id>.zip.part` and the
  package `<id>.zip`. `id` is the id of an export row, a UUID.
  """
  @spec export_paths(Ecto.UUID.t()) :: %{build: String.t(), part: String.t(), zip: String.t()}
  def export_paths(id) when is_binary(id) do
    dir = export_dir()

    %{
      build: Path.join(dir, "#{id}.build"),
      part: Path.join(dir, "#{id}.zip.part"),
      zip: Path.join(dir, "#{id}.zip")
    }
  end

  @doc """
  Removes the files of the export `id`: the three paths of
  `export_paths/1` and, for a plain basename `file_name`, the stored
  package that `package_path/1` reads. A symbolic link is removed as a
  link; its target stays. Each failed removal is logged as `export file
  not removed: <name>, <reason>`, and the function then returns `:error`.
  """
  @spec remove_export_files(Ecto.UUID.t(), String.t() | nil) :: :ok | :error
  def remove_export_files(id, file_name \\ nil) do
    paths = export_paths(id)

    results =
      [paths.build, paths.part, paths.zip, stored_path(file_name)]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.map(&remove_entry/1)

    if Enum.all?(results, &(&1 == :ok)), do: :ok, else: :error
  end

  @doc """
  Changes the status of `export` only while its stored status is one of
  `from`: one `UPDATE exports ... WHERE id = $1 AND status IN (...)
  RETURNING *`, which also sets `updated_at`. `attrs` holds `status` and
  optionally `file_name` and `error`, which `Export.status_changeset/2`
  checks; an invalid value raises `Ecto.InvalidChangesetError`.

  Returns `{:ok, export}` with the stored row, or `{:error, :stale}` when
  the export has another status or is gone, for example because
  `Espalier.Interop.StaleExportWorker` set it to `failed` in the meantime.
  PostgreSQL evaluates the condition on the current row version, so of two
  concurrent transitions of one export at most one succeeds.
  """
  @spec transition_export(Export.t(), [export_status()], map()) ::
          {:ok, Export.t()} | {:error, :stale}
  def transition_export(%Export{id: id} = export, from, attrs)
      when is_list(from) and is_map(attrs) do
    target = export |> Export.status_changeset(attrs) |> Ecto.Changeset.apply_action!(:update)

    changes =
      for field <- [:status, :file_name, :error],
          Map.has_key?(attrs, field),
          do: {field, Map.fetch!(target, field)}

    query = from(e in Export, where: e.id == ^id and e.status in ^from, select: e)

    case Repo.update_all(query, set: [{:updated_at, DateTime.utc_now(:second)} | changes]) do
      {1, [updated]} -> {:ok, updated}
      {0, []} -> {:error, :stale}
    end
  end

  @doc """
  The file name of a download, `<program slug>-module-<number>-<scorm_version>.zip`,
  for an export with its program and its module.
  """
  def download_name(%Export{program: %{slug: slug}, module: %{number: number}} = export) do
    "#{slug}-module-#{number}-#{export.scorm_version}.zip"
  end

  @doc """
  The directory of the packages: `EXPORT_DIR` (`config :espalier,
  :export_dir`, task 0016 step 7) as an absolute path.
  """
  @spec export_dir() :: String.t()
  def export_dir, do: :espalier |> Application.fetch_env!(:export_dir) |> Path.expand()

  ## Retention

  @doc """
  The retention of exports from `config :espalier, :export_retention`:
  `max_age_days` (default 7) and `max_packages` (default 100), each a
  positive integer. Another value raises `ArgumentError`.
  """
  @spec retention() :: %{max_age_days: pos_integer(), max_packages: pos_integer()}
  def retention do
    config = Application.get_env(:espalier, :export_retention, [])

    Map.new(@retention_defaults, fn {key, default} ->
      case Keyword.get(config, key, default) do
        value when is_integer(value) and value > 0 ->
          {key, value}

        value ->
          raise ArgumentError,
                "export_retention #{key} must be a positive integer, got: #{inspect(value)}"
      end
    end)
  end

  @doc """
  Deletes exports by the rules of `retention/0` and removes their files.

    * `:count` deletes every export with status `done` except the newest
      `max_packages`, ordered by `updated_at`, `inserted_at` and id. The
      option `keep: id` names an export that counts as the newest: the
      export worker passes the export it has just finished, which may share
      its `updated_at` second with an earlier one.
    * `:all` first deletes every export with status `done` or `failed`
      whose `updated_at` lies more than `max_age_days` back, then applies
      `:count`, and finally removes the orphans: the direct entries of
      `EXPORT_DIR` named `<uuid>.build`, `<uuid>.zip.part` or `<uuid>.zip`
      whose id has no export row. Other names, deeper entries and the
      targets of symbolic links stay untouched.

  Each rule deletes its rows with one `DELETE ... RETURNING id, file_name`
  and removes the files of exactly these rows after the statement has
  committed, so a download that reads the row afterwards answers 404. A
  failed removal is logged, and the orphan step of the next sweep removes
  the file. An export with status `queued` or `running` is never deleted.
  Call the function outside a transaction.

  Logs `export deleted: export <id>, <rule>` per deleted export and
  `export file without export removed: <name>` per orphan, and returns the
  deleted ids and the removed orphan names.
  """
  @spec prune_exports(:count | :all, keyword()) :: %{
          deleted: [Ecto.UUID.t()],
          orphans: [String.t()]
        }
  def prune_exports(mode, opts \\ [])

  def prune_exports(:count, opts),
    do: %{deleted: delete_over_limit(retention(), opts[:keep]), orphans: []}

  def prune_exports(:all, opts) do
    retention = retention()
    expired = delete_expired(retention)
    over_limit = delete_over_limit(retention, opts[:keep])
    %{deleted: expired ++ over_limit, orphans: remove_orphans()}
  end

  defp delete_expired(%{max_age_days: days}) do
    before = DateTime.add(DateTime.utc_now(:second), -days, :day)

    delete_exports(
      from(e in Export, where: e.status in [:done, :failed] and e.updated_at < ^before),
      "older than #{days} days"
    )
  end

  # The outer condition on the status holds also for a row that a
  # concurrent statement changed, because PostgreSQL checks it again on the
  # current row version.
  defp delete_over_limit(%{max_packages: max}, keep) do
    done =
      case keep do
        nil ->
          from(e in Export, where: e.status == :done)

        id ->
          from(e in Export,
            where: e.status == :done,
            order_by: [desc: fragment("? = ?", e.id, type(^id, :binary_id))]
          )
      end

    older =
      from(e in done,
        order_by: [desc: e.updated_at, desc: e.inserted_at, desc: e.id],
        offset: ^max,
        select: e.id
      )

    delete_exports(
      from(e in Export, where: e.status == :done and e.id in subquery(older)),
      "beyond the newest #{max} packages"
    )
  end

  defp delete_exports(query, rule) do
    {_count, rows} = Repo.delete_all(from(e in query, select: {e.id, e.file_name}))

    for {id, file_name} <- rows do
      Logger.info("export deleted: export #{id}, #{rule}")
      remove_export_files(id, file_name)
      id
    end
  end

  # The names come from the listing of EXPORT_DIR and match @export_entry,
  # so every path is a direct entry of EXPORT_DIR.
  # sobelow_skip ["Traversal.FileModule"]
  defp remove_orphans do
    dir = export_dir()

    entries =
      case File.ls(dir) do
        {:ok, names} ->
          for name <- Enum.sort(names),
              [_name, id] <- [Regex.run(@export_entry, name)],
              do: {id, name}

        {:error, _reason} ->
          []
      end

    known = known_ids(entries |> Enum.map(&elem(&1, 0)) |> Enum.uniq())

    Enum.flat_map(entries, fn {id, name} ->
      with false <- MapSet.member?(known, id),
           :ok <- remove_entry(Path.join(dir, name)) do
        Logger.info("export file without export removed: #{name}")
        [name]
      else
        _kept -> []
      end
    end)
  end

  defp known_ids([]), do: MapSet.new()

  defp known_ids(ids),
    do: MapSet.new(Repo.all(from(e in Export, where: e.id in ^ids, select: e.id)))

  # File.rm_rf/1 removes a symbolic link without following it, also below a
  # directory, and treats a missing path as removed.
  # sobelow_skip ["Traversal.FileModule"]
  defp remove_entry(path) do
    case File.rm_rf(path) do
      {:ok, _removed} ->
        :ok

      {:error, reason, file} ->
        Logger.warning(
          "export file not removed: #{Path.relative_to(file, export_dir())}, " <>
            "#{:file.format_error(reason)}"
        )

        :error
    end
  end

  # A live module of a published program, with its program.
  defp published_module(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Catalog.learner_module(uuid)
      :error -> {:error, :not_found}
    end
  end

  # The path of a stored file name below EXPORT_DIR, or nil when the name is
  # no plain basename.
  defp stored_path(file_name) do
    if plain_basename?(file_name), do: Path.join(export_dir(), file_name)
  end

  defp plain_basename?(name) when is_binary(name) do
    name not in ["", ".", ".."] and Path.basename(name) == name and
      not String.contains?(name, ["/", "\\", <<0>>])
  end

  defp plain_basename?(_name), do: false

  defp user_id(%Scope{user: %{id: id}}), do: id
  defp user_id(%Scope{}), do: nil

  defp require_author(scope) do
    if Scope.has_role?(scope, :author), do: :ok, else: {:error, :forbidden}
  end
end
