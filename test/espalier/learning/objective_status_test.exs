defmodule Espalier.Learning.ObjectiveStatusTest do
  @moduledoc """
  `derive/2` on in-memory links and facts (README section 7, rule 15): an
  objective is evidenced through a passed assessment, an attended format or
  a correct item among its own evidence, and open otherwise.
  """
  use ExUnit.Case, async: true

  alias Espalier.Catalog.LearningObjective
  alias Espalier.Learning.ObjectiveStatus

  @no_facts %{passed_assessment_ids: [], attended_format_ids: [], correct_item_ids: []}

  setup do
    %{
      assessment_id: uuid(),
      other_assessment_id: uuid(),
      format_id: uuid(),
      other_format_id: uuid(),
      item_id: uuid(),
      other_item_id: uuid()
    }
  end

  test "evidenced through a passed assessment among its assessment_ids", ids do
    links = [
      link("m1-subject-next-word", assessment_ids: [ids.other_assessment_id, ids.assessment_id])
    ]

    facts = %{@no_facts | passed_assessment_ids: [ids.assessment_id]}

    assert ObjectiveStatus.derive(links, facts) == [
             %{key: "m1-subject-next-word", status: :evidenced}
           ]
  end

  test "evidenced through an attended format among its format_ids", ids do
    links = [link("m1-self-own-responsibility", format_ids: [ids.format_id])]
    facts = %{@no_facts | attended_format_ids: [ids.format_id]}

    assert ObjectiveStatus.derive(links, facts) == [
             %{key: "m1-self-own-responsibility", status: :evidenced}
           ]
  end

  test "evidenced through a correct item among its item_ids", ids do
    links = [link("m2-method-release-check", item_ids: [ids.item_id])]
    facts = %{@no_facts | correct_item_ids: [ids.item_id]}

    assert ObjectiveStatus.derive(links, facts) == [
             %{key: "m2-method-release-check", status: :evidenced}
           ]
  end

  test "open with three empty sets", ids do
    links = [
      link("m1-subject-next-word",
        assessment_ids: [ids.assessment_id],
        format_ids: [ids.format_id],
        item_ids: [ids.item_id]
      )
    ]

    assert ObjectiveStatus.derive(links, @no_facts) == [
             %{key: "m1-subject-next-word", status: :open}
           ]
  end

  test "open when the passed assessment is not among its assessment_ids", ids do
    links = [link("m1-subject-next-word", assessment_ids: [ids.assessment_id])]
    facts = %{@no_facts | passed_assessment_ids: [ids.other_assessment_id]}

    assert ObjectiveStatus.derive(links, facts) == [
             %{key: "m1-subject-next-word", status: :open}
           ]
  end

  test "open when the attended format is missing from its format_ids", ids do
    links = [link("m1-self-own-responsibility", format_ids: [ids.format_id])]
    facts = %{@no_facts | attended_format_ids: [ids.other_format_id]}

    assert ObjectiveStatus.derive(links, facts) == [
             %{key: "m1-self-own-responsibility", status: :open}
           ]
  end

  test "open when the correct item is not among its item_ids", ids do
    links = [link("m2-method-release-check", item_ids: [ids.item_id])]
    facts = %{@no_facts | correct_item_ids: [ids.other_item_id]}

    assert ObjectiveStatus.derive(links, facts) == [
             %{key: "m2-method-release-check", status: :open}
           ]
  end

  test "keeps the order of the links, one entry with key and status per link", ids do
    links = [
      link("m2-method-release-check", item_ids: [ids.item_id]),
      link("m1-subject-next-word", assessment_ids: [ids.assessment_id]),
      link("m1-self-own-responsibility", format_ids: [ids.format_id]),
      link("m1-method-check-claims", item_ids: [ids.other_item_id])
    ]

    facts = %{
      passed_assessment_ids: [ids.assessment_id],
      attended_format_ids: [],
      correct_item_ids: [ids.item_id]
    }

    result = ObjectiveStatus.derive(links, facts)

    assert result == [
             %{key: "m2-method-release-check", status: :evidenced},
             %{key: "m1-subject-next-word", status: :evidenced},
             %{key: "m1-self-own-responsibility", status: :open},
             %{key: "m1-method-check-claims", status: :open}
           ]

    for entry <- result, do: assert(entry |> Map.keys() |> Enum.sort() == [:key, :status])
  end

  test "takes the facts as lists or as MapSets", ids do
    links = [
      link("m1-subject-next-word", assessment_ids: [ids.assessment_id]),
      link("m1-self-own-responsibility", format_ids: [ids.format_id]),
      link("m2-method-release-check", item_ids: [ids.item_id]),
      link("m1-method-check-claims", item_ids: [ids.other_item_id])
    ]

    lists = %{
      passed_assessment_ids: [ids.assessment_id],
      attended_format_ids: [ids.format_id],
      correct_item_ids: [ids.item_id]
    }

    sets = Map.new(lists, fn {name, values} -> {name, MapSet.new(values)} end)
    expected = [:evidenced, :evidenced, :evidenced, :open]

    assert links |> ObjectiveStatus.derive(lists) |> Enum.map(& &1.status) == expected
    assert links |> ObjectiveStatus.derive(sets) |> Enum.map(& &1.status) == expected
  end

  test "gives no entry for no links" do
    assert ObjectiveStatus.derive([], @no_facts) == []
  end

  defp link(key, evidence) do
    %{
      objective: %LearningObjective{id: uuid(), key: key},
      lesson_ids: [uuid()],
      item_ids: Keyword.get(evidence, :item_ids, []),
      format_ids: Keyword.get(evidence, :format_ids, []),
      assessment_ids: Keyword.get(evidence, :assessment_ids, [])
    }
  end

  defp uuid, do: Ecto.UUID.generate()
end
