defmodule EspalierWeb.Admin.PackJSON do
  @moduledoc """
  The views of `EspalierWeb.Admin.PackController` (task 0015, step 7).

  The pack view carries the report, the payload of a `validated` import
  (with answer keys; the route is restricted to authors) and `alignment`:
  `mode` and `matrix` from the stored payload (`nil` without one) and the
  report entries of `Espalier.Catalog.Alignment.check/1` with file and line,
  split into `errors` and `warnings`.
  """

  alias Espalier.Catalog.{Alignment, PackImport}

  @finding_members ~w(file line check module key message)

  @doc "Renders an import."
  def show(%{pack_import: %PackImport{} = pack_import}) do
    report = pack_import.report || %{}
    errors = Map.get(report, "errors", [])
    warnings = Map.get(report, "warnings", [])
    payload = pack_import.payload

    %{
      id: pack_import.id,
      status: pack_import.status,
      pack_key: pack_import.pack_key,
      pack_version: pack_import.pack_version,
      inserted_at: pack_import.inserted_at,
      published_at: pack_import.published_at,
      report: %{errors: errors, warnings: warnings},
      payload: if(pack_import.status == :validated, do: payload),
      alignment: %{
        mode: if(is_map(payload), do: payload["alignment"]),
        matrix: if(is_map(payload), do: Alignment.matrix(payload)),
        errors: findings(errors),
        warnings: findings(warnings)
      }
    }
  end

  @doc "Renders the 422 answer of a rejected archive."
  def archive_rejected(%{entries: entries}) do
    %{error: "archive_rejected", report: %{errors: entries, warnings: []}}
  end

  @doc "Renders the 409 answer `alignment_errors`."
  def alignment_errors(%{findings: findings}) do
    %{
      error: "alignment_errors",
      findings: Enum.map(findings, &Map.take(&1, [:check, :module, :file, :key, :message]))
    }
  end

  @doc "Renders the diff of `Espalier.Catalog.Pack.Diff.compute/1`."
  def diff(%{diff: diff}), do: diff

  # The report entries of the alignment checks are the ones with `check`.
  defp findings(entries) do
    for %{"check" => check} = entry when is_integer(check) <- entries,
        do: Map.take(entry, @finding_members)
  end
end
