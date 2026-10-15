defmodule Espalier.Catalog.Pack.DiffTest do
  use Espalier.DataCase, async: true

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import Espalier.LearningFixtures, only: [publish_demo!: 0, publish_demo!: 1, objective!: 2]
  import Espalier.PackFixtures, only: [copy_pack!: 1, demo_path: 0, update_yaml!: 3]

  alias Espalier.Accounts.Scope
  alias Espalier.AccountsFixtures
  alias Espalier.Catalog
  alias Espalier.Catalog.Pack.{Diff, Importer, Publisher}
  alias Espalier.Catalog.PackImport

  @key "ai-assistant-basics-demo"

  setup do
    author = user_with_role_fixture(:author)
    %{scope: %{Scope.for_user(author) | roles: [:learner, :author]}}
  end

  describe "after a publish of the demo pack" do
    setup do
      %{program: publish_demo!()}
    end

    test "an unchanged payload gives empty lists for every kind", %{scope: scope} do
      diff = diff!(scope, demo_payload())

      assert diff |> Map.keys() |> Enum.sort() == Enum.sort(Diff.kinds())

      for kind <- Diff.kinds() do
        assert %{added: [], changed: [], archived: []} = diff[kind], "#{kind} is not empty"
      end

      assert diff.learning_objectives.changed_fields == %{}
    end

    test "a removed objective appears under archived", %{scope: scope} do
      key = "m2-method-release-check"
      diff = diff!(scope, without_objective(demo_payload(), key))

      assert diff.learning_objectives == %{
               added: [],
               changed: [],
               archived: [key],
               changed_fields: %{}
             }

      # The item that named it loses the objective.
      assert diff.items.changed == ["m2-release-drill"]
    end

    test "a new objective appears under added", %{scope: scope} do
      payload =
        update_module(demo_payload(), 2, fn module ->
          [template | _rest] = module["objectives"]

          new =
            Map.merge(template, %{
              "key" => "m2-method-new-check",
              "statement" => "Learners can name a new check.",
              "area" => "method",
              "depth" => "know"
            })

          Map.update!(module, "objectives", &(&1 ++ [new]))
        end)

      diff = diff!(scope, payload)

      assert diff.learning_objectives == %{
               added: ["m2-method-new-check"],
               changed: [],
               archived: [],
               changed_fields: %{}
             }
    end

    test "a changed depth appears under changed with changed_fields depth", %{scope: scope} do
      key = "m1-method-check-claims"
      payload = update_objective(demo_payload(), key, &Map.put(&1, "depth", "apply"))

      assert diff!(scope, payload).learning_objectives == %{
               added: [],
               changed: [key],
               archived: [],
               changed_fields: %{key => ["depth"]}
             }
    end

    test "a changed taught_in appears with changed_fields taught_in", %{scope: scope} do
      key = "m1-method-check-claims"

      payload =
        update_objective(demo_payload(), key, fn objective ->
          refute objective["taught_in"] == ["02-second-lesson"]
          Map.put(objective, "taught_in", ["02-second-lesson"])
        end)

      assert diff!(scope, payload).learning_objectives == %{
               added: [],
               changed: [key],
               archived: [],
               changed_fields: %{key => ["taught_in"]}
             }
    end

    test "an item whose objectives change is changed, and so are the objectives it gains or loses",
         %{scope: scope} do
      payload =
        update_item(demo_payload(), "m1-before-use", fn item ->
          assert item["objectives"] == ["m1-method-check-claims"]
          Map.put(item, "objectives", ["m1-subject-varying-answers"])
        end)

      diff = diff!(scope, payload)

      assert diff.items == %{added: [], changed: ["m1-before-use"], archived: []}

      assert diff.learning_objectives == %{
               added: [],
               changed: ["m1-method-check-claims", "m1-subject-varying-answers"],
               archived: [],
               changed_fields: %{
                 "m1-method-check-claims" => ["items"],
                 "m1-subject-varying-answers" => ["items"]
               }
             }
    end

    test "a format whose objectives change is changed, and so is the objective it loses",
         %{scope: scope} do
      payload =
        update_in(demo_payload()["formats"], fn formats ->
          Enum.map(formats, fn
            %{"key" => "workshop"} = format ->
              Map.update!(format, "objectives", &List.delete(&1, "m1-social-team-transparency"))

            format ->
              format
          end)
        end)

      diff = diff!(scope, payload)

      assert diff.formats == %{added: [], changed: ["workshop"], archived: []}
      assert diff.learning_objectives.changed == ["m1-social-team-transparency"]

      assert diff.learning_objectives.changed_fields == %{
               "m1-social-team-transparency" => ["formats"]
             }
    end

    test "a module whose areas_elsewhere changes appears under changed of modules", %{
      scope: scope
    } do
      payload =
        update_module(demo_payload(), 2, fn module ->
          assert %{"social" => _social} = module["areas_elsewhere"]
          Map.update!(module, "areas_elsewhere", &Map.delete(&1, "social"))
        end)

      assert diff!(scope, payload).modules == %{added: [], changed: ["2"], archived: []}
    end

    test "a changed answer key marks the item as changed", %{scope: scope} do
      payload =
        update_item(demo_payload(), "m1-exam-next-word", fn item ->
          Map.update!(item, "options", fn options ->
            Enum.map(options, &Map.update!(&1, "correct", fn correct -> not correct end))
          end)
        end)

      assert diff!(scope, payload).items == %{
               added: [],
               changed: ["m1-exam-next-word"],
               archived: []
             }
    end

    test "a changed block text marks the lesson as changed", %{scope: scope} do
      payload =
        update_module(demo_payload(), 1, fn module ->
          Map.update!(module, "lessons", fn [first | rest] ->
            [update_in(first, ["blocks", Access.at(0), "body"], &(&1 <> " Changed.")) | rest]
          end)
        end)

      [first_lesson | _rest] = hd(payload["modules"])["lessons"]

      assert diff!(scope, payload).lessons == %{
               added: [],
               changed: ["1/#{first_lesson["key"]}"],
               archived: []
             }
    end

    test "a new citation of an item, a reordered exam and a changed requirement are changes",
         %{scope: scope} do
      demo = demo_payload()
      source = hd(demo["sources"])["key"]

      payload =
        demo
        |> update_item("m1-fluent-figure", &Map.put(&1, "cite", [source]))
        |> update_module(1, fn module ->
          Map.update!(module, "assessments", fn assessments ->
            Enum.map(assessments, &Map.update!(&1, "items", fn items -> Enum.reverse(items) end))
          end)
        end)
        |> Map.update!("qualifications", fn [first | rest] ->
          [Map.update!(first, "requirements", &tl/1) | rest]
        end)

      diff = diff!(scope, payload)
      assert diff.items.changed == ["m1-fluent-figure"]
      assert diff.assessments.changed == ["module-1-exam"]
      assert diff.qualifications.changed == [hd(demo["qualifications"])["code"]]
    end

    test "an objective whose live row is archived and that the payload holds again is added",
         %{scope: scope, program: program} do
      key = "m2-method-release-check"
      reduced = without_objective(demo_payload(), key)

      assert {:ok, %PackImport{status: :published}} =
               reduced |> validated!() |> Publisher.publish()

      assert %DateTime{} = objective!(program, key).archived_at

      # A key whose row is archived already is not archived again.
      assert diff!(scope, reduced).learning_objectives.archived == []

      assert diff!(scope, demo_payload()).learning_objectives == %{
               added: [key],
               changed: [],
               archived: [],
               changed_fields: %{}
             }
    end

    test "an import that only reorders the qualifications changes those whose place changed",
         %{scope: scope} do
      three = copy_pack!(demo_path())

      update_yaml!(three, "qualifications.yaml", fn [basics, workshop] ->
        coach = %{workshop | "code" => "coach", "title" => "Coaching in the team"}
        [basics, workshop, coach]
      end)

      publish_demo!(three)

      assert diff!(scope, pack_payload(three)).qualifications == %{
               added: [],
               changed: [],
               archived: []
             }

      reversed = copy_pack!(three)
      update_yaml!(reversed, "qualifications.yaml", &Enum.reverse/1)
      payload = pack_payload(reversed)
      assert Enum.map(payload["qualifications"], & &1["code"]) == ["coach", "workshop", "basics"]

      diff = diff!(scope, payload)

      # workshop keeps place 2; basics and coach trade places 1 and 3.
      assert diff.qualifications == %{added: [], changed: ["basics", "coach"], archived: []}

      for kind <- Diff.kinds() -- [:qualifications] do
        assert %{added: [], changed: [], archived: []} = diff[kind], "#{kind} is not empty"
      end
    end
  end

  test "without a program every key of the payload is added", %{scope: scope} do
    payload = demo_payload()
    diff = diff!(scope, payload)

    for kind <- Diff.kinds() do
      assert %{changed: [], archived: []} = diff[kind]
    end

    assert diff.modules.added == ["1", "2"]

    assert diff.lessons.added == [
             "1/01-first-lesson",
             "1/02-second-lesson",
             "1/03-third-lesson",
             "2/01-first-lesson",
             "2/02-second-lesson"
           ]

    assert diff.rules.added == ~w(1/1 1/2 1/3 1/4 1/5 1/6 2/1 2/2 2/3 2/4)
    assert diff.learning_objectives.added == Enum.sort(keys(payload, "objectives"))
    assert length(diff.learning_objectives.added) == 8
    assert diff.learning_objectives.changed_fields == %{}
    assert diff.items.added == Enum.sort(keys(payload, "items"))
    assert length(diff.items.added) == 12
    assert diff.assessments.added == ["module-1-exam"]
    assert diff.qualifications.added == ["basics", "workshop"]
    assert diff.formats.added == ["handbook", "help-desk", "workshop"]
    assert length(diff.sources.added) == 2
    assert length(diff.segments.added) == 4
    assert length(diff.glossary_terms.added) == 8
  end

  describe "Catalog.pack_diff/2" do
    test "answers not_publishable for an import without payload", %{scope: scope} do
      pack_import =
        Repo.insert!(%PackImport{
          pack_key: @key,
          status: :failed,
          report: %{"errors" => [], "warnings" => []},
          payload: nil
        })

      assert Catalog.pack_diff(scope, pack_import) == {:error, :not_publishable}
    end

    test "requires the role author" do
      learner = Scope.for_user(AccountsFixtures.user_fixture())
      pack_import = validated!(demo_payload())

      assert Catalog.pack_diff(learner, pack_import) == {:error, :forbidden}
    end
  end

  ## Helpers

  # Stores `payload` as a validated import, reads it back through the
  # context and returns its diff.
  defp diff!(scope, payload) do
    pack_import = validated!(payload)
    assert {:ok, stored} = Catalog.get_pack_import(scope, pack_import.id)
    assert {:ok, diff} = Catalog.pack_diff(scope, stored)
    diff
  end

  defp validated!(payload) do
    Repo.insert!(%PackImport{
      pack_key: payload["key"],
      pack_version: payload["version"],
      status: :validated,
      report: %{"errors" => [], "warnings" => []},
      payload: payload
    })
  end

  defp demo_payload, do: pack_payload(demo_path())

  defp pack_payload(path) do
    {:ok, %PackImport{status: :validated, payload: payload}} = Importer.import(path, nil)
    payload
  end

  defp keys(payload, list) do
    for module <- payload["modules"], entry <- module[list], do: entry["key"]
  end

  defp update_module(payload, number, fun) do
    update_in(payload["modules"], fn modules ->
      Enum.map(modules, &if(&1["number"] == number, do: fun.(&1), else: &1))
    end)
  end

  # Applies `fun` to the list `list` (objectives or items) of every module.
  defp update_lists(payload, list, fun) do
    update_in(payload["modules"], fn modules -> Enum.map(modules, &Map.update!(&1, list, fun)) end)
  end

  # Applies `fun` to the entry `key` of the list `list` of every module.
  defp update_entry(payload, list, key, fun) do
    update_lists(payload, list, fn entries -> Enum.map(entries, &apply_to_key(&1, key, fun)) end)
  end

  defp apply_to_key(%{"key" => key} = entry, key, fun), do: fun.(entry)
  defp apply_to_key(entry, _key, _fun), do: entry

  defp update_objective(payload, key, fun), do: update_entry(payload, "objectives", key, fun)

  defp update_item(payload, key, fun), do: update_entry(payload, "items", key, fun)

  # The payload without the objective `key` and without every reference of
  # an item or a format to it.
  defp without_objective(payload, key) do
    payload
    |> update_lists("objectives", fn objectives ->
      Enum.reject(objectives, &(&1["key"] == key))
    end)
    |> update_lists("items", fn items -> Enum.map(items, &drop_objective(&1, key)) end)
    |> Map.update!("formats", fn formats -> Enum.map(formats, &drop_objective(&1, key)) end)
  end

  defp drop_objective(entry, key), do: Map.update!(entry, "objectives", &List.delete(&1, key))
end
