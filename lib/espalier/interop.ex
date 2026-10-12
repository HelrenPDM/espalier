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

  The manifests come from the fixed EEx templates
  `priv/scorm/imsmanifest_12.xml.eex` and
  `priv/scorm/imsmanifest_2004.xml.eex`, compiled into this module, and
  every value enters them through `xml_escape/1` (ASVS 1.1.2, 1.2.1 and
  1.3.7).
  """

  require EEx

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

  @typedoc "A SCORM version of an export."
  @type scorm_version :: :scorm12 | :scorm2004

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
    path = plain_basename?(file_name) && Path.join(export_dir(), file_name)

    if path && File.regular?(path), do: {:ok, path}, else: {:error, :not_found}
  end

  def package_path(%Export{}), do: {:error, :export_not_ready}

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

  # A live module of a published program, with its program.
  defp published_module(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Catalog.learner_module(uuid)
      :error -> {:error, :not_found}
    end
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
