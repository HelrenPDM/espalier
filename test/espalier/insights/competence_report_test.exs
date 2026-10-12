defmodule Espalier.Insights.CompetenceReportTest do
  @moduledoc """
  `Espalier.Insights.competence_report/2` (task 0014, step 8, the paragraph
  on the competence report, and the cases of step 13) on catalog rows that
  the tests insert directly: a program, its modules, learning objectives,
  items, `item_objectives` rows and `item_stats` rows.

  The cases cover the links (one cell for two items of one objective, one
  count for an item with two objectives of the same area and depth, a count
  in each row for an item with two areas and depths, and no count for
  polls, archived items, archived objectives and archived modules), the
  months in ascending order with a suppressed cell for a month without
  statistics, the grouping by org unit with `insights_org_unit` true and
  false, the order of the rows by area and depth, the threshold on the
  summed count of a cell, and the acceptance case of a changed depth: the
  report reads area and depth from `learning_objectives` alone.

  The cases of the secondary suppression build the item report next to the
  competence report and show that no suppressed count follows from the two,
  by difference, by the bounds of the suppressed cells or by which cells are
  suppressed: an item with fewer attempts than the threshold in one org unit
  of a month (without the breakdown: in that month) suppresses every cell of
  each area and depth it names in that month, in every org unit, also cells
  whose sum reaches the threshold, and every area and depth has a row for
  every org unit of the report.

  The module changes `config :espalier, :insights` and `:learning` through
  `put_insights/1` and `put_learning/1` and therefore runs with
  `async: false`.
  """
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import Espalier.InsightsFixtures

  alias Ecto.UUID
  alias Espalier.{Accounts, Insights}
  alias Espalier.Accounts.Scope
  alias Espalier.Catalog.{Item, LearningObjective, Program}
  alias Espalier.Catalog.Module, as: CatalogModule

  @august ~D[2026-08-01]
  @september ~D[2026-09-01]

  setup do
    # A threshold of 1 shows every cell with at least one attempt, so the
    # cases below read the counts and shares; a month without statistics
    # has the count 0 and stays suppressed.
    put_insights(min_group_size: 1)
    put_learning(insights_org_unit: false)

    program = insert_program()
    %{scope: analyst_scope(), program: program, module: insert_module(program, 1)}
  end

  describe "links through item_objectives" do
    test "two items that name the same subject/know objective sum into one cell",
         %{scope: scope, program: program, module: module} do
      objective = insert_objective(module, "m1-subject-know", :subject, :know)
      first = insert_item(module, "first")
      second = insert_item(module, "second")
      link(first, [objective])
      link(second, [objective])

      item_stat!(first, @september, 4, 3)
      item_stat!(second, @september, 6, 2)

      assert {:ok, report} = Insights.competence_report(scope, program.slug)

      assert report == %{
               by_org_unit: false,
               locale: "en",
               min_group_size: 1,
               months: [@september],
               rows: [
                 %{
                   area: :subject,
                   depth: :know,
                   org_unit: nil,
                   cells: [%{count: 4 + 6, value: (3 + 2) / (4 + 6)}]
                 }
               ]
             }
    end

    test "an item that names two objectives of the same area and depth counts once in that row",
         %{scope: scope, program: program, module: module} do
      first = insert_objective(module, "m1-subject-know-a", :subject, :know)
      second = insert_objective(module, "m1-subject-know-b", :subject, :know)
      item = insert_item(module, "twice-linked")
      link(item, [first, second])

      item_stat!(item, @september, 5, 4)

      assert {:ok,
              %{
                by_org_unit: false,
                months: [@september],
                rows: [%{area: :subject, depth: :know, org_unit: nil, cells: [cell]}]
              }} = Insights.competence_report(scope, program.slug)

      assert cell == %{count: 5, value: 0.8}
    end

    test "an item that names a subject/know and a method/apply objective counts in both rows",
         %{scope: scope, program: program, module: module} do
      subject = insert_objective(module, "m1-subject-know", :subject, :know)
      method = insert_objective(module, "m1-method-apply", :method, :apply)
      item = insert_item(module, "two-areas")
      link(item, [method, subject])

      item_stat!(item, @september, 5, 4)

      assert {:ok, %{by_org_unit: false, months: [@september], rows: rows}} =
               Insights.competence_report(scope, program.slug)

      assert rows == [
               %{area: :subject, depth: :know, org_unit: nil, cells: [%{count: 5, value: 0.8}]},
               %{area: :method, depth: :apply, org_unit: nil, cells: [%{count: 5, value: 0.8}]}
             ]
    end

    test "polls, archived items, archived objectives and archived modules add to no cell",
         %{scope: scope, program: program, module: module} do
      archived = DateTime.utc_now(:second)
      archived_module = insert_module(program, 2, archived)

      subject = insert_objective(module, "m1-subject-know", :subject, :know)
      retired = insert_objective(module, "m1-method-apply", :method, :apply, archived)
      gone = insert_objective(archived_module, "m2-self-judge", :self, :judge)

      live = insert_item(module, "live")
      poll = insert_item(module, "poll", :poll)
      archived_item = insert_item(module, "archived-item", :single_choice, archived)
      retired_only = insert_item(module, "retired-objective-only")
      archived_module_item = insert_item(archived_module, "archived-module-item")
      gone_only = insert_item(module, "archived-module-objective-only")

      link(live, [subject])
      link(poll, [subject])
      link(archived_item, [subject])
      link(retired_only, [retired])
      link(archived_module_item, [subject])
      link(gone_only, [gone])

      item_stat!(live, @september, 5, 4)

      for item <- [poll, archived_item, retired_only, archived_module_item, gone_only] do
        item_stat!(item, @september, 7, 7)
        item_stat!(item, @august, 3, 0)
      end

      assert {:ok, report} = Insights.competence_report(scope, program.slug)

      assert report == %{
               by_org_unit: false,
               locale: "en",
               min_group_size: 1,
               months: [@september],
               rows: [
                 %{area: :subject, depth: :know, org_unit: nil, cells: [%{count: 5, value: 0.8}]}
               ]
             }
    end
  end

  describe "months" do
    test "two periods give two months in ascending order and a suppressed cell for a month without statistics",
         %{scope: scope, program: program, module: module} do
      subject = insert_objective(module, "m1-subject-know", :subject, :know)
      method = insert_objective(module, "m1-method-apply", :method, :apply)
      subject_item = insert_item(module, "subject-item")
      method_item = insert_item(module, "method-item")
      link(subject_item, [subject])
      link(method_item, [method])

      # The later month comes first, so the order of the months does not
      # follow the order of insertion.
      item_stat!(subject_item, @september, 8, 6)
      item_stat!(method_item, @september, 4, 1)
      item_stat!(subject_item, @august, 5, 2)

      assert {:ok, report} = Insights.competence_report(scope, program.slug)

      assert report == %{
               by_org_unit: false,
               locale: "en",
               min_group_size: 1,
               months: [@august, @september],
               rows: [
                 %{
                   area: :subject,
                   depth: :know,
                   org_unit: nil,
                   cells: [%{count: 5, value: 0.4}, %{count: 8, value: 0.75}]
                 },
                 %{
                   area: :method,
                   depth: :apply,
                   org_unit: nil,
                   cells: [%{suppressed: true}, %{count: 4, value: 0.25}]
                 }
               ]
             }
    end
  end

  describe "org units" do
    setup %{module: module} do
      objective = insert_objective(module, "m1-subject-know", :subject, :know)
      item = insert_item(module, "org-unit-item")
      link(item, [objective])

      item_stat!(item, @september, 5, 4, org_unit: "Unit B")
      item_stat!(item, @september, 3, 1, org_unit: "Unit A")
      item_stat!(item, @september, 2, 1)

      :ok
    end

    test "with insights_org_unit true, each org unit has a row of its own, nil last",
         %{scope: scope, program: program} do
      put_learning(insights_org_unit: true)

      assert {:ok, report} = Insights.competence_report(scope, program.slug)

      assert report == %{
               by_org_unit: true,
               locale: "en",
               min_group_size: 1,
               months: [@september],
               rows: [
                 %{
                   area: :subject,
                   depth: :know,
                   org_unit: "Unit A",
                   cells: [%{count: 3, value: 0.3333}]
                 },
                 %{
                   area: :subject,
                   depth: :know,
                   org_unit: "Unit B",
                   cells: [%{count: 5, value: 0.8}]
                 },
                 %{area: :subject, depth: :know, org_unit: nil, cells: [%{count: 2, value: 0.5}]}
               ]
             }
    end

    test "with insights_org_unit false, the org units sum into one row with org_unit nil",
         %{scope: scope, program: program} do
      assert {:ok, report} = Insights.competence_report(scope, program.slug)

      assert report == %{
               by_org_unit: false,
               locale: "en",
               min_group_size: 1,
               months: [@september],
               rows: [
                 %{
                   area: :subject,
                   depth: :know,
                   org_unit: nil,
                   cells: [%{count: 5 + 3 + 2, value: (4 + 1 + 1) / (5 + 3 + 2)}]
                 }
               ]
             }
    end
  end

  describe "order of the rows" do
    test "rows follow the order of the areas and the depths, whatever the order of insertion",
         %{scope: scope, program: program, module: module} do
      areas = Ecto.Enum.values(LearningObjective, :area)
      depths = Ecto.Enum.values(LearningObjective, :depth)
      assert areas == [:subject, :method, :self, :social]
      assert depths == [:know, :apply, :judge]

      # Each combination gets its own number of attempts, so that a cell
      # shows which combination it belongs to. The objectives, items and
      # statistics are inserted from the last combination to the first.
      combinations =
        for {area, a} <- Enum.with_index(areas), {depth, d} <- Enum.with_index(depths) do
          {area, depth, 10 + 3 * a + d}
        end

      for {area, depth, attempts} <- Enum.reverse(combinations) do
        objective = insert_objective(module, "m1-#{area}-#{depth}", area, depth)
        item = insert_item(module, "item-#{area}-#{depth}")
        link(item, [objective])
        item_stat!(item, @september, attempts, attempts)
      end

      assert {:ok, %{by_org_unit: false, months: [@september], rows: rows}} =
               Insights.competence_report(scope, program.slug)

      assert rows ==
               for(
                 {area, depth, attempts} <- combinations,
                 do: %{
                   area: area,
                   depth: depth,
                   org_unit: nil,
                   cells: [%{count: attempts, value: 1.0}]
                 }
               )
    end
  end

  describe "threshold" do
    test "a shown cell carries the summed count, a cell at the threshold is shown and one below it is suppressed",
         %{scope: scope, program: program, module: module} do
      put_insights(min_group_size: 5)

      subject = insert_objective(module, "m1-subject-know", :subject, :know)
      method = insert_objective(module, "m1-method-apply", :method, :apply)
      self_judge = insert_objective(module, "m1-self-judge", :self, :judge)
      first = insert_item(module, "first")
      second = insert_item(module, "second")
      third = insert_item(module, "third")
      link(first, [subject, method])
      link(second, [subject])
      link(third, [self_judge])

      # The subject/know cell sums both items, the method/apply cell holds
      # the first item alone at the threshold, and the self/judge cell holds
      # the third item alone below it.
      item_stat!(first, @september, 5, 3)
      item_stat!(second, @september, 5, 2)
      item_stat!(third, @september, 4, 4)

      assert {:ok, report} = Insights.competence_report(scope, program.slug)

      assert report == %{
               by_org_unit: false,
               locale: "en",
               min_group_size: 5,
               months: [@september],
               rows: [
                 %{
                   area: :subject,
                   depth: :know,
                   org_unit: nil,
                   cells: [%{count: 5 + 5, value: (3 + 2) / (5 + 5)}]
                 },
                 %{area: :method, depth: :apply, org_unit: nil, cells: [%{count: 5, value: 0.6}]},
                 %{area: :self, depth: :judge, org_unit: nil, cells: [%{suppressed: true}]}
               ]
             }
    end
  end

  # The item report shows the attempts of each item per month, summed over
  # the org units. The cases below build it next to the competence report
  # and show that no suppressed count follows from the two reports by
  # difference.
  describe "secondary suppression without the org-unit breakdown" do
    setup %{module: module} do
      put_insights(min_group_size: 5)

      objective = insert_objective(module, "m1-subject-know", :subject, :know)
      x = insert_item(module, "x")
      y = insert_item(module, "y")
      link(x, [objective])
      link(y, [objective])

      %{x: x, y: y}
    end

    test "an item below the threshold suppresses the cell although the sum reaches it, and at the threshold the cell shows the sum",
         %{scope: scope, program: program, x: x, y: y} do
      item_stat!(x, @september, 40, 32)
      y_stat = item_stat!(y, @september, 2, 1)

      # The sum of 42 reaches the threshold, but a shown cell of 42 minus
      # the 40 attempts of X in the item report would give the 2 attempts
      # of Y, which the item report suppresses.
      assert {:ok, %{months: [@september], rows: rows}} =
               Insights.competence_report(scope, program.slug)

      assert rows == [
               %{area: :subject, depth: :know, org_unit: nil, cells: [%{suppressed: true}]}
             ]

      assert item_cells(scope, program) == %{
               "x" => [%{count: 40, value: 0.8}],
               "y" => [%{suppressed: true}]
             }

      # With five attempts of Y, every item reaches the threshold, and the
      # cell shows the sum and the share correct of both items.
      y_stat |> Ecto.Changeset.change(attempts: 5, correct: 4) |> Repo.update!()

      assert {:ok, %{months: [@september], rows: rows}} =
               Insights.competence_report(scope, program.slug)

      assert rows == [
               %{
                 area: :subject,
                 depth: :know,
                 org_unit: nil,
                 cells: [%{count: 40 + 5, value: (32 + 4) / (40 + 5)}]
               }
             ]

      assert item_cells(scope, program) == %{
               "x" => [%{count: 40, value: 0.8}],
               "y" => [%{count: 5, value: 0.8}]
             }
    end
  end

  # The cases below fill the subject/know cells of September, and the item
  # report sums the org units of each item into its total. With the
  # breakdown, only an org unit with a shown cell has rows, so a report in
  # which every cell is suppressed lists none.
  describe "secondary suppression with the org-unit breakdown" do
    setup %{module: module} do
      put_insights(min_group_size: 5)
      put_learning(insights_org_unit: true)

      objective = insert_objective(module, "m1-subject-know", :subject, :know)
      x = insert_item(module, "x")
      link(x, [objective])

      %{objective: objective, x: x}
    end

    test "an item with fewer attempts than the threshold in one org unit is suppressed in every org unit",
         %{scope: scope, program: program, x: x} do
      item_stat!(x, @september, 20, 16, org_unit: "Unit A")
      item_stat!(x, @september, 3, 2, org_unit: "Unit B")

      # The item report gives the 23 attempts of X, so a shown cell of
      # Unit A with 20 attempts would give the 3 attempts of Unit B.
      assert competence_cells(scope, program) == %{}

      assert item_cells(scope, program) == %{
               "x" => [%{count: 20 + 3, value: Float.round((16 + 2) / (20 + 3), 4)}]
             }
    end

    test "suppressed cells reveal no count through their bounds",
         %{scope: scope, program: program, x: x} do
      item_stat!(x, @september, 6, 5, org_unit: "Unit V")
      item_stat!(x, @september, 4, 4, org_unit: "Unit U")
      item_stat!(x, @september, 4, 4, org_unit: "Unit W")

      # If only the two small cells were suppressed, the item total of 14
      # minus the 6 attempts of Unit V would leave 8 attempts for two cells
      # of at most 4 each, and 8 correct answers for them: both would follow.
      assert competence_cells(scope, program) == %{}

      assert item_cells(scope, program) == %{
               "x" => [%{count: 14, value: Float.round(13 / 14, 4)}]
             }
    end

    test "an item is suppressed also when its small org units reach the threshold together",
         %{scope: scope, program: program, x: x} do
      item_stat!(x, @september, 20, 10, org_unit: "Unit A")
      item_stat!(x, @september, 2, 1, org_unit: "Unit B")
      item_stat!(x, @september, 3, 1, org_unit: "Unit C")

      assert competence_cells(scope, program) == %{}
    end

    test "a suppressed item hides every cell of its area and depth in that month, in every org unit",
         %{scope: scope, program: program, module: module, objective: objective, x: x} do
      y = insert_item(module, "y")
      link(y, [objective])

      item_stat!(x, @september, 20, 10, org_unit: "Unit A")
      item_stat!(x, @september, 20, 20, org_unit: "Unit B")
      item_stat!(y, @september, 2, 2, org_unit: "Unit B")

      # Unit A holds X alone with 20 attempts. If only the cells that hold Y
      # were suppressed, Unit A would be shown and Unit B hidden, and the
      # hidden cell would tell that Y reached Unit B.
      assert competence_cells(scope, program) == %{}

      assert item_cells(scope, program) == %{
               "x" => [%{count: 40, value: 0.75}],
               "y" => [%{suppressed: true}]
             }
    end

    test "the suppressed cells do not show which org units a suppressed item reached",
         %{scope: scope, program: program, module: module, objective: objective} do
      method = insert_objective(module, "m1-method-apply", :method, :apply)
      i = insert_item(module, "i")
      j = insert_item(module, "j")
      link(i, [objective])
      link(j, [objective, method])

      for unit <- ["Unit 1", "Unit 2", "Unit 3", "Unit 4"] do
        item_stat!(i, @september, 1, 0, org_unit: unit)
        item_stat!(j, @september, 6, 4, org_unit: unit)
      end

      assert {:ok, %{months: [@september], rows: rows}} =
               Insights.competence_report(scope, program.slug)

      # The method/apply cells show J in every org unit. If a subject/know
      # cell, which holds the 6 attempts of J as well, were hidden only where
      # I has attempts, every hidden cell would give I at least one attempt
      # there, and the item report, which suppresses the 4 attempts of I,
      # would leave exactly one per org unit.
      assert Map.new(rows, &{{&1.area, &1.org_unit}, &1.cells}) ==
               Map.new(
                 ["Unit 1", "Unit 2", "Unit 3", "Unit 4"],
                 &{{:subject, &1}, [%{suppressed: true}]}
               )
               |> Map.merge(
                 Map.new(
                   ["Unit 1", "Unit 2", "Unit 3", "Unit 4"],
                   &{{:method, &1}, [%{count: 6, value: Float.round(4 / 6, 4)}]}
                 )
               )

      assert item_cells(scope, program) == %{
               "i" => [%{suppressed: true}],
               "j" => [%{count: 24, value: Float.round(16 / 24, 4)}]
             }
    end

    test "an item whose suppressed org unit would follow from its shown cell and its item total is suppressed in every cell",
         %{scope: scope, program: program, module: module, objective: objective, x: x} do
      j = insert_item(module, "j")
      k = insert_item(module, "k")
      link(j, [objective])
      link(k, [objective])

      item_stat!(x, @september, 3, 1, org_unit: "Unit U")
      item_stat!(x, @september, 7, 6, org_unit: "Unit V")
      item_stat!(j, @september, 6, 3, org_unit: "Unit W")
      item_stat!(k, @september, 2, 1, org_unit: "Unit W")

      # A shown cell of Unit V, which holds X alone, and the 10 attempts of
      # X in the item report would give the 3 attempts of X in Unit U.
      assert competence_cells(scope, program) == %{}

      assert item_cells(scope, program) == %{
               "x" => [%{count: 10, value: 0.7}],
               "j" => [%{count: 6, value: 0.5}],
               "k" => [%{suppressed: true}]
             }
    end

    test "an item linked to two areas is suppressed in both, and an item without a small org unit stays shown",
         %{scope: scope, program: program, module: module, objective: objective, x: x} do
      method = insert_objective(module, "m1-method-apply", :method, :apply)
      link(x, [method])
      y = insert_item(module, "y")
      link(y, [objective])

      for unit <- ["Unit A", "Unit B", "Unit C"],
          do: item_stat!(x, @september, 20, 10, org_unit: unit)

      item_stat!(y, @september, 20, 15, org_unit: "Unit A")
      item_stat!(y, @september, 2, 0, org_unit: "Unit B")
      item_stat!(y, @september, 1, 0, org_unit: "Unit C")

      assert {:ok, %{months: [@september], rows: rows}} =
               Insights.competence_report(scope, program.slug)

      # Every subject/know cell holds Y, which has fewer attempts than the
      # threshold in Unit B and Unit C. The method/apply cells hold X alone,
      # which has 20 attempts in every org unit.
      assert Map.new(rows, &{{&1.area, &1.org_unit}, &1.cells}) == %{
               {:subject, "Unit A"} => [%{suppressed: true}],
               {:subject, "Unit B"} => [%{suppressed: true}],
               {:subject, "Unit C"} => [%{suppressed: true}],
               {:method, "Unit A"} => [%{count: 20, value: 0.5}],
               {:method, "Unit B"} => [%{count: 20, value: 0.5}],
               {:method, "Unit C"} => [%{count: 20, value: 0.5}]
             }

      assert item_cells(scope, program) == %{
               "x" => [%{count: 60, value: 0.5}],
               "y" => [%{count: 23, value: Float.round(15 / 23, 4)}]
             }
    end

    test "an org unit whose cells are all suppressed has no row, so the rows show no suppressed item's org units",
         %{scope: scope, program: program, module: module, x: x} do
      method = insert_objective(module, "m1-method-apply", :method, :apply)
      z = insert_item(module, "z")
      link(z, [method])

      item_stat!(x, @september, 20, 10, org_unit: "Unit A")
      item_stat!(z, @september, 1, 1, org_unit: "Unit B")
      item_stat!(z, @september, 1, 0, org_unit: "Unit C")

      assert {:ok, %{months: [@september], rows: rows}} =
               Insights.competence_report(scope, program.slug)

      # Listed for their suppressed cells, Unit B and Unit C would each show
      # at least one attempt of Z, and the item report, which suppresses the
      # 2 attempts of Z, would leave exactly one in each.
      assert Enum.map(rows, &{&1.area, &1.org_unit, &1.cells}) == [
               {:subject, "Unit A", [%{count: 20, value: 0.5}]},
               {:method, "Unit A", [%{suppressed: true}]}
             ]
    end

    test "every area and depth has a row for every org unit with a shown cell",
         %{scope: scope, program: program, module: module, x: x} do
      method = insert_objective(module, "m1-method-apply", :method, :apply)
      z = insert_item(module, "z")
      link(z, [method])

      item_stat!(x, @september, 20, 10, org_unit: "Unit A")
      item_stat!(x, @september, 20, 10, org_unit: "Unit B")
      item_stat!(z, @september, 20, 10, org_unit: "Unit C")

      assert {:ok, %{months: [@september], rows: rows}} =
               Insights.competence_report(scope, program.slug)

      # An org unit without attempts in an area and depth has a row whose
      # cell is suppressed, so the rows do not show which org units an item
      # reached.
      assert Enum.map(rows, &{&1.area, &1.org_unit, &1.cells}) == [
               {:subject, "Unit A", [%{count: 20, value: 0.5}]},
               {:subject, "Unit B", [%{count: 20, value: 0.5}]},
               {:subject, "Unit C", [%{suppressed: true}]},
               {:method, "Unit A", [%{suppressed: true}]},
               {:method, "Unit B", [%{suppressed: true}]},
               {:method, "Unit C", [%{count: 20, value: 0.5}]}
             ]
    end

    test "with every contribution at or above the threshold, every cell of the column is shown and equals the sums",
         %{scope: scope, program: program, module: module, objective: objective, x: x} do
      y = insert_item(module, "y")
      link(y, [objective])

      item_stat!(x, @september, 5, 5, org_unit: "Unit A")
      item_stat!(y, @september, 7, 1, org_unit: "Unit A")
      item_stat!(x, @september, 10, 5, org_unit: "Unit B")
      item_stat!(y, @september, 5, 4, org_unit: "Unit B")
      item_stat!(x, @september, 5, 2)
      item_stat!(y, @september, 5, 2)

      assert {:ok, report} = Insights.competence_report(scope, program.slug)

      assert report == %{
               by_org_unit: true,
               locale: "en",
               min_group_size: 5,
               months: [@september],
               rows: [
                 %{
                   area: :subject,
                   depth: :know,
                   org_unit: "Unit A",
                   cells: [%{count: 5 + 7, value: (5 + 1) / (5 + 7)}]
                 },
                 %{
                   area: :subject,
                   depth: :know,
                   org_unit: "Unit B",
                   cells: [%{count: 10 + 5, value: (5 + 4) / (10 + 5)}]
                 },
                 %{
                   area: :subject,
                   depth: :know,
                   org_unit: nil,
                   cells: [%{count: 5 + 5, value: (2 + 2) / (5 + 5)}]
                 }
               ]
             }

      # The shown cells add up to the totals of the item report, and no
      # cell is left to compute.
      assert item_cells(scope, program) == %{
               "x" => [%{count: 5 + 10 + 5, value: (5 + 5 + 2) / (5 + 10 + 5)}],
               "y" => [%{count: 7 + 5 + 5, value: Float.round((1 + 4 + 2) / (7 + 5 + 5), 4)}]
             }
    end
  end

  describe "area and depth from learning_objectives" do
    test "after the depth of an objective changes from know to apply, its items count in the apply row only",
         %{scope: scope, program: program, module: module} do
      changed = insert_objective(module, "m1-subject-changed", :subject, :know)
      kept = insert_objective(module, "m1-subject-kept", :subject, :know)
      first = insert_item(module, "first")
      second = insert_item(module, "second")
      other = insert_item(module, "other")
      link(first, [changed])
      link(second, [changed])
      link(other, [kept])

      item_stat!(first, @august, 4, 4)
      item_stat!(first, @september, 6, 3)
      item_stat!(second, @september, 4, 1)
      item_stat!(other, @september, 2, 2)

      assert {:ok, %{months: [@august, @september], rows: before}} =
               Insights.competence_report(scope, program.slug)

      assert before == [
               %{
                 area: :subject,
                 depth: :know,
                 org_unit: nil,
                 cells: [%{count: 4, value: 1.0}, %{count: 12, value: 0.5}]
               }
             ]

      # Only the objective changes; the items and their statistics stay as
      # they are, because an item has no area and no depth of its own.
      changed |> Ecto.Changeset.change(depth: :apply) |> Repo.update!()

      assert {:ok, report} = Insights.competence_report(scope, program.slug)

      assert report == %{
               by_org_unit: false,
               locale: "en",
               min_group_size: 1,
               months: [@august, @september],
               rows: [
                 %{
                   area: :subject,
                   depth: :know,
                   org_unit: nil,
                   cells: [%{suppressed: true}, %{count: 2, value: 1.0}]
                 },
                 %{
                   area: :subject,
                   depth: :apply,
                   org_unit: nil,
                   cells: [%{count: 4, value: 1.0}, %{count: 10, value: 0.4}]
                 }
               ]
             }
    end
  end

  # The cells of the item report by item key, for the month of September.
  defp item_cells(scope, program) do
    assert {:ok, %{months: [@september], rows: rows}} = Insights.item_report(scope, program.slug)
    Map.new(rows, &{&1.key, &1.cells})
  end

  # The cells of the competence report by org unit, for a report whose rows
  # all belong to the subject/know column of September. Without a shown cell,
  # the breakdown lists no org unit and the map is empty.
  defp competence_cells(scope, program) do
    assert {:ok, %{by_org_unit: true, months: [@september], rows: rows}} =
             Insights.competence_report(scope, program.slug)

    assert Enum.all?(rows, &(&1.area == :subject and &1.depth == :know))
    Map.new(rows, &{&1.org_unit, &1.cells})
  end

  # The scope of a session of a user with the role analyst, as the request
  # pipeline builds it from the role grants.
  defp analyst_scope do
    analyst = user_with_role_fixture(:analyst)
    {_token, session} = session_fixture(analyst)
    Scope.for_session(analyst, session, Accounts.list_role_grants(analyst))
  end

  defp insert_program do
    Repo.insert!(%Program{
      slug: "competence-#{System.unique_integer([:positive])}",
      title: "Competence report",
      locale: "en",
      status: :published,
      pack_version: "1.0.0"
    })
  end

  defp insert_module(program, number, archived_at \\ nil) do
    Repo.insert!(%CatalogModule{
      program_id: program.id,
      number: number,
      title: "Module #{number}",
      summary: "Summary",
      areas_elsewhere: %{},
      archived_at: archived_at
    })
  end

  defp insert_objective(module, key, area, depth, archived_at \\ nil) do
    Repo.insert!(%LearningObjective{
      program_id: module.program_id,
      module_id: module.id,
      key: key,
      statement: "Learners can do what #{key} names.",
      area: area,
      depth: depth,
      phase: :understand,
      position: 1,
      archived_at: archived_at
    })
  end

  defp insert_item(module, key, kind \\ :single_choice, archived_at \\ nil) do
    Repo.insert!(%Item{
      program_id: module.program_id,
      module_id: module.id,
      key: key,
      kind: kind,
      stem: "Stem of #{key}",
      core: false,
      phase: :apply,
      provenance: :invented,
      position: 1,
      archived_at: archived_at
    })
  end

  defp link(item, objectives) do
    Repo.insert_all(
      "item_objectives",
      for(
        objective <- objectives,
        do: %{item_id: UUID.dump!(item.id), learning_objective_id: UUID.dump!(objective.id)}
      )
    )
  end
end
