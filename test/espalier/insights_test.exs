defmodule Espalier.InsightsTest do
  @moduledoc """
  The Insights context of task 0014 (spec steps 3, 8 and 13; README
  sections 7 and 10; ASVS 8.2.1): `record_once/3` with a new and an
  existing marker and the rollback of the marker on an error;
  `record_self_assessment/3`, `vote_format/3` and `record_feedback/3`
  with their validation; `participation/2`; the suppression function
  `cell/2` below, at and above the threshold; the role check of every
  report function; the threshold and the locale of the program that every
  report carries; and the shapes and orders of the self-assessment, item,
  format, feedback and credential reports. Once any answer exists, the
  self-assessment report lists every live segment, so that a missing row
  tells nothing, and an archived segment, a key without a segment and an
  archived qualification appear only with a shown cell. The credential
  report follows the order of `qualifications.yaml`, or the `position` of
  its entries, and lists the archived qualifications after the live ones
  (issue #39). The competence report has its own tests in
  `test/espalier/insights/competence_report_test.exs`.

  A test that compares a stored date with the current date takes the date
  before the insert and accepts the following day as well, so that it
  passes across UTC midnight.

  `put_insights/1` and `put_learning/1` change global settings, so the
  module runs synchronously. Every test starts with the threshold 1, so
  that a cell with the count 0 is the only suppressed one unless a test
  raises the threshold.
  """
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures
  import Espalier.InsightsFixtures
  import Espalier.LearningFixtures

  import Espalier.CredentialsFixtures,
    only: [credential_fixture: 3, qualification!: 2, user_with_role_fixture: 1]

  alias Espalier.Accounts.Scope
  alias Espalier.{Catalog, Insights, Learning, PackFixtures}
  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.{PackImport, Qualification, Segment, Station}

  alias Espalier.Insights.{
    FeedbackResponse,
    InterestVote,
    ParticipationMarker,
    SelfAssessmentResponse
  }

  alias Espalier.Learning.Enrollment

  @reports [
    :self_assessment_report,
    :item_report,
    :competence_report,
    :format_report,
    :feedback_report,
    :credential_report
  ]

  @invalid_answers {:error, {:validation_failed, "answers", "invalid"}}
  @invalid_segment {:error, {:validation_failed, "segment_key", "invalid"}}

  setup do
    put_insights(min_group_size: 1, feedback_free_text: false)
    put_learning(insights_org_unit: false)
    :ok
  end

  # A scope that holds the role analyst, as the request pipeline builds it
  # from a grant.
  defp analyst_scope do
    user = user_with_role_fixture(:analyst)
    %Scope{Scope.for_user(user) | roles: [:learner, :analyst]}
  end

  defp archive!(struct),
    do: struct |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update!()

  defp unpublish!(program),
    do: program |> Ecto.Changeset.change(status: :archived) |> Repo.update!()

  defp segment!(program, key), do: Repo.get_by!(Segment, program_id: program.id, key: key)

  defp label!(program, key), do: segment!(program, key).label

  defp markers, do: Repo.all(ParticipationMarker)

  # A date that the code under test recorded as the current UTC date:
  # `before` is the date the test took before the call, and the following
  # day is accepted for a call that ran after UTC midnight.
  defp assert_recorded_today(date, before), do: assert(date in [before, Date.add(before, 1)])

  defp user_with_org_unit(org_unit),
    do: user_fixture() |> Ecto.Changeset.change(org_unit: org_unit) |> Repo.update!()

  # Publishes the fixture pack `minimal` as a second program next to the
  # demo program.
  defp publish_minimal! do
    {:ok, %PackImport{status: :validated} = pack_import} =
      Importer.import(PackFixtures.fixture_path("minimal"), nil)

    {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    Catalog.get_program_by_slug("minimal-pack")
  end

  # The cells of a row as `{count, value}` pairs, `:suppressed` for a
  # suppressed cell.
  defp cells(%{cells: cells}), do: Enum.map(cells, &plain_cell/1)

  defp plain_cell(%{suppressed: true} = cell) when map_size(cell) == 1, do: :suppressed

  defp plain_cell(%{count: count, value: value} = cell) when map_size(cell) == 2,
    do: {count, value}

  describe "record_once/3" do
    setup do
      %{scope: scope_for(user_fixture()), subject: {:format_vote, Ecto.UUID.generate()}}
    end

    test "with a new marker, runs fun once and returns its result",
         %{scope: scope, subject: {type, id} = subject} do
      test_pid = self()

      assert {:ok, :inserted} =
               Insights.record_once(scope, subject, fn ->
                 send(test_pid, :ran)
                 {:ok, :inserted}
               end)

      assert_received :ran
      refute_received :ran

      assert [%ParticipationMarker{subject_type: ^type, subject_id: ^id} = marker] = markers()
      assert marker.user_id == scope.user.id
    end

    test "with an existing marker, returns already_recorded and does not call fun",
         %{scope: scope, subject: subject} do
      test_pid = self()
      assert {:ok, :first} = Insights.record_once(scope, subject, fn -> {:ok, :first} end)

      assert {:ok, :already_recorded} =
               Insights.record_once(scope, subject, fn ->
                 send(test_pid, :ran)
                 {:ok, :second}
               end)

      refute_received :ran
      assert [_one] = markers()
    end

    test "an error from fun rolls the marker back, so a later call runs fun again",
         %{scope: scope, subject: subject} do
      test_pid = self()

      assert {:error, :boom} = Insights.record_once(scope, subject, fn -> {:error, :boom} end)
      assert markers() == []

      assert {:ok, :second} =
               Insights.record_once(scope, subject, fn ->
                 send(test_pid, :ran)
                 {:ok, :second}
               end)

      assert_received :ran
      assert [_one] = markers()
    end

    test "an error from fun also rolls back the rows that fun inserted", %{scope: scope} do
      program = publish_demo!()

      assert {:error, :boom} =
               Insights.record_once(scope, {:self_assessment, program.id}, fn ->
                 self_assessment_rows!(program, "daily-users", 1)
                 {:error, :boom}
               end)

      assert markers() == []
      assert Repo.aggregate(SelfAssessmentResponse, :count) == 0
    end

    test "a marker belongs to one user, subject type and subject id",
         %{scope: scope, subject: {_type, id} = subject} do
      other = scope_for(user_fixture())

      for {scope, subject} <- [
            {scope, subject},
            {other, subject},
            {scope, {:feedback, id}},
            {scope, {:format_vote, Ecto.UUID.generate()}}
          ] do
        assert {:ok, :new} = Insights.record_once(scope, subject, fn -> {:ok, :new} end)
      end

      assert length(markers()) == 4
    end
  end

  describe "cell/2" do
    test "suppresses a count below the threshold and shows one at and above it" do
      put_insights(min_group_size: 5)

      assert Insights.cell(0, 0) == %{suppressed: true}
      assert Insights.cell(4, 4) == %{suppressed: true}
      assert Insights.cell(4, 0.75) == %{suppressed: true}
      assert Insights.cell(5, 5) == %{count: 5, value: 5}
      assert Insights.cell(5, 0.6) == %{count: 5, value: 0.6}
      assert Insights.cell(6, 6) == %{count: 6, value: 6}
    end

    test "with min_group_size 1, suppresses the count 0 and shows the count 1" do
      put_insights(min_group_size: 1)

      assert Insights.cell(0, 0) == %{suppressed: true}
      assert Insights.cell(0, 0.0) == %{suppressed: true}
      assert Insights.cell(1, 1) == %{count: 1, value: 1}
    end
  end

  describe "the role check of the reports" do
    setup do
      %{program: publish_demo!()}
    end

    test "every report answers forbidden for a learner scope, also for an unknown slug" do
      learner = scope_for(user_fixture())

      for report <- @reports, slug <- [demo_slug(), "unknown-program"] do
        assert apply(Insights, report, [learner, slug]) == {:error, :forbidden},
               "#{report} #{slug}"
      end
    end

    test "every report answers forbidden for a scope whose roles do not include analyst" do
      staff = %Scope{
        Scope.for_user(user_fixture())
        | roles: [:learner, :author, :admin, :facilitator, :registrar]
      }

      for report <- @reports, scope <- [staff, Scope.system()] do
        assert apply(Insights, report, [scope, demo_slug()]) == {:error, :forbidden},
               "#{report} #{inspect(scope.roles)}"
      end
    end

    test "every report answers not_found for an analyst and an unknown slug" do
      analyst = analyst_scope()

      for report <- @reports do
        assert apply(Insights, report, [analyst, "unknown-program"]) == {:error, :not_found},
               "#{report}"
      end
    end

    test "every report reads a program in any status, names the threshold and the locale and holds no total",
         %{program: program} do
      put_insights(min_group_size: 3)
      unpublish!(program)
      analyst = analyst_scope()
      locale = program.locale

      keys = %{
        self_assessment_report: [:by_org_unit, :locale, :min_group_size, :months, :rows],
        item_report: [:locale, :min_group_size, :months, :rows],
        competence_report: [:by_org_unit, :locale, :min_group_size, :months, :rows],
        format_report: [:formats, :locale, :min_group_size],
        feedback_report: [:locale, :min_group_size, :questions],
        credential_report: [:locale, :min_group_size, :qualifications]
      }

      for report <- @reports do
        assert {:ok, %{min_group_size: 3, locale: ^locale} = result} =
                 apply(Insights, report, [analyst, demo_slug()])

        assert result |> Map.keys() |> Enum.sort() == keys[report], "#{report}"
      end
    end

    test "every report carries the locale of its program", %{program: program} do
      program |> Ecto.Changeset.change(locale: "de") |> Repo.update!()
      other = publish_minimal!()
      analyst = analyst_scope()

      for report <- @reports do
        assert {:ok, %{locale: "de"}} = apply(Insights, report, [analyst, demo_slug()]),
               "#{report}"

        assert {:ok, %{locale: "en"}} = apply(Insights, report, [analyst, other.slug]),
               "#{report}"
      end
    end

    test "the reports read only the rows of their program" do
      other = publish_minimal!()
      analyst = analyst_scope()

      self_assessment_rows!(other, "daily-users", 2)
      vote_rows!(format!(other, "workshop"), 2)
      feedback_row!(other, %{"usefulness" => "very-useful", "clarity" => 3, "suggestion" => "x"})
      item_stat!(item!(other, "m1-choice"), Date.utc_today(), 4, 2)
      credential_fixture(user_fixture(), qualification!(other, "basics"), %{status: :active})

      assert {:ok, %{months: [], rows: []}} =
               Insights.self_assessment_report(analyst, demo_slug())

      assert {:ok, %{months: [], rows: []}} = Insights.item_report(analyst, demo_slug())

      # The demo program has a subject/know objective as well, so only the
      # program filter keeps these statistics out of its report, while the
      # other program shows them.
      assert {:ok, %{months: [], rows: []}} = Insights.competence_report(analyst, demo_slug())

      assert {:ok, %{rows: [%{area: :subject, depth: :know, org_unit: nil} = row]}} =
               Insights.competence_report(analyst, other.slug)

      assert cells(row) == [{4, 0.5}]

      assert {:ok, %{formats: formats}} = Insights.format_report(analyst, demo_slug())
      assert Enum.map(formats, & &1.cell) == List.duplicate(%{suppressed: true}, 3)

      assert {:ok, %{questions: questions}} = Insights.feedback_report(analyst, demo_slug())

      for question <- questions do
        assert Enum.all?(question.choices, &(&1.cell == %{suppressed: true})), question.key
        assert question.free_text in [nil, %{suppressed: true}], question.key
      end

      assert {:ok, %{qualifications: qualifications}} =
               Insights.credential_report(analyst, demo_slug())

      assert Enum.map(qualifications, & &1.code) == ["basics", "workshop"]

      for qualification <- qualifications, entry <- qualification.statuses do
        assert entry.cell == %{suppressed: true}
      end
    end
  end

  describe "self_assessment_report/2" do
    setup do
      %{program: publish_demo!(), analyst: analyst_scope()}
    end

    test "lists the months in ascending order and every live segment in segment order with its label",
         %{program: program, analyst: analyst} do
      self_assessment_rows!(program, "stopped-users", 2, recorded_on: ~D[2026-09-20])
      self_assessment_rows!(program, "daily-users", 3, recorded_on: ~D[2026-09-02])
      self_assessment_rows!(program, "daily-users", 1, recorded_on: ~D[2026-08-31])
      self_assessment_rows!(program, "non-users", 1, recorded_on: ~D[2026-08-01])

      assert {:ok, report} = Insights.self_assessment_report(analyst, demo_slug())

      assert report.by_org_unit == false
      assert report.months == [~D[2026-08-01], ~D[2026-09-01]]

      assert Enum.map(report.rows, &{&1.segment_key, &1.label, &1.org_unit, cells(&1)}) == [
               {"daily-users", label!(program, "daily-users"), nil, [{1, 1}, {3, 3}]},
               {"occasional-users", label!(program, "occasional-users"), nil,
                [:suppressed, :suppressed]},
               {"non-users", label!(program, "non-users"), nil, [{1, 1}, :suppressed]},
               {"stopped-users", label!(program, "stopped-users"), nil, [:suppressed, {2, 2}]}
             ]
    end

    test "without any answer, has no months and no rows, also by org unit",
         %{program: program, analyst: analyst} do
      program |> segment!("daily-users") |> archive!()

      for org_unit_setting <- [false, true] do
        put_learning(insights_org_unit: org_unit_setting)

        assert {:ok, %{by_org_unit: ^org_unit_setting, months: [], rows: []}} =
                 Insights.self_assessment_report(analyst, demo_slug())
      end
    end

    test "answers in one segment list every live segment, the others with suppressed cells",
         %{program: program, analyst: analyst} do
      self_assessment_rows!(program, "non-users", 2, recorded_on: ~D[2026-09-15])

      assert {:ok, report} = Insights.self_assessment_report(analyst, demo_slug())

      assert report.months == [~D[2026-09-01]]

      assert Enum.map(report.rows, &{&1.segment_key, &1.label, &1.org_unit, cells(&1)}) == [
               {"daily-users", label!(program, "daily-users"), nil, [:suppressed]},
               {"occasional-users", label!(program, "occasional-users"), nil, [:suppressed]},
               {"non-users", label!(program, "non-users"), nil, [{2, 2}]},
               {"stopped-users", label!(program, "stopped-users"), nil, [:suppressed]}
             ]
    end

    test "four answers of one segment and org unit give the same report as none, once other answers create the month and the org unit",
         %{program: program, analyst: analyst} do
      put_insights(min_group_size: 5)
      on = [recorded_on: ~D[2026-09-15], org_unit: "Audit"]
      self_assessment_rows!(program, "daily-users", 5, on)

      # The report with the setting false and with the setting true.
      reports = fn ->
        for org_unit_setting <- [false, true] do
          put_learning(insights_org_unit: org_unit_setting)
          assert {:ok, report} = Insights.self_assessment_report(analyst, demo_slug())
          report
        end
      end

      assert [summed, by_org_unit] = without = reports.()

      self_assessment_rows!(program, "non-users", 4, on)

      assert reports.() == without

      assert Enum.map(summed.rows, &{&1.segment_key, &1.org_unit, cells(&1)}) == [
               {"daily-users", nil, [{5, 5}]},
               {"occasional-users", nil, [:suppressed]},
               {"non-users", nil, [:suppressed]},
               {"stopped-users", nil, [:suppressed]}
             ]

      assert Enum.map(by_org_unit.rows, &{&1.segment_key, &1.org_unit, cells(&1)}) == [
               {"daily-users", "Audit", [{5, 5}]},
               {"occasional-users", "Audit", [:suppressed]},
               {"non-users", "Audit", [:suppressed]},
               {"stopped-users", "Audit", [:suppressed]}
             ]
    end

    test "an archived segment with a shown cell follows the live ones, and a key without a segment comes last with label nil",
         %{program: program, analyst: analyst} do
      self_assessment_rows!(program, "a-retired-key", 1)
      self_assessment_rows!(program, "daily-users", 1)
      self_assessment_rows!(program, "occasional-users", 1)
      daily = program |> segment!("daily-users") |> archive!()

      assert {:ok, report} = Insights.self_assessment_report(analyst, demo_slug())

      assert Enum.map(report.rows, &{&1.segment_key, &1.label}) == [
               {"occasional-users", label!(program, "occasional-users")},
               {"non-users", label!(program, "non-users")},
               {"stopped-users", label!(program, "stopped-users")},
               {"daily-users", daily.label},
               {"a-retired-key", nil}
             ]
    end

    test "an archived segment and a key without a segment have no row while their cells are suppressed and a row once one is shown",
         %{program: program, analyst: analyst} do
      put_insights(min_group_size: 3)
      daily = program |> segment!("daily-users") |> archive!()
      self_assessment_rows!(program, "non-users", 3, recorded_on: ~D[2026-08-10])
      self_assessment_rows!(program, "daily-users", 2, recorded_on: ~D[2026-09-10])
      self_assessment_rows!(program, "a-retired-key", 2, recorded_on: ~D[2026-09-10])

      assert {:ok, report} = Insights.self_assessment_report(analyst, demo_slug())

      assert report.months == [~D[2026-08-01], ~D[2026-09-01]]

      assert Enum.map(report.rows, &{&1.segment_key, cells(&1)}) == [
               {"occasional-users", [:suppressed, :suppressed]},
               {"non-users", [{3, 3}, :suppressed]},
               {"stopped-users", [:suppressed, :suppressed]}
             ]

      self_assessment_rows!(program, "daily-users", 1, recorded_on: ~D[2026-09-30])
      self_assessment_rows!(program, "a-retired-key", 1, recorded_on: ~D[2026-09-01])

      assert {:ok, report} = Insights.self_assessment_report(analyst, demo_slug())

      assert Enum.map(report.rows, &{&1.segment_key, &1.label, cells(&1)}) == [
               {"occasional-users", label!(program, "occasional-users"),
                [:suppressed, :suppressed]},
               {"non-users", label!(program, "non-users"), [{3, 3}, :suppressed]},
               {"stopped-users", label!(program, "stopped-users"), [:suppressed, :suppressed]},
               {"daily-users", daily.label, [:suppressed, {3, 3}]},
               {"a-retired-key", nil, [:suppressed, {3, 3}]}
             ]
    end

    test "with insights_org_unit true, an archived segment has a row only in the org units with a shown cell",
         %{program: program, analyst: analyst} do
      put_insights(min_group_size: 2)
      put_learning(insights_org_unit: true)
      program |> segment!("daily-users") |> archive!()
      on = [recorded_on: ~D[2026-09-10]]
      self_assessment_rows!(program, "daily-users", 2, [org_unit: "Audit"] ++ on)
      self_assessment_rows!(program, "daily-users", 1, [org_unit: "Finance"] ++ on)

      assert {:ok, report} = Insights.self_assessment_report(analyst, demo_slug())

      assert Enum.map(report.rows, &{&1.segment_key, &1.org_unit, cells(&1)}) == [
               {"occasional-users", "Audit", [:suppressed]},
               {"occasional-users", "Finance", [:suppressed]},
               {"non-users", "Audit", [:suppressed]},
               {"non-users", "Finance", [:suppressed]},
               {"stopped-users", "Audit", [:suppressed]},
               {"stopped-users", "Finance", [:suppressed]},
               {"daily-users", "Audit", [{2, 2}]}
             ]
    end

    test "with insights_org_unit true, gives one row per live segment and org unit, nil last",
         %{program: program, analyst: analyst} do
      put_learning(insights_org_unit: true)
      org_unit_rows!(program)

      assert {:ok, report} = Insights.self_assessment_report(analyst, demo_slug())

      assert report.by_org_unit
      assert report.months == [~D[2026-09-01]]

      assert Enum.map(report.rows, &{&1.segment_key, &1.org_unit, cells(&1)}) == [
               {"daily-users", "Audit", [{3, 3}]},
               {"daily-users", "Finance", [{2, 2}]},
               {"daily-users", nil, [{1, 1}]},
               {"occasional-users", "Audit", [:suppressed]},
               {"occasional-users", "Finance", [:suppressed]},
               {"occasional-users", nil, [:suppressed]},
               {"non-users", "Audit", [{1, 1}]},
               {"non-users", "Finance", [:suppressed]},
               {"non-users", nil, [:suppressed]},
               {"stopped-users", "Audit", [:suppressed]},
               {"stopped-users", "Finance", [:suppressed]},
               {"stopped-users", nil, [:suppressed]}
             ]
    end

    test "with insights_org_unit false, the rows of several org units sum into one row",
         %{program: program, analyst: analyst} do
      org_unit_rows!(program)

      assert {:ok, report} = Insights.self_assessment_report(analyst, demo_slug())

      assert report.by_org_unit == false

      assert Enum.map(report.rows, &{&1.segment_key, &1.org_unit, cells(&1)}) == [
               {"daily-users", nil, [{6, 6}]},
               {"occasional-users", nil, [:suppressed]},
               {"non-users", nil, [{1, 1}]},
               {"stopped-users", nil, [:suppressed]}
             ]
    end

    test "suppresses a cell below the threshold", %{program: program, analyst: analyst} do
      put_insights(min_group_size: 3)
      self_assessment_rows!(program, "daily-users", 2)
      self_assessment_rows!(program, "non-users", 3)

      assert {:ok, %{min_group_size: 3, rows: rows}} =
               Insights.self_assessment_report(analyst, demo_slug())

      assert Enum.map(rows, &{&1.segment_key, cells(&1)}) == [
               {"daily-users", [:suppressed]},
               {"occasional-users", [:suppressed]},
               {"non-users", [{3, 3}]},
               {"stopped-users", [:suppressed]}
             ]
    end
  end

  # Self-assessment rows of September 2026 in three org units, one of them
  # nil, in an order that differs from the order of the report.
  defp org_unit_rows!(program) do
    on = [recorded_on: ~D[2026-09-15]]
    self_assessment_rows!(program, "non-users", 1, [org_unit: "Audit"] ++ on)
    self_assessment_rows!(program, "daily-users", 2, [org_unit: "Finance"] ++ on)
    self_assessment_rows!(program, "daily-users", 1, on)
    self_assessment_rows!(program, "daily-users", 3, [org_unit: "Audit"] ++ on)
  end

  describe "item_report/2" do
    setup do
      %{program: publish_demo!(), analyst: analyst_scope()}
    end

    test "sums attempts and correct answers over the org units per item and month",
         %{program: program, analyst: analyst} do
      item = item!(program, "m1-before-use")
      item_stat!(item, ~D[2026-09-10], 3, 1, org_unit: "Audit")
      item_stat!(item, ~D[2026-09-10], 4, 3, org_unit: "Finance")
      item_stat!(item, ~D[2026-09-10], 2, 2)
      item_stat!(item, ~D[2026-07-01], 3, 0)

      for org_unit_setting <- [false, true] do
        put_learning(insights_org_unit: org_unit_setting)

        assert {:ok, report} = Insights.item_report(analyst, demo_slug())

        assert report.months == [~D[2026-07-01], ~D[2026-09-01]]

        assert report.rows == [
                 %{
                   item_id: item.id,
                   key: "m1-before-use",
                   kind: :single_choice,
                   module_number: 1,
                   stem: item.stem,
                   cells: [%{count: 3, value: 0.0}, %{count: 9, value: 0.6667}]
                 }
               ]
      end
    end

    test "leaves out polls, archived items and the items of an archived module",
         %{program: program, analyst: analyst} do
      live = item!(program, "m1-how-models-write")
      poll = item!(program, "m1-first-task-poll")
      archived = item!(program, "m1-fluent-figure")
      module_two = item!(program, "m2-prompt-builder")

      item_stat!(live, ~D[2026-09-01], 5, 2)
      item_stat!(archived, ~D[2026-09-01], 5, 2)
      item_stat!(module_two, ~D[2026-08-01], 5, 2)
      item_stat!(poll, ~D[2026-06-01], 5, 0)

      archive!(archived)
      program |> module!(2) |> archive!()

      assert {:ok, report} = Insights.item_report(analyst, demo_slug())

      assert Enum.map(report.rows, & &1.key) == ["m1-how-models-write"]
      assert report.months == [~D[2026-09-01]]
    end

    test "orders the rows by module number and item position",
         %{program: program, analyst: analyst} do
      keys =
        ~w(m2-release-drill m1-before-use m2-judge-drafts m1-how-models-write m2-prompt-builder m1-why-answers-vary)

      for key <- keys, do: item_stat!(item!(program, key), ~D[2026-09-01], 1, 1)

      assert {:ok, report} = Insights.item_report(analyst, demo_slug())

      assert Enum.map(report.rows, &{&1.module_number, &1.key}) == [
               {1, "m1-how-models-write"},
               {1, "m1-why-answers-vary"},
               {1, "m1-before-use"},
               {2, "m2-prompt-builder"},
               {2, "m2-judge-drafts"},
               {2, "m2-release-drill"}
             ]
    end

    test "suppresses a cell whose attempts lie below the threshold and a month without statistics",
         %{program: program, analyst: analyst} do
      put_insights(min_group_size: 5)
      first = item!(program, "m1-how-models-write")
      second = item!(program, "m1-before-use")
      item_stat!(first, ~D[2026-08-01], 4, 4)
      item_stat!(first, ~D[2026-09-01], 5, 4)
      item_stat!(second, ~D[2026-09-01], 6, 3)

      assert {:ok, report} = Insights.item_report(analyst, demo_slug())

      assert Enum.map(report.rows, &{&1.key, cells(&1)}) == [
               {"m1-how-models-write", [:suppressed, {5, 0.8}]},
               {"m1-before-use", [:suppressed, {6, 0.5}]}
             ]
    end
  end

  describe "format_report/2" do
    setup do
      %{program: publish_demo!(), analyst: analyst_scope()}
    end

    test "counts the votes per live format in format order", %{program: program, analyst: analyst} do
      put_insights(min_group_size: 2)
      handbook = format!(program, "handbook")
      workshop = format!(program, "workshop")
      help_desk = format!(program, "help-desk")
      vote_rows!(workshop, 3)
      vote_rows!(handbook, 1)

      assert {:ok, %{formats: formats}} = Insights.format_report(analyst, demo_slug())

      assert formats == [
               %{
                 id: handbook.id,
                 key: "handbook",
                 title: handbook.title,
                 cell: %{suppressed: true}
               },
               %{
                 id: workshop.id,
                 key: "workshop",
                 title: workshop.title,
                 cell: %{count: 3, value: 3}
               },
               %{
                 id: help_desk.id,
                 key: "help-desk",
                 title: help_desk.title,
                 cell: %{suppressed: true}
               }
             ]
    end

    test "leaves out an archived format", %{program: program, analyst: analyst} do
      program |> format!("help-desk") |> vote_rows!(2)
      program |> format!("help-desk") |> archive!()

      assert {:ok, %{formats: formats}} = Insights.format_report(analyst, demo_slug())
      assert Enum.map(formats, & &1.key) == ["handbook", "workshop"]
    end
  end

  describe "feedback_report/2" do
    setup do
      %{program: publish_demo!(), analyst: analyst_scope()}
    end

    test "counts the choices per option and the scale values from 1 to 5",
         %{program: program, analyst: analyst} do
      feedback_row!(program, %{"usefulness" => "very-useful", "clarity" => 5})
      feedback_row!(program, %{"usefulness" => "very-useful", "clarity" => 4})
      feedback_row!(program, %{"usefulness" => "not-useful"})
      feedback_row!(program, %{"clarity" => 4})

      assert {:ok, %{questions: [usefulness, clarity, suggestion]}} =
               Insights.feedback_report(analyst, demo_slug())

      assert %{key: "usefulness", kind: "single_choice", free_text: nil} = usefulness
      assert usefulness.label == "How useful was this program for your daily work?"

      assert Enum.map(usefulness.choices, &{&1.key, &1.label, &1.cell}) == [
               {"very-useful", "Very useful", %{count: 2, value: 2}},
               {"somewhat-useful", "Somewhat useful", %{suppressed: true}},
               {"not-useful", "Not useful", %{count: 1, value: 1}}
             ]

      assert %{key: "clarity", kind: "scale", free_text: nil} = clarity

      assert Enum.map(clarity.choices, &{&1.key, &1.label, &1.cell}) == [
               {"1", nil, %{suppressed: true}},
               {"2", nil, %{suppressed: true}},
               {"3", nil, %{suppressed: true}},
               {"4", nil, %{count: 2, value: 2}},
               {"5", nil, %{count: 1, value: 1}}
             ]

      assert %{key: "suggestion", kind: "free_text", choices: []} = suggestion
      assert suggestion.free_text == %{suppressed: true}
    end

    test "lists free text only when its count reaches the threshold",
         %{program: program, analyst: analyst} do
      put_insights(min_group_size: 3)
      texts = ["Add more examples.", "Shorter lessons.", "Add more examples."]

      for text <- Enum.take(texts, 2), do: feedback_row!(program, %{"suggestion" => text})
      feedback_row!(program, %{"usefulness" => "very-useful"})

      assert {:ok, %{questions: questions}} = Insights.feedback_report(analyst, demo_slug())
      assert List.last(questions).free_text == %{suppressed: true}

      feedback_row!(program, %{"suggestion" => List.last(texts)})

      assert {:ok, %{questions: questions}} = Insights.feedback_report(analyst, demo_slug())
      assert %{count: 3, answers: answers} = List.last(questions).free_text
      assert Enum.sort(answers) == Enum.sort(texts)
    end

    test "a program without a feedback station has no questions",
         %{program: program, analyst: analyst} do
      feedback_row!(program, %{"usefulness" => "very-useful"})

      Repo.delete_all(
        from s in Station, where: s.program_id == ^program.id and s.kind == :feedback
      )

      assert {:ok, %{questions: []}} = Insights.feedback_report(analyst, demo_slug())
    end
  end

  describe "feedback_report/2 with two free-text questions" do
    setup do
      pack = PackFixtures.copy_pack!(PackFixtures.demo_path())

      PackFixtures.update_yaml!(pack, "feedback.yaml", fn feedback ->
        Map.update!(
          feedback,
          "questions",
          &(&1 ++ [%{"key" => "remark", "kind" => "free_text", "label" => "Anything else?"}])
        )
      end)

      %{program: publish_demo!(pack), analyst: analyst_scope()}
    end

    test "lists the answers of one question apart from those of the others",
         %{program: program, analyst: analyst} do
      put_insights(min_group_size: 3)

      for n <- 1..3, do: feedback_row!(program, %{"suggestion" => "suggestion #{n}"})

      for n <- 1..2 do
        feedback_row!(program, %{"remark" => "remark #{n}", "usefulness" => "very-useful"})
      end

      assert {:ok, %{questions: questions}} = Insights.feedback_report(analyst, demo_slug())
      by_key = Map.new(questions, &{&1.key, &1})

      assert Enum.map(questions, & &1.key) == ~w(usefulness clarity suggestion remark)
      assert %{count: 3, answers: suggestions} = by_key["suggestion"].free_text
      assert Enum.sort(suggestions) == ["suggestion 1", "suggestion 2", "suggestion 3"]
      assert by_key["remark"].free_text == %{suppressed: true}

      feedback_row!(program, %{"remark" => "remark 3"})

      assert {:ok, %{questions: questions}} = Insights.feedback_report(analyst, demo_slug())
      by_key = Map.new(questions, &{&1.key, &1})

      assert %{count: 3, answers: remarks} = by_key["remark"].free_text
      assert Enum.sort(remarks) == ["remark 1", "remark 2", "remark 3"]
      assert %{count: 3, answers: suggestions} = by_key["suggestion"].free_text
      assert Enum.sort(suggestions) == ["suggestion 1", "suggestion 2", "suggestion 3"]
    end
  end

  describe "credential_report/2" do
    setup do
      program = publish_demo!()

      %{
        program: program,
        analyst: analyst_scope(),
        basics: qualification!(program, "basics"),
        workshop: qualification!(program, "workshop")
      }
    end

    test "counts the credentials per qualification and status in the order of the statuses",
         %{analyst: analyst, basics: basics, workshop: workshop} do
      for status <- [:revoked, :active, :expired, :active, :refresh_due] do
        credential_fixture(user_fixture(), basics, %{status: status})
      end

      credential_fixture(user_fixture(), workshop, %{status: :active})

      assert {:ok, %{qualifications: [basics_row, workshop_row]}} =
               Insights.credential_report(analyst, demo_slug())

      assert %{code: "basics", archived: false} = basics_row
      assert basics_row.title == basics.title

      assert Enum.map(basics_row.statuses, &{&1.status, &1.cell}) == [
               {:active, %{count: 2, value: 2}},
               {:refresh_due, %{count: 1, value: 1}},
               {:expired, %{count: 1, value: 1}},
               {:revoked, %{count: 1, value: 1}}
             ]

      assert %{code: "workshop", archived: false} = workshop_row

      assert Enum.map(workshop_row.statuses, &{&1.status, &1.cell}) == [
               {:active, %{count: 1, value: 1}},
               {:refresh_due, %{suppressed: true}},
               {:expired, %{suppressed: true}},
               {:revoked, %{suppressed: true}}
             ]
    end

    test "appends an archived qualification with a shown cell and leaves out one without credentials",
         %{program: program, analyst: analyst} do
      legacy = archived_qualification!(program, "legacy")
      _retired = archived_qualification!(program, "retired")
      credential_fixture(user_fixture(), legacy, %{status: :expired})

      assert {:ok, %{qualifications: qualifications}} =
               Insights.credential_report(analyst, demo_slug())

      assert Enum.map(qualifications, &{&1.code, &1.archived}) == [
               {"basics", false},
               {"workshop", false},
               {"legacy", true}
             ]

      assert Enum.map(List.last(qualifications).statuses, & &1.cell) == [
               %{suppressed: true},
               %{suppressed: true},
               %{count: 1, value: 1},
               %{suppressed: true}
             ]
    end

    test "suppresses the count of four credentials and shows the count of five",
         %{analyst: analyst, basics: basics} do
      put_insights(min_group_size: 5)

      for _ <- 1..4, do: credential_fixture(user_fixture(), basics, %{status: :active})

      assert {:ok, %{qualifications: [basics_row | _]}} =
               Insights.credential_report(analyst, demo_slug())

      assert hd(basics_row.statuses) == %{status: :active, cell: %{suppressed: true}}

      credential_fixture(user_fixture(), basics, %{status: :active})

      assert {:ok, %{qualifications: [basics_row | _]}} =
               Insights.credential_report(analyst, demo_slug())

      assert hd(basics_row.statuses) == %{status: :active, cell: %{count: 5, value: 5}}
    end

    test "leaves out an archived qualification whose counts all lie below the threshold and lists it once one reaches it",
         %{program: program, analyst: analyst} do
      put_insights(min_group_size: 3)
      legacy = archived_qualification!(program, "legacy")

      # Four credentials, but no status reaches the threshold.
      for status <- [:expired, :revoked, :expired, :revoked] do
        credential_fixture(user_fixture(), legacy, %{status: status})
      end

      assert {:ok, %{qualifications: qualifications}} =
               Insights.credential_report(analyst, demo_slug())

      assert Enum.map(qualifications, &{&1.code, &1.archived}) == [
               {"basics", false},
               {"workshop", false}
             ]

      credential_fixture(user_fixture(), legacy, %{status: :expired})

      assert {:ok, %{qualifications: [_basics, _workshop, legacy_row]}} =
               Insights.credential_report(analyst, demo_slug())

      assert %{code: "legacy", archived: true} = legacy_row

      assert Enum.map(legacy_row.statuses, &{&1.status, &1.cell}) == [
               {:active, %{suppressed: true}},
               {:refresh_due, %{suppressed: true}},
               {:expired, %{count: 3, value: 3}},
               {:revoked, %{suppressed: true}}
             ]
    end
  end

  # Inserts an archived qualification `code` of `program`. Its position 1
  # equals the position of the first live qualification of the demo pack, so
  # the report places it after the live ones by its archive flag alone.
  defp archived_qualification!(program, code) do
    Repo.insert!(%Qualification{
      program_id: program.id,
      code: code,
      title: "Archived qualification #{code}",
      audience: "Nobody.",
      unlocks: [],
      add_on: false,
      validity_kind: :none,
      phases: [],
      position: 1,
      archived_at: DateTime.utc_now(:second)
    })
  end

  describe "credential_report/2 with the qualification order of the pack" do
    setup do
      %{analyst: analyst_scope()}
    end

    # The add-on `a` stands between two base qualifications. The order by
    # add-on flag and code would give b, c, a, the order by code a, b, c.
    test "without position, lists the qualifications in the order of qualifications.yaml",
         %{analyst: analyst} do
      publish_qualifications!([
        qualification_entry("c", false),
        qualification_entry("a", true),
        qualification_entry("b", false)
      ])

      assert {:ok, %{qualifications: qualifications}} =
               Insights.credential_report(analyst, demo_slug())

      assert Enum.map(qualifications, &{&1.code, &1.archived}) == [
               {"c", false},
               {"a", false},
               {"b", false}
             ]
    end

    test "with position on every entry, lists the qualifications by position and not in the order of the file",
         %{analyst: analyst} do
      publish_qualifications!([
        qualification_entry("c", false, 30),
        qualification_entry("a", true, 20),
        qualification_entry("b", false, 10)
      ])

      assert {:ok, %{qualifications: qualifications}} =
               Insights.credential_report(analyst, demo_slug())

      assert Enum.map(qualifications, & &1.code) == ["b", "a", "c"]
    end

    test "lists archived qualifications after the live ones in position order, also with a lower position",
         %{analyst: analyst} do
      program =
        publish_qualifications!([
          qualification_entry("c", false),
          qualification_entry("a", true),
          qualification_entry("b", false)
        ])

      c = program |> qualification!("c") |> archive!()
      b = program |> qualification!("b") |> archive!()
      assert {c.position, qualification!(program, "a").position, b.position} == {1, 2, 3}

      # An archived qualification has a row only with a shown cell.
      credential_fixture(user_fixture(), b, %{status: :active})
      credential_fixture(user_fixture(), c, %{status: :expired})

      assert {:ok, %{qualifications: qualifications}} =
               Insights.credential_report(analyst, demo_slug())

      assert Enum.map(qualifications, &{&1.code, &1.archived}) == [
               {"a", false},
               {"c", true},
               {"b", true}
             ]
    end
  end

  # Publishes a copy of the demo pack whose qualifications.yaml holds
  # `entries` in place of basics and workshop.
  defp publish_qualifications!(entries) do
    pack = PackFixtures.copy_pack!(PackFixtures.demo_path())
    PackFixtures.write_yaml!(pack, "qualifications.yaml", entries)
    publish_demo!(pack)
  end

  # An entry of qualifications.yaml that requires module 1 of the demo pack,
  # with `position` when one is given.
  defp qualification_entry(code, add_on, position \\ nil) do
    entry = %{
      "code" => code,
      "title" => "Qualification #{code}",
      "audience" => "Everyone.",
      "unlocks" => ["Task #{code}"],
      "add_on" => add_on,
      "validity_kind" => "none",
      "phases" => ["anchor"],
      "requirements" => [%{"kind" => "module_completed", "target" => 1}]
    }

    if position, do: Map.put(entry, "position", position), else: entry
  end

  describe "participation/2" do
    setup do
      %{program: publish_demo!(), scope: scope_for(user_fixture())}
    end

    test "reports the markers of the scope user and no answer",
         %{program: program, scope: scope} do
      assert Insights.participation(scope, demo_slug()) ==
               {:ok, %{self_assessment: false, feedback: false, format_votes: []}}

      handbook = format!(program, "handbook")
      workshop = format!(program, "workshop")

      assert {:ok, _} = Insights.record_self_assessment(scope, demo_slug(), "non-users")
      assert {:ok, _} = Insights.vote_format(scope, workshop.id, "would_use")
      assert {:ok, _} = Insights.vote_format(scope, handbook.id, "would_use")
      assert {:ok, _} = Insights.record_feedback(scope, demo_slug(), %{"clarity" => 3})

      assert Insights.participation(scope, demo_slug()) ==
               {:ok,
                %{self_assessment: true, feedback: true, format_votes: [handbook.id, workshop.id]}}

      assert Insights.participation(scope_for(user_fixture()), demo_slug()) ==
               {:ok, %{self_assessment: false, feedback: false, format_votes: []}}
    end

    test "lists only the votes for live formats of the program",
         %{program: program, scope: scope} do
      help_desk = format!(program, "help-desk")
      assert {:ok, _} = Insights.vote_format(scope, help_desk.id, "would_use")
      archive!(help_desk)

      other = publish_minimal!()
      assert {:ok, _} = Insights.vote_format(scope, format!(other, "workshop").id, "would_use")

      assert {:ok, %{format_votes: []}} = Insights.participation(scope, demo_slug())
    end

    test "an unknown or unpublished program answers not_found",
         %{program: program, scope: scope} do
      assert Insights.participation(scope, "unknown-program") == {:error, :not_found}

      unpublish!(program)
      assert Insights.participation(scope, demo_slug()) == {:error, :not_found}
    end
  end

  describe "record_self_assessment/3" do
    setup do
      %{program: publish_demo!(), scope: scope_for(user_fixture())}
    end

    test "records a new answer and applies the segment's default path",
         %{program: program, scope: scope} do
      today = Date.utc_today()

      assert Insights.record_self_assessment(scope, demo_slug(), "non-users") ==
               {:ok, %{path: :full, already_recorded: false}}

      assert [%SelfAssessmentResponse{segment_key: "non-users", org_unit: nil} = row] =
               Repo.all(SelfAssessmentResponse)

      assert row.program_id == program.id
      assert_recorded_today(row.recorded_on, today)

      assert %Enrollment{path: :full, path_chosen_manually: false} =
               Learning.get_enrollment(scope, program.id)

      assert [%ParticipationMarker{subject_type: :self_assessment}] = markers()
    end

    test "a second answer creates no row and leaves the enrollment unchanged",
         %{program: program, scope: scope} do
      assert {:ok, %{path: :full, already_recorded: false}} =
               Insights.record_self_assessment(scope, demo_slug(), "non-users")

      assert Insights.record_self_assessment(scope, demo_slug(), "daily-users") ==
               {:ok, %{path: :full, already_recorded: true}}

      assert [%SelfAssessmentResponse{segment_key: "non-users"}] =
               Repo.all(SelfAssessmentResponse)

      assert Learning.get_enrollment(scope, program.id).path == :full
    end

    test "leaves a manually chosen path unchanged", %{program: program, scope: scope} do
      enrollment = enroll!(scope, "full")
      assert {:ok, _manual} = Learning.update_path(scope, enrollment.id, "short")

      assert Insights.record_self_assessment(scope, demo_slug(), "non-users") ==
               {:ok, %{path: :short, already_recorded: false}}

      assert %Enrollment{path: :short, path_chosen_manually: true} =
               Learning.get_enrollment(scope, program.id)

      assert [%SelfAssessmentResponse{segment_key: "non-users"}] =
               Repo.all(SelfAssessmentResponse)
    end

    test "an answer already recorded without an enrollment returns the path nil",
         %{program: program, scope: scope} do
      assert {:ok, :marked} =
               Insights.record_once(scope, {:self_assessment, program.id}, fn ->
                 {:ok, :marked}
               end)

      assert Insights.record_self_assessment(scope, demo_slug(), "daily-users") ==
               {:ok, %{path: nil, already_recorded: true}}

      assert Learning.get_enrollment(scope, program.id) == nil
      assert Repo.aggregate(SelfAssessmentResponse, :count) == 0
    end

    test "stores the org unit of the user only with insights_org_unit true" do
      values = ["  Finance  ", String.duplicate("ä", 300), "   "]

      put_learning(insights_org_unit: true)

      for value <- values do
        user = user_with_org_unit(value)

        assert {:ok, _} =
                 Insights.record_self_assessment(scope_for(user), demo_slug(), "daily-users")
      end

      assert stored_org_units() == Enum.sort(Enum.map(values, &Insights.org_unit/1))
      assert "Finance" in stored_org_units()
      assert Enum.any?(stored_org_units(), &(&1 && String.length(&1) == 255))

      Repo.delete_all(SelfAssessmentResponse)
      put_learning(insights_org_unit: false)
      user = user_with_org_unit("Finance")

      assert {:ok, _} = Insights.record_self_assessment(scope_for(user), demo_slug(), "non-users")
      assert stored_org_units() == [nil]
    end

    test "an unknown or unpublished program answers not_found and records nothing",
         %{program: program, scope: scope} do
      assert Insights.record_self_assessment(scope, "unknown-program", "daily-users") ==
               {:error, :not_found}

      unpublish!(program)

      assert Insights.record_self_assessment(scope, demo_slug(), "daily-users") ==
               {:error, :not_found}

      assert markers() == []
      assert Repo.aggregate(SelfAssessmentResponse, :count) == 0
    end

    test "an unknown or archived segment answers validation_failed on segment_key",
         %{program: program, scope: scope} do
      assert Insights.record_self_assessment(scope, demo_slug(), "unknown-segment") ==
               @invalid_segment

      program |> segment!("daily-users") |> archive!()

      assert Insights.record_self_assessment(scope, demo_slug(), "daily-users") ==
               @invalid_segment

      assert markers() == []
      assert Repo.aggregate(SelfAssessmentResponse, :count) == 0
      assert Learning.get_enrollment(scope, program.id) == nil

      assert {:ok, %{already_recorded: false}} =
               Insights.record_self_assessment(scope, demo_slug(), "non-users")
    end
  end

  # The org units of the stored self-assessment rows, sorted with nil first.
  defp stored_org_units do
    Repo.all(from r in SelfAssessmentResponse, select: r.org_unit)
    |> Enum.sort()
  end

  describe "vote_format/3" do
    setup do
      %{program: publish_demo!(), scope: scope_for(user_fixture())}
    end

    test "records a vote once per person and format", %{program: program, scope: scope} do
      workshop = format!(program, "workshop")
      today = Date.utc_today()

      assert Insights.vote_format(scope, workshop.id, "would_use") ==
               {:ok, %{already_recorded: false}}

      assert Insights.vote_format(scope, workshop.id, "would_use") ==
               {:ok, %{already_recorded: true}}

      assert [%InterestVote{choice: :would_use} = vote] = Repo.all(InterestVote)
      assert vote.companion_format_id == workshop.id
      assert_recorded_today(vote.recorded_on, today)
    end

    test "an unknown or archived format, or one of an unpublished program, answers not_found",
         %{program: program, scope: scope} do
      assert Insights.vote_format(scope, Ecto.UUID.generate(), "would_use") ==
               {:error, :not_found}

      help_desk = program |> format!("help-desk") |> archive!()
      assert Insights.vote_format(scope, help_desk.id, "would_use") == {:error, :not_found}

      workshop = format!(program, "workshop")
      unpublish!(program)
      assert Insights.vote_format(scope, workshop.id, "would_use") == {:error, :not_found}

      assert markers() == []
      assert Repo.aggregate(InterestVote, :count) == 0
    end
  end

  describe "record_feedback/3" do
    setup do
      %{program: publish_demo!(), scope: scope_for(user_fixture())}
    end

    test "stores the answers once, with the free text trimmed",
         %{program: program, scope: scope} do
      put_insights(feedback_free_text: true)

      answers = %{
        "usefulness" => "somewhat-useful",
        "clarity" => 5,
        "suggestion" => "  More examples, please.\n"
      }

      today = Date.utc_today()

      assert Insights.record_feedback(scope, demo_slug(), answers) ==
               {:ok, %{already_recorded: false}}

      assert [%FeedbackResponse{} = row] = Repo.all(FeedbackResponse)
      assert row.program_id == program.id
      assert_recorded_today(row.recorded_on, today)

      assert row.answers == %{
               "usefulness" => "somewhat-useful",
               "clarity" => 5,
               "suggestion" => "More examples, please."
             }

      assert Insights.record_feedback(scope, demo_slug(), %{"clarity" => 1}) ==
               {:ok, %{already_recorded: true}}

      assert [_one] = Repo.all(FeedbackResponse)
    end

    test "accepts a part of the questions, also with atom keys", %{scope: scope} do
      assert Insights.record_feedback(scope, demo_slug(), %{usefulness: "not-useful"}) ==
               {:ok, %{already_recorded: false}}

      assert [%FeedbackResponse{answers: %{"usefulness" => "not-useful"} = answers}] =
               Repo.all(FeedbackResponse)

      assert map_size(answers) == 1
    end

    test "accepts free text of 2,000 characters after trimming", %{scope: scope} do
      put_insights(feedback_free_text: true)
      text = String.duplicate("ä", Insights.free_text_length())

      assert {:ok, %{already_recorded: false}} =
               Insights.record_feedback(scope, demo_slug(), %{"suggestion" => "  " <> text <> " "})

      assert [%FeedbackResponse{answers: %{"suggestion" => ^text}}] = Repo.all(FeedbackResponse)
    end

    test "rejects answers that do not fit their question and records nothing",
         %{scope: scope} do
      put_insights(feedback_free_text: true)

      invalid = [
        %{},
        %{"unknown" => "very-useful"},
        %{"usefulness" => "unknown-option"},
        %{"usefulness" => 1},
        %{"usefulness" => nil},
        %{"clarity" => 0},
        %{"clarity" => 6},
        %{"clarity" => "3"},
        %{"clarity" => 3.0},
        %{"suggestion" => "   "},
        %{"suggestion" => String.duplicate("a", Insights.free_text_length() + 1)},
        %{"suggestion" => "a\u0000b"},
        # Invalid UTF-8, which only a caller outside the JSON parser can pass.
        %{"suggestion" => <<0xFF, 0x41>>},
        # One grapheme of 50,001 code points: the limit counts code points.
        %{"suggestion" => "e" <> String.duplicate("́", 50_000)},
        %{"suggestion" => 5},
        %{"usefulness" => "very-useful", "clarity" => 9}
      ]

      for answers <- invalid do
        assert Insights.record_feedback(scope, demo_slug(), answers) == @invalid_answers,
               inspect(answers)
      end

      assert markers() == []
      assert Repo.aggregate(FeedbackResponse, :count) == 0

      assert {:ok, %{already_recorded: false}} =
               Insights.record_feedback(scope, demo_slug(), %{"usefulness" => "very-useful"})
    end

    test "rejects free text while feedback_free_text is false", %{scope: scope} do
      put_insights(feedback_free_text: false)

      assert Insights.record_feedback(scope, demo_slug(), %{"suggestion" => "Fine."}) ==
               @invalid_answers

      assert Insights.record_feedback(scope, demo_slug(), %{
               "usefulness" => "very-useful",
               "suggestion" => "Fine."
             }) == @invalid_answers

      assert markers() == []
      assert Repo.aggregate(FeedbackResponse, :count) == 0
    end

    test "a program that is unknown, unpublished or without a feedback station answers not_found",
         %{program: program, scope: scope} do
      answers = %{"usefulness" => "very-useful"}

      assert Insights.record_feedback(scope, "unknown-program", answers) == {:error, :not_found}

      Repo.delete_all(
        from s in Station, where: s.program_id == ^program.id and s.kind == :feedback
      )

      assert Insights.record_feedback(scope, demo_slug(), answers) == {:error, :not_found}

      other = publish_minimal!()
      unpublish!(other)

      assert Insights.record_feedback(scope, "minimal-pack", %{"useful" => "yes"}) ==
               {:error, :not_found}

      assert markers() == []
      assert Repo.aggregate(FeedbackResponse, :count) == 0
    end
  end
end
