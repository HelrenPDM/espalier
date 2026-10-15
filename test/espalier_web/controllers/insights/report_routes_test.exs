defmodule EspalierWeb.Insights.ReportRoutesTest do
  @moduledoc """
  The six report routes of the role `analyst` (task 0014, steps 8 and 13,
  ASVS 8.2.1 and the Acceptance): `GET /api/insights/self-assessment`,
  `/items`, `/competence`, `/formats`, `/feedback` and `/credentials`.

  Each route answers 401 without a session, 403 `enrollment_required` for
  an enrollment session, 403 `forbidden` with a logged `authz_fail` for a
  user without the role `analyst`, 404 for an unknown program, 422 for a
  slug that breaks the key format, and 200 with a body that matches the
  schema of its operation for an analyst, always with
  `cache-control: no-store`. The acceptance cases with
  `INSIGHTS_MIN_GROUP_SIZE=5` run through the learner routes: four
  learners leave a cell suppressed, and the fifth makes it visible with the
  count 5. This holds for a segment of the self-assessment, for the active
  credentials of a qualification and for a competence cell, whose value is
  then the share correct. A suppressed cell carries neither a count nor a
  value, every body names the threshold and the locale of the program, and
  the raw text of no body holds the id, the display name or the e-mail
  address of a learner.

  The other report cases: once any answer exists, the self-assessment
  report lists every live segment, the feedback lists free text only once
  the number of texts reaches the threshold, the format report counts each
  person's vote once per format, the item report leaves out polls, and the
  self-assessment report breaks down by org unit only while
  `INSIGHTS_ORG_UNIT` is true, and the credential report lists the
  qualifications in the order of `qualifications.yaml`, or by the
  `position` of its entries (issue #39).

  The expected months are read back from the stored rows, so that a test
  that runs across the end of a month expects the month the rows were
  recorded in.
  """
  # put_insights/1 and put_learning/1 change the application environment.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query, only: [from: 2]
  import Espalier.CredentialsFixtures
  import Espalier.InsightsFixtures
  import Espalier.LearningFixtures
  import OpenApiSpex.TestAssertions

  alias Espalier.{Accounts, Catalog, PackFixtures}
  alias Espalier.Accounts.Scope
  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.{PackImport, Segment}
  alias Espalier.Insights.{ItemStat, SelfAssessmentResponse}
  alias Espalier.Repo
  alias EspalierWeb.ApiSpec

  # Each report route with the schema of its 200 answer.
  @routes [
    {"self-assessment", "SelfAssessmentReport"},
    {"items", "ItemReport"},
    {"competence", "CompetenceReport"},
    {"formats", "FormatReport"},
    {"feedback", "FeedbackReport"},
    {"credentials", "CredentialReport"}
  ]

  @statuses ~w(active refresh_due expired revoked)

  # The live segments of the demo pack in their order.
  @segment_keys ~w(daily-users occasional-users non-users stopped-users)

  @suppressed %{"suppressed" => true}

  setup do
    # The threshold of the acceptance, and the defaults of the other settings.
    put_insights(min_group_size: 5, feedback_free_text: false)
    put_learning(insights_org_unit: false)

    %{program: publish_demo!(), analyst: user_with_role_fixture(:analyst), spec: ApiSpec.spec()}
  end

  defp report_path(route, slug), do: "/api/insights/#{route}?program=#{slug}"

  # GET of a report by `user` with a fresh session of strength mfa.
  defp get_report(user, route, slug),
    do: json_request(log_in_user(api_conn(), user), :get, report_path(route, slug))

  # The body of a 200 answer, after the check of its cache header.
  defp report!(user, route, slug) do
    response = get_report(user, route, slug)
    assert get_resp_header(response, "cache-control") == ["no-store"], route
    json_response(response, 200)
  end

  # The months of the stored rows of `queryable` (a schema or a query) in
  # ascending order as ISO 8601 dates, read from the date column `column`.
  defp stored_months(queryable, column) do
    Repo.all(from r in queryable, select: field(r, ^column))
    |> Enum.map(&Date.beginning_of_month/1)
    |> Enum.uniq()
    |> Enum.sort(Date)
    |> Enum.map(&Date.to_iso8601/1)
  end

  # The rows of the self-assessment report without the org-unit breakdown:
  # one row per live segment, whose cells `cells` gives by segment key and
  # which is one suppressed cell for every other segment.
  defp segment_rows(program, cells) do
    for key <- @segment_keys do
      %{
        "segment_key" => key,
        "label" => label(program, key),
        "org_unit" => nil,
        "cells" => Map.get(cells, key, [@suppressed])
      }
    end
  end

  defp with_org_unit(user, org_unit) do
    user |> Ecto.Changeset.change(org_unit: org_unit) |> Repo.update!()
  end

  defp label(program, segment_key),
    do: Repo.get_by!(Segment, program_id: program.id, key: segment_key).label

  # Publishes a copy of the demo pack under the key `qualification-order`,
  # whose qualifications.yaml holds `entries`, next to the demo program.
  defp publish_qualifications!(entries) do
    pack = PackFixtures.copy_pack!(PackFixtures.demo_path())
    PackFixtures.update_yaml!(pack, "pack.yaml", &Map.put(&1, "key", "qualification-order"))
    PackFixtures.write_yaml!(pack, "qualifications.yaml", entries)
    {:ok, %PackImport{status: :validated} = pack_import} = Importer.import(pack, nil)
    {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    Catalog.get_program_by_slug("qualification-order")
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

  # Every map in a decoded body that carries the member `suppressed`.
  defp suppressed_entries(%{} = map) do
    own = if Map.has_key?(map, "suppressed"), do: [map], else: []
    own ++ Enum.flat_map(Map.values(map), &suppressed_entries/1)
  end

  defp suppressed_entries(list) when is_list(list), do: Enum.flat_map(list, &suppressed_entries/1)
  defp suppressed_entries(_value), do: []

  ## Learner actions through their routes

  defp self_assess!(user, slug, segment_key) do
    conn =
      json_request(log_in_user(api_conn(), user), :post, "/api/self-assessments", %{
        program_slug: slug,
        segment_key: segment_key
      })

    assert %{"already_recorded" => false} = json_response(conn, 200)
  end

  defp answer_item!(user, item, answer) do
    conn =
      json_request(log_in_user(api_conn(), user), :post, "/api/items/#{item.id}/responses", %{
        answer: answer
      })

    json_response(conn, 200)
  end

  defp vote!(user, format) do
    conn =
      json_request(log_in_user(api_conn(), user), :post, "/api/formats/#{format.id}/votes", %{
        choice: "would_use"
      })

    json_response(conn, 200)
  end

  defp feedback!(user, slug, answers) do
    conn =
      json_request(log_in_user(api_conn(), user), :post, "/api/feedback", %{
        program_slug: slug,
        answers: answers
      })

    assert json_response(conn, 200) == %{"already_recorded" => false}
  end

  describe "access (ASVS 8.2.1)" do
    test "every report route answers 401 without a session", %{program: program} do
      for {route, _schema} <- @routes do
        conn = json_request(api_conn(), :get, report_path(route, program.slug))
        assert json_response(conn, 401) == %{"error" => "unauthenticated"}, route
        assert get_resp_header(conn, "cache-control") == ["no-store"], route
      end
    end

    test "every report route answers 403 enrollment_required for an enrollment session of an analyst",
         %{program: program, analyst: analyst} do
      conn =
        log_in_user(api_conn(), analyst, %{strength: :enrollment, auth_methods: [:email_code]})

      ref = attach_security_events()
      analyst_id = analyst.id

      for {route, _schema} <- @routes do
        response = json_request(conn, :get, report_path(route, program.slug))
        assert json_response(response, 403) == %{"error" => "enrollment_required"}, route
        assert get_resp_header(response, "cache-control") == ["no-store"], route

        assert_received {^ref,
                         %{name: :authz_fail, reason: "enrollment_required", user_id: ^analyst_id}}
      end
    end

    test "every report route answers 403 forbidden for a learner, also for an unknown program",
         %{program: program} do
      learner = user_fixture()
      learner_id = learner.id
      ref = attach_security_events()

      for {route, _schema} <- @routes, slug <- [program.slug, "no-such-program"] do
        response = get_report(learner, route, slug)
        assert json_response(response, 403) == %{"error" => "forbidden"}, route
        assert get_resp_header(response, "cache-control") == ["no-store"], route
        assert_received {^ref, %{name: :authz_fail, reason: "forbidden", user_id: ^learner_id}}
      end
    end

    test "every report route answers 403 forbidden for a user with every role but analyst",
         %{program: program} do
      user = user_with_role_fixture(:admin)

      for role <- [:facilitator, :author, :registrar] do
        {:ok, _grant} = Accounts.grant_role(Scope.system(), user, role)
      end

      for {route, _schema} <- @routes do
        response = get_report(user, route, program.slug)
        assert json_response(response, 403) == %{"error" => "forbidden"}, route
      end
    end

    test "every report route answers 404 for an unknown program", %{analyst: analyst} do
      for {route, _schema} <- @routes do
        response = get_report(analyst, route, "no-such-program")
        assert json_response(response, 404) == %{"error" => "not_found"}, route
        assert get_resp_header(response, "cache-control") == ["no-store"], route
      end
    end

    test "every report route answers 422 for a slug that breaks the key format or is missing",
         %{analyst: analyst} do
      for {route, _schema} <- @routes do
        for slug <- ["Not_A_Slug", "-leading-dash", "demo%0A"] do
          response = get_report(analyst, route, slug)

          assert json_response(response, 422) == %{
                   "error" => "validation_failed",
                   "fields" => %{"program" => ["invalid_format"]}
                 },
                 "#{route} #{slug}"

          assert get_resp_header(response, "cache-control") == ["no-store"], route
        end

        response =
          json_request(log_in_user(api_conn(), analyst), :get, "/api/insights/#{route}")

        assert json_response(response, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"program" => ["missing_field"]}
               },
               route
      end
    end
  end

  # Rows that give every report visible cells and suppressed ones at the
  # threshold 5: a poll with statistics, a revoked credential and formats,
  # options and scale values without answers.
  defp populate!(program) do
    today = Date.utc_today()
    self_assessment_rows!(program, "daily-users", 5)
    self_assessment_rows!(program, "non-users", 2)
    item_stat!(item!(program, "m1-how-models-write"), today, 6, 3)
    item_stat!(item!(program, "m1-before-use"), today, 2, 1)
    item_stat!(item!(program, "m1-first-task-poll"), today, 9, 0)
    vote_rows!(format!(program, "handbook"), 5)
    vote_rows!(format!(program, "workshop"), 1)

    for i <- 1..5 do
      feedback_row!(program, %{
        "usefulness" => "very-useful",
        "clarity" => 4,
        "suggestion" => "Suggestion #{i}"
      })
    end

    basics = qualification!(program, "basics")
    for _ <- 1..5, do: credential_fixture(user_fixture(), basics)
    credential_fixture(user_fixture(), basics, %{status: :revoked})
  end

  describe "an analyst" do
    # One test per route and case, so that a schema mismatch of one route
    # leaves the checks of the others visible.
    for {route, schema} <- @routes do
      @route route
      @schema schema

      test "receives GET /api/insights/#{route} without answers as #{schema}",
           %{program: program, analyst: analyst, spec: spec} do
        body = report!(analyst, @route, program.slug)
        assert body["min_group_size"] == 5
        assert body["locale"] == program.locale
        assert_schema(body, @schema, spec)
      end

      test "receives GET /api/insights/#{route} with visible and suppressed cells as #{schema}",
           %{program: program, analyst: analyst, spec: spec} do
        populate!(program)
        body = report!(analyst, @route, program.slug)
        assert body["min_group_size"] == 5
        assert body["locale"] == program.locale

        # A suppressed cell carries neither a count nor a value.
        entries = suppressed_entries(body)
        assert entries != []
        assert Enum.all?(entries, &(&1 == %{"suppressed" => true}))
        assert_schema(body, @schema, spec)
      end
    end

    test "receives no month and no row before any answer", %{program: program, analyst: analyst} do
      assert %{"months" => [], "rows" => [], "by_org_unit" => false} =
               report!(analyst, "self-assessment", program.slug)

      assert %{"months" => [], "rows" => []} = report!(analyst, "items", program.slug)
      assert %{"months" => [], "rows" => []} = report!(analyst, "competence", program.slug)
    end

    test "reads a program in any status", %{program: program, analyst: analyst, spec: spec} do
      self_assessment_rows!(program, "daily-users", 5)
      program |> Ecto.Changeset.change(status: :archived) |> Repo.update!()

      body = report!(analyst, "self-assessment", program.slug)
      assert_schema(body, "SelfAssessmentReport", spec)

      assert body["rows"] ==
               segment_rows(program, %{"daily-users" => [%{"count" => 5, "value" => 5}]})
    end

    test "receives the locale of the program in every report, as its schema declares",
         %{program: program, analyst: analyst, spec: spec} do
      program |> Ecto.Changeset.change(locale: "de") |> Repo.update!()

      for {route, schema} <- @routes do
        body = report!(analyst, route, program.slug)
        assert body["locale"] == "de", route
        assert_schema(body, schema, spec)
        assert :locale in spec.components.schemas[schema].required, route
      end
    end

    # The add-on `a` stands between two base qualifications, where the order
    # by add-on flag and code would put it last.
    test "receives the qualifications of /credentials in the order of qualifications.yaml",
         %{analyst: analyst, spec: spec} do
      program =
        publish_qualifications!([
          qualification_entry("c", false),
          qualification_entry("a", true),
          qualification_entry("b", false)
        ])

      body = report!(analyst, "credentials", program.slug)
      assert_schema(body, "CredentialReport", spec)

      assert Enum.map(body["qualifications"], &{&1["code"], &1["archived"]}) == [
               {"c", false},
               {"a", false},
               {"b", false}
             ]
    end

    test "receives the qualifications of /credentials by position when every entry sets one",
         %{analyst: analyst} do
      program =
        publish_qualifications!([
          qualification_entry("c", false, 30),
          qualification_entry("a", true, 20),
          qualification_entry("b", false, 10)
        ])

      body = report!(analyst, "credentials", program.slug)
      assert Enum.map(body["qualifications"], & &1["code"]) == ~w(b a c)
    end
  end

  describe "with INSIGHTS_MIN_GROUP_SIZE=5" do
    test "a self-assessment cell is suppressed after four learners and counts 5 after the fifth",
         %{program: program, analyst: analyst} do
      [first | rest] = for _ <- 1..5, do: user_fixture()

      for user <- rest, do: self_assess!(user, program.slug, "daily-users")

      # Every live segment has a row, so the four answers show only as a
      # suppressed cell, as a segment without answers does.
      assert report!(analyst, "self-assessment", program.slug) == %{
               "min_group_size" => 5,
               "locale" => program.locale,
               "by_org_unit" => false,
               "months" => stored_months(SelfAssessmentResponse, :recorded_on),
               "rows" => segment_rows(program, %{})
             }

      self_assess!(first, program.slug, "daily-users")

      assert report!(analyst, "self-assessment", program.slug) == %{
               "min_group_size" => 5,
               "locale" => program.locale,
               "by_org_unit" => false,
               "months" => stored_months(SelfAssessmentResponse, :recorded_on),
               "rows" =>
                 segment_rows(program, %{"daily-users" => [%{"count" => 5, "value" => 5}]})
             }
    end

    test "the active credentials of a qualification are suppressed with four people and count 5 with five",
         %{program: program, analyst: analyst} do
      basics = qualification!(program, "basics")
      for _ <- 1..4, do: credential_fixture(user_fixture(), basics)

      suppressed =
        for status <- @statuses, do: %{"status" => status, "cell" => %{"suppressed" => true}}

      assert %{"min_group_size" => 5, "qualifications" => qualifications} =
               report!(analyst, "credentials", program.slug)

      assert [
               %{"code" => "basics", "archived" => false, "statuses" => ^suppressed},
               %{"code" => "workshop", "archived" => false, "statuses" => ^suppressed}
             ] = qualifications

      credential_fixture(user_fixture(), basics)

      assert %{"qualifications" => [basics_row, workshop_row]} =
               report!(analyst, "credentials", program.slug)

      assert basics_row == %{
               "code" => "basics",
               "title" => basics.title,
               "archived" => false,
               "statuses" => [
                 %{"status" => "active", "cell" => %{"count" => 5, "value" => 5}}
                 | tl(suppressed)
               ]
             }

      assert workshop_row["statuses"] == suppressed
    end

    test "a competence cell is suppressed after four answers and shows count 5 and the share correct after the fifth",
         %{program: program, analyst: analyst} do
      # The practice item names the single objective m1-subject-next-word
      # (subject/know), so its answers produce exactly one row.
      item = item!(program, "m1-how-models-write")
      learners = for _ <- 1..5, do: user_fixture()
      for user <- learners, do: enroll!(scope_for(user))

      answers = [
        correct_answer(item),
        correct_answer(item),
        correct_answer(item),
        wrong_answer(item),
        wrong_answer(item)
      ]

      [{fifth, fifth_answer} | first_four] = learners |> Enum.zip(answers) |> Enum.reverse()

      for {user, answer} <- first_four, do: answer_item!(user, item, answer)

      row = %{"area" => "subject", "depth" => "know", "org_unit" => nil}

      assert report!(analyst, "competence", program.slug) == %{
               "min_group_size" => 5,
               "locale" => program.locale,
               "by_org_unit" => false,
               "months" => stored_months(ItemStat, :period),
               "rows" => [Map.put(row, "cells", [%{"suppressed" => true}])]
             }

      assert %{"correct" => false} = answer_item!(fifth, item, fifth_answer)

      assert report!(analyst, "competence", program.slug) == %{
               "min_group_size" => 5,
               "locale" => program.locale,
               "by_org_unit" => false,
               "months" => stored_months(ItemStat, :period),
               "rows" => [Map.put(row, "cells", [%{"count" => 5, "value" => 0.6}])]
             }
    end

    test "the feedback lists free text only from the threshold on, in any order",
         %{program: program, analyst: analyst} do
      put_insights(feedback_free_text: true)
      texts = for i <- 1..5, do: "Add more examples, please (#{i})."
      [last | first_four] = Enum.reverse(texts)

      answers = fn text ->
        %{"usefulness" => "very-useful", "clarity" => 4, "suggestion" => text}
      end

      for text <- first_four, do: feedback!(user_fixture(), program.slug, answers.(text))

      body = report!(analyst, "feedback", program.slug)
      questions = Map.new(body["questions"], &{&1["key"], &1})

      assert questions["suggestion"]["free_text"] == %{"suppressed" => true}
      assert questions["suggestion"]["choices"] == []

      assert Enum.all?(
               questions["usefulness"]["choices"],
               &(&1["cell"] == %{"suppressed" => true})
             )

      assert questions["usefulness"]["free_text"] == nil

      feedback!(user_fixture(), program.slug, answers.(last))

      body = report!(analyst, "feedback", program.slug)
      assert Enum.map(body["questions"], & &1["key"]) == ~w(usefulness clarity suggestion)
      questions = Map.new(body["questions"], &{&1["key"], &1})

      assert %{"count" => 5, "answers" => listed} = questions["suggestion"]["free_text"]
      assert length(listed) == 5
      assert MapSet.new(listed) == MapSet.new(texts)

      assert Enum.map(questions["usefulness"]["choices"], &{&1["key"], &1["cell"]}) == [
               {"very-useful", %{"count" => 5, "value" => 5}},
               {"somewhat-useful", %{"suppressed" => true}},
               {"not-useful", %{"suppressed" => true}}
             ]

      assert Enum.map(questions["clarity"]["choices"], &{&1["key"], &1["cell"]}) == [
               {"1", %{"suppressed" => true}},
               {"2", %{"suppressed" => true}},
               {"3", %{"suppressed" => true}},
               {"4", %{"count" => 5, "value" => 5}},
               {"5", %{"suppressed" => true}}
             ]
    end
  end

  describe "with a smaller threshold" do
    test "the format report counts the votes per format, each person once",
         %{program: program, analyst: analyst} do
      put_insights(min_group_size: 2)
      [ada, ben, cleo] = for _ <- 1..3, do: user_fixture()
      handbook = format!(program, "handbook")
      workshop = format!(program, "workshop")

      for user <- [ada, ben, cleo], do: vote!(user, handbook)
      for user <- [ada, ben], do: vote!(user, workshop)
      assert vote!(ada, handbook) == %{"already_recorded" => true}

      assert %{"min_group_size" => 2, "formats" => formats} =
               report!(analyst, "formats", program.slug)

      assert Enum.map(formats, &{&1["key"], &1["cell"]}) == [
               {"handbook", %{"count" => 3, "value" => 3}},
               {"workshop", %{"count" => 2, "value" => 2}},
               {"help-desk", %{"suppressed" => true}}
             ]

      assert Enum.map(formats, & &1["id"]) ==
               [handbook.id, workshop.id, format!(program, "help-desk").id]
    end

    test "the item report leaves out polls", %{program: program, analyst: analyst} do
      put_insights(min_group_size: 2)
      item = item!(program, "m1-how-models-write")
      poll = item!(program, "m1-first-task-poll")

      for {user, answer} <- [
            {user_fixture(), correct_answer(item)},
            {user_fixture(), wrong_answer(item)}
          ] do
        enroll!(scope_for(user))
        answer_item!(user, item, answer)
        answer_item!(user, poll, correct_answer(poll))
      end

      # The poll answers are counted, so the report leaves out an existing row.
      assert [%ItemStat{attempts: 2}] = Repo.all(from s in ItemStat, where: s.item_id == ^poll.id)

      assert report!(analyst, "items", program.slug) == %{
               "min_group_size" => 2,
               "locale" => program.locale,
               "months" =>
                 stored_months(from(s in ItemStat, where: s.item_id == ^item.id), :period),
               "rows" => [
                 %{
                   "item_id" => item.id,
                   "key" => "m1-how-models-write",
                   "kind" => "single_choice",
                   "module_number" => 1,
                   "stem" => item.stem,
                   "cells" => [%{"count" => 2, "value" => 0.5}]
                 }
               ]
             }
    end

    test "the self-assessment report breaks down by org unit while INSIGHTS_ORG_UNIT is true",
         %{program: program, analyst: analyst, spec: spec} do
      put_insights(min_group_size: 1)
      put_learning(insights_org_unit: true)

      for org_unit <- ["Unit A", "Unit A", "Unit B", nil] do
        user_fixture() |> with_org_unit(org_unit) |> self_assess!(program.slug, "daily-users")
      end

      body = report!(analyst, "self-assessment", program.slug)
      assert_schema(body, "SelfAssessmentReport", spec)
      assert %{"by_org_unit" => true, "months" => months, "rows" => rows} = body
      assert months == stored_months(SelfAssessmentResponse, :recorded_on)

      # Every live segment has a row per org unit with answers, nil last.
      shown = %{
        {"daily-users", "Unit A"} => [%{"count" => 2, "value" => 2}],
        {"daily-users", "Unit B"} => [%{"count" => 1, "value" => 1}],
        {"daily-users", nil} => [%{"count" => 1, "value" => 1}]
      }

      assert Enum.map(rows, &{&1["segment_key"], &1["org_unit"], &1["cells"]}) ==
               for(
                 key <- @segment_keys,
                 org_unit <- ["Unit A", "Unit B", nil],
                 do: {key, org_unit, Map.get(shown, {key, org_unit}, [@suppressed])}
               )

      # With the setting false, the same answers sum into one row per segment.
      put_learning(insights_org_unit: false)

      assert %{"by_org_unit" => false, "rows" => rows} =
               report!(analyst, "self-assessment", program.slug)

      assert rows == segment_rows(program, %{"daily-users" => [%{"count" => 4, "value" => 4}]})
    end

    test "no report body contains the id, the display name or the e-mail address of a learner",
         %{program: program, analyst: analyst} do
      put_insights(min_group_size: 1, feedback_free_text: true)
      put_learning(insights_org_unit: true)
      item = item!(program, "m1-how-models-write")
      handbook = format!(program, "handbook")
      basics = qualification!(program, "basics")

      learners =
        for name <- ["Quentin Learner", "Rosalind Learner", "Sergei Learner"] do
          user = user_fixture(%{display_name: name}) |> with_org_unit("Unit A")
          self_assess!(user, program.slug, "daily-users")
          answer_item!(user, item, correct_answer(item))
          vote!(user, handbook)

          feedback!(user, program.slug, %{
            "usefulness" => "very-useful",
            "clarity" => 5,
            "suggestion" => "More examples from daily work."
          })

          credential_fixture(user, basics)
          user
        end

      for {route, _schema} <- @routes do
        response = get_report(analyst, route, program.slug)
        assert json_response(response, 200)["min_group_size"] == 1

        for user <- learners, needle <- [user.id, user.display_name, user.email] do
          refute response.resp_body =~ needle, "#{route} contains #{needle}"
        end
      end

      assert %{"rows" => rows} = report!(analyst, "self-assessment", program.slug)

      assert Enum.map(rows, &{&1["segment_key"], &1["org_unit"], &1["cells"]}) == [
               {"daily-users", "Unit A", [%{"count" => 3, "value" => 3}]}
               | for(key <- tl(@segment_keys), do: {key, "Unit A", [@suppressed]})
             ]

      assert %{"questions" => questions} = report!(analyst, "feedback", program.slug)
      suggestion = Enum.find(questions, &(&1["key"] == "suggestion"))
      assert suggestion["free_text"]["count"] == 3
    end
  end
end
