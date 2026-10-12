defmodule EspalierWeb.InsightsJSON do
  @moduledoc """
  Views of the insights routes (task 0014). Every view names its members
  explicitly. The report views render the cells of
  `Espalier.Insights.cell/2` unchanged, so a suppressed cell carries
  neither a count nor a value.
  """

  @doc "Renders the answer of a self-assessment."
  def self_assessment(%{path: path, already_recorded: already_recorded}) do
    %{path: path, already_recorded: already_recorded}
  end

  @doc "Renders whether an anonymous answer is new."
  def recorded(%{already_recorded: already_recorded}), do: %{already_recorded: already_recorded}

  @doc "Renders the participation of the signed-in user."
  def participation(participation) do
    %{
      self_assessment: participation.self_assessment,
      feedback: participation.feedback,
      format_votes: participation.format_votes
    }
  end

  @doc "Renders the self-assessment report."
  def self_assessment_report(report) do
    %{
      min_group_size: report.min_group_size,
      locale: report.locale,
      by_org_unit: report.by_org_unit,
      months: report.months,
      rows:
        Enum.map(report.rows, fn row ->
          %{
            segment_key: row.segment_key,
            label: row.label,
            org_unit: row.org_unit,
            cells: Enum.map(row.cells, &cell/1)
          }
        end)
    }
  end

  @doc "Renders the item report."
  def item_report(report) do
    %{
      min_group_size: report.min_group_size,
      locale: report.locale,
      months: report.months,
      rows:
        Enum.map(report.rows, fn row ->
          %{
            item_id: row.item_id,
            key: row.key,
            kind: row.kind,
            module_number: row.module_number,
            stem: row.stem,
            cells: Enum.map(row.cells, &cell/1)
          }
        end)
    }
  end

  @doc "Renders the competence report."
  def competence_report(report) do
    %{
      min_group_size: report.min_group_size,
      locale: report.locale,
      by_org_unit: report.by_org_unit,
      months: report.months,
      rows:
        Enum.map(report.rows, fn row ->
          %{
            area: row.area,
            depth: row.depth,
            org_unit: row.org_unit,
            cells: Enum.map(row.cells, &cell/1)
          }
        end)
    }
  end

  @doc "Renders the format report."
  def format_report(report) do
    %{
      min_group_size: report.min_group_size,
      locale: report.locale,
      formats:
        Enum.map(report.formats, fn format ->
          %{id: format.id, key: format.key, title: format.title, cell: cell(format.cell)}
        end)
    }
  end

  @doc "Renders the feedback report."
  def feedback_report(report) do
    %{
      min_group_size: report.min_group_size,
      locale: report.locale,
      questions:
        Enum.map(report.questions, fn question ->
          %{
            key: question.key,
            kind: question.kind,
            label: question.label,
            choices:
              Enum.map(question.choices, fn choice ->
                %{key: choice.key, label: choice.label, cell: cell(choice.cell)}
              end),
            free_text: free_text(question.free_text)
          }
        end)
    }
  end

  @doc "Renders the credential report."
  def credential_report(report) do
    %{
      min_group_size: report.min_group_size,
      locale: report.locale,
      qualifications:
        Enum.map(report.qualifications, fn qualification ->
          %{
            code: qualification.code,
            title: qualification.title,
            archived: qualification.archived,
            statuses:
              Enum.map(qualification.statuses, fn entry ->
                %{status: entry.status, cell: cell(entry.cell)}
              end)
          }
        end)
    }
  end

  defp cell(%{suppressed: true}), do: %{suppressed: true}
  defp cell(%{count: count, value: value}), do: %{count: count, value: value}

  defp free_text(nil), do: nil
  defp free_text(%{suppressed: true}), do: %{suppressed: true}
  defp free_text(%{count: count, answers: answers}), do: %{count: count, answers: answers}
end
