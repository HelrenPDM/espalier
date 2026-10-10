defmodule Espalier.LearningFixtures do
  @moduledoc """
  Helpers for the tests of task 0009: the published demo pack, lookups of
  catalog rows by key, enrollments, and answers built from the answer key
  of an item. Only tests build answers from the answer key; the application
  reads it in `Espalier.Learning.Evaluator` alone.
  """

  import Ecto.Query

  alias Espalier.Accounts.Scope
  alias Espalier.Catalog

  alias Espalier.Catalog.{
    Assessment,
    AssessmentItem,
    CompanionFormat,
    Item,
    LearningObjective,
    PackImport
  }

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.{Learning, PackFixtures, Repo}

  @slug "ai-assistant-basics-demo"

  @doc "The slug of the demo program."
  def demo_slug, do: @slug

  @doc "Imports and publishes the pack at `path` (default: the demo pack) and returns its program."
  def publish_demo!(path \\ PackFixtures.demo_path()) do
    {:ok, %PackImport{status: :validated} = pack_import} = Importer.import(path, nil)
    {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    Catalog.get_program_by_slug(@slug)
  end

  @doc "The item `key` of `program`, with options, rules and reveals."
  def item!(program, key) do
    Item
    |> Repo.get_by!(program_id: program.id, key: key)
    |> Repo.preload([:options, :rules, :reveals])
  end

  @doc "The assessment `key` of `program`."
  def assessment!(program, key \\ "module-1-exam"),
    do: Repo.get_by!(Assessment, program_id: program.id, key: key)

  @doc "The module `number` of `program`."
  def module!(program, number),
    do: Repo.get_by!(CatalogModule, program_id: program.id, number: number)

  @doc "The learning objective `key` of `program`."
  def objective!(program, key),
    do: Repo.get_by!(LearningObjective, program_id: program.id, key: key)

  @doc "The companion format `key` of `program`."
  def format!(program, key), do: Repo.get_by!(CompanionFormat, program_id: program.id, key: key)

  @doc "The items of an assessment in position order, ready for answers."
  def exam_items!(assessment) do
    Repo.all(
      from ai in AssessmentItem,
        join: i in assoc(ai, :item),
        where: ai.assessment_id == ^assessment.id,
        order_by: ai.position,
        select: i
    )
    |> Repo.preload([:options])
  end

  @doc "A scope for `user` as the request pipeline builds it."
  def scope_for(user), do: Scope.for_user(user)

  @doc "Enrolls the user of `scope` in the demo program."
  def enroll!(scope, path \\ "short", slug \\ @slug) do
    {:ok, _status, enrollment} = Learning.enroll(scope, slug, path)
    enrollment
  end

  @doc """
  The correct answer to `item`, as a JSON map with string keys (the form of a
  request body). A poll answer chooses its first option.
  """
  def correct_answer(%Item{kind: kind} = item) when kind in [:single_choice, :multiple_choice],
    do: %{"options" => for(o <- item.options, o.correct, do: o.key)}

  def correct_answer(%Item{kind: :poll} = item),
    do: %{"options" => [hd(Enum.sort_by(item.options, & &1.position)).key]}

  def correct_answer(%Item{kind: :slot_builder, config: config}) do
    %{
      "slots" =>
        Map.new(config["slots"], fn slot ->
          {slot["key"], Enum.find(slot["options"], & &1["correct"])["key"]}
        end)
    }
  end

  def correct_answer(%Item{kind: :classification, config: config}),
    do: %{"cases" => config["expected"]}

  def correct_answer(%Item{kind: :checklist_drill, config: config}) do
    %{
      "checks" => for(check <- config["checks"], check["required"], do: check["key"]),
      "initials" => "AB"
    }
  end

  @doc "A wrong answer to `item` (not for a poll)."
  def wrong_answer(%Item{kind: kind} = item) when kind in [:single_choice, :multiple_choice],
    do: %{"options" => [Enum.find(item.options, &(not &1.correct)).key]}

  def wrong_answer(%Item{kind: :slot_builder, config: config}) do
    %{
      "slots" =>
        Map.new(config["slots"], fn slot ->
          {slot["key"], Enum.find(slot["options"], &(not &1["correct"]))["key"]}
        end)
    }
  end

  def wrong_answer(%Item{kind: :classification, config: config}) do
    [first | rest] = config["categories"] |> Enum.map(& &1["key"])
    rotated = rest ++ [first]
    mapping = Enum.zip(Enum.map(config["categories"], & &1["key"]), rotated) |> Map.new()
    %{"cases" => Map.new(config["expected"], fn {c, category} -> {c, mapping[category]} end)}
  end

  def wrong_answer(%Item{kind: :checklist_drill}), do: %{"checks" => [], "initials" => "AB"}

  @doc """
  Converts a JSON answer into the form that `CastAndValidate` hands to the
  context: atom keys for the members, string keys inside `slots` and `cases`.
  """
  def cast_answer(answer) do
    Map.new(answer, fn {key, value} -> {String.to_existing_atom(key), value} end)
  end

  @doc """
  Answers for every item of `assessment`: the items whose keys are in
  `wrong` get a wrong answer, the others the correct one.
  """
  def exam_answers(assessment, wrong \\ []) do
    Map.new(exam_items!(assessment), fn item ->
      answer = if item.key in wrong, do: wrong_answer(item), else: correct_answer(item)
      {item.id, answer}
    end)
  end
end
