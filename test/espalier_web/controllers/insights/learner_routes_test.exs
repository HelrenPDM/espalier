defmodule EspalierWeb.Insights.LearnerRoutesTest do
  @moduledoc """
  The four learner routes of task 0014 (spec steps 3, 4 and 13): the
  self-assessment with the default path of its segment, the "would use"
  vote for a companion format, the feedback checked against the questions
  of the feedback station, and the own participation.

  The routes require a signed-in session (ASVS 8.2.1): they answer 401 to
  a signed-out client, 403 `enrollment_required` to an enrollment session,
  and 200 with the schema of their operation to a learner and to an
  analyst, who takes part as a learner as well. They validate their input
  with `CastAndValidate` and the checks of `Espalier.Insights` (ASVS 2.2.1),
  and a body with an extra member answers 422 (ASVS 15.3.3). Each person
  counts once: a repeated answer stores no second row and answers
  `already_recorded: true`, and a repeated self-assessment leaves the path
  unchanged (Acceptance). The anonymous rows carry no user reference, and
  no answer carries a user id (README section 10).
  """
  # put_insights/1 changes config :espalier, :insights for the node.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import Espalier.InsightsFixtures
  import Espalier.LearningFixtures
  import OpenApiSpex.TestAssertions

  alias Espalier.Catalog.{CompanionFormat, Program, Segment, Station}

  alias Espalier.Insights.{
    FeedbackResponse,
    InterestVote,
    ParticipationMarker,
    SelfAssessmentResponse
  }

  alias Espalier.Learning.Enrollment
  alias Espalier.Repo
  alias EspalierWeb.ApiSpec

  @anonymous_tables ~w(self_assessment_responses interest_votes feedback_responses)

  setup do
    program = publish_demo!()
    user = user_fixture()

    %{
      program: program,
      user: user,
      conn: log_in_user(api_conn(), user),
      spec: ApiSpec.spec()
    }
  end

  defp self_assess(conn, slug, segment_key) do
    body = %{program_slug: slug, segment_key: segment_key}
    json_request(conn, :post, "/api/self-assessments", body)
  end

  defp vote(conn, format_id, body \\ %{choice: "would_use"}),
    do: json_request(conn, :post, "/api/formats/#{format_id}/votes", body)

  defp feedback(conn, slug, answers),
    do: json_request(conn, :post, "/api/feedback", %{program_slug: slug, answers: answers})

  defp participation(conn, slug, status \\ 200) do
    conn
    |> json_request(:get, "/api/me/participation?program=#{slug}")
    |> json_response(status)
  end

  defp count(schema), do: Repo.aggregate(schema, :count)

  # The row counts of the three anonymous tables and of the markers.
  defp stored do
    Enum.map(
      [SelfAssessmentResponse, InterestVote, FeedbackResponse, ParticipationMarker],
      &count/1
    )
  end

  defp enrollment(user, program),
    do: Repo.get_by(Enrollment, user_id: user.id, program_id: program.id)

  defp archive!(schema, id) do
    {1, _rows} =
      Repo.update_all(from(r in schema, where: r.id == ^id),
        set: [archived_at: DateTime.utc_now(:second)]
      )

    :ok
  end

  defp segment!(program, key), do: Repo.get_by!(Segment, program_id: program.id, key: key)

  # Every learner route of task 0014 with a body that passes CastAndValidate.
  defp routes(program) do
    slug = program.slug

    [
      {:post, "/api/self-assessments", %{program_slug: slug, segment_key: "daily-users"}},
      {:post, "/api/formats/#{format!(program, "workshop").id}/votes", %{choice: "would_use"}},
      {:post, "/api/feedback", %{program_slug: slug, answers: %{usefulness: "very-useful"}}},
      {:get, "/api/me/participation?program=#{slug}", nil}
    ]
  end

  describe "access" do
    test "every learner route of task 0014 answers 401 without a session", %{program: program} do
      for {method, path, body} <- routes(program) do
        conn = json_request(api_conn(), method, path, body)
        assert json_response(conn, 401) == %{"error" => "unauthenticated"}, "#{method} #{path}"
      end

      assert stored() == [0, 0, 0, 0]
    end

    test "every learner route of task 0014 answers 403 enrollment_required with an enrollment session",
         %{program: program, user: user} do
      conn = log_in_user(api_conn(), user, %{strength: :enrollment, auth_methods: [:email_code]})

      for {method, path, body} <- routes(program) do
        response = json_request(conn, method, path, body)

        assert json_response(response, 403) == %{"error" => "enrollment_required"},
               "#{method} #{path}"
      end

      assert stored() == [0, 0, 0, 0]
      assert count(Enrollment) == 0
    end

    test "every learner route of task 0014 answers 200 for a learner with its schema",
         %{conn: conn, program: program, spec: spec} do
      assert_answers_with_schemas(conn, program, spec)
      assert stored() == [1, 1, 1, 3]
    end

    test "every learner route of task 0014 answers 200 for an analyst with its schema",
         %{program: program, spec: spec} do
      analyst = user_with_role_fixture(:analyst)
      conn = log_in_user(api_conn(), analyst)

      assert_answers_with_schemas(conn, program, spec)
      assert stored() == [1, 1, 1, 3]

      assert %Enrollment{path: :short, path_chosen_manually: false} =
               enrollment(analyst, program)
    end
  end

  # Sends every learner route of task 0014 through `conn` and checks each
  # 200 answer against the schema of its operation.
  defp assert_answers_with_schemas(conn, program, spec) do
    schemas = ~w(SelfAssessmentResult InsightRecorded InsightRecorded Participation)

    for {{method, path, body}, schema} <- Enum.zip(routes(program), schemas) do
      response = conn |> json_request(method, path, body) |> json_response(200)
      assert_schema(response, schema, spec)
    end
  end

  describe "POST /api/self-assessments" do
    test "a new answer applies the default path of the segment and creates the enrollment",
         %{conn: conn, user: user, program: program} do
      assert conn |> self_assess(program.slug, "daily-users") |> json_response(200) == %{
               "path" => "short",
               "already_recorded" => false
             }

      assert %Enrollment{path: :short, path_chosen_manually: false} = enrollment(user, program)

      other = user_fixture()
      other_conn = log_in_user(api_conn(), other)

      assert other_conn |> self_assess(program.slug, "non-users") |> json_response(200) == %{
               "path" => "full",
               "already_recorded" => false
             }

      assert %Enrollment{path: :full, path_chosen_manually: false} = enrollment(other, program)

      segments = Repo.all(from r in SelfAssessmentResponse, select: r.segment_key)
      assert Enum.sort(segments) == ["daily-users", "non-users"]
    end

    test "a second answer of the same person stores no second row and leaves the path unchanged, also with another segment",
         %{conn: conn, user: user, program: program} do
      assert %{"path" => "short", "already_recorded" => false} =
               conn |> self_assess(program.slug, "daily-users") |> json_response(200)

      for segment_key <- ["daily-users", "non-users"] do
        assert conn |> self_assess(program.slug, segment_key) |> json_response(200) == %{
                 "path" => "short",
                 "already_recorded" => true
               },
               segment_key
      end

      assert [%SelfAssessmentResponse{segment_key: "daily-users"}] =
               Repo.all(SelfAssessmentResponse)

      assert count(ParticipationMarker) == 1
      assert %Enrollment{path: :short, path_chosen_manually: false} = enrollment(user, program)
    end

    test "a manually chosen path stays unchanged by a first self-assessment",
         %{conn: conn, user: user, program: program} do
      created =
        conn
        |> json_request(:post, "/api/enrollments", %{program_slug: program.slug, path: "short"})
        |> json_response(201)

      assert %{"path" => "full", "path_chosen_manually" => true} =
               conn
               |> json_request(:patch, "/api/enrollments/#{created["id"]}", %{path: "full"})
               |> json_response(200)

      assert conn |> self_assess(program.slug, "daily-users") |> json_response(200) == %{
               "path" => "full",
               "already_recorded" => false
             }

      assert %Enrollment{path: :full, path_chosen_manually: true} = enrollment(user, program)

      assert [%SelfAssessmentResponse{segment_key: "daily-users"}] =
               Repo.all(SelfAssessmentResponse)
    end

    test "an existing enrollment with path_chosen_manually false takes the default path",
         %{conn: conn, user: user, program: program} do
      existing = enroll!(scope_for(user), "short")

      assert conn |> self_assess(program.slug, "stopped-users") |> json_response(200) == %{
               "path" => "full",
               "already_recorded" => false
             }

      assert %Enrollment{id: id, path: :full, path_chosen_manually: false} =
               enrollment(user, program)

      assert id == existing.id
      assert count(Enrollment) == 1
    end

    test "an unknown and an archived segment answer 422 with the member segment_key",
         %{conn: conn, program: program} do
      :ok = archive!(Segment, segment!(program, "occasional-users").id)

      for segment_key <- ["no-such-segment", "occasional-users"] do
        assert conn |> self_assess(program.slug, segment_key) |> json_response(422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"segment_key" => ["invalid"]}
               },
               segment_key
      end

      assert stored() == [0, 0, 0, 0]
      assert count(Enrollment) == 0
    end

    test "an unknown program answers 404", %{conn: conn} do
      assert conn |> self_assess("no-such-program", "daily-users") |> json_response(404) == %{
               "error" => "not_found"
             }

      assert stored() == [0, 0, 0, 0]
      assert count(Enrollment) == 0
    end

    test "an extra member, a slug that breaks the key pattern and a missing member answer 422",
         %{conn: conn, user: user, program: program} do
      cases = [
        {%{program_slug: program.slug, segment_key: "daily-users", user_id: user.id},
         %{"user_id" => ["unexpected_field"]}},
        {%{program_slug: program.slug, segment_key: "daily-users", path: "full"},
         %{"path" => ["unexpected_field"]}},
        {%{program_slug: "Not A Slug", segment_key: "daily-users"},
         %{"program_slug" => ["invalid_format"]}},
        {%{program_slug: program.slug, segment_key: "daily-users\n"},
         %{"segment_key" => ["invalid_format"]}},
        {%{program_slug: program.slug}, %{"segment_key" => ["missing_field"]}}
      ]

      for {body, fields} <- cases do
        response = json_request(conn, :post, "/api/self-assessments", body)

        assert json_response(response, 422) == %{
                 "error" => "validation_failed",
                 "fields" => fields
               },
               inspect(body)
      end

      assert stored() == [0, 0, 0, 0]
      assert count(Enrollment) == 0
    end
  end

  describe "POST /api/formats/:id/votes" do
    test "a new and a repeated vote store one row per format",
         %{conn: conn, program: program} do
      workshop = format!(program, "workshop")

      assert conn |> vote(workshop.id) |> json_response(200) == %{"already_recorded" => false}
      assert conn |> vote(workshop.id) |> json_response(200) == %{"already_recorded" => true}

      assert [%InterestVote{choice: :would_use, companion_format_id: format_id}] =
               Repo.all(InterestVote)

      assert format_id == workshop.id

      handbook = format!(program, "handbook")
      assert conn |> vote(handbook.id) |> json_response(200) == %{"already_recorded" => false}
      assert count(InterestVote) == 2
      assert count(ParticipationMarker) == 2
    end

    test "an unknown format, an archived format and a format of an unpublished program answer 404",
         %{conn: conn, program: program} do
      help_desk = format!(program, "help-desk")
      :ok = archive!(CompanionFormat, help_desk.id)

      for id <- [Ecto.UUID.generate(), help_desk.id] do
        assert conn |> vote(id) |> json_response(404) == %{"error" => "not_found"}, id
      end

      {1, _rows} =
        Repo.update_all(from(p in Program, where: p.id == ^program.id), set: [status: :archived])

      assert conn |> vote(format!(program, "workshop").id) |> json_response(404) == %{
               "error" => "not_found"
             }

      assert stored() == [0, 0, 0, 0]
    end

    test "a choice other than would_use, an extra member and an id that is no UUID answer 422",
         %{conn: conn, user: user, program: program} do
      workshop = format!(program, "workshop")

      cases = [
        {workshop.id, %{choice: "would_not_use"}, %{"choice" => ["invalid_enum"]}},
        {workshop.id, %{choice: "would_use", user_id: user.id},
         %{"user_id" => ["unexpected_field"]}},
        {workshop.id, %{}, %{"choice" => ["missing_field"]}},
        {"not-a-uuid", %{choice: "would_use"}, %{"id" => ["invalid_format"]}}
      ]

      for {id, body, fields} <- cases do
        assert conn |> vote(id, body) |> json_response(422) == %{
                 "error" => "validation_failed",
                 "fields" => fields
               },
               inspect(body)
      end

      assert stored() == [0, 0, 0, 0]
    end
  end

  describe "POST /api/feedback" do
    test "a single_choice and a scale answer are stored once, and a repeated submission stores nothing",
         %{conn: conn, program: program} do
      answers = %{usefulness: "very-useful", clarity: 4}

      assert conn |> feedback(program.slug, answers) |> json_response(200) == %{
               "already_recorded" => false
             }

      assert conn |> feedback(program.slug, %{usefulness: "not-useful"}) |> json_response(200) ==
               %{"already_recorded" => true}

      assert [%FeedbackResponse{program_id: program_id, answers: stored_answers}] =
               Repo.all(FeedbackResponse)

      assert program_id == program.id
      assert stored_answers == %{"usefulness" => "very-useful", "clarity" => 4}
      assert count(ParticipationMarker) == 1
    end

    test "free text answers 422 while FEEDBACK_FREE_TEXT is false",
         %{conn: conn, program: program} do
      put_insights(feedback_free_text: false)

      for answers <- [
            %{suggestion: "More examples, please."},
            %{usefulness: "very-useful", suggestion: "More examples, please."}
          ] do
        assert conn |> feedback(program.slug, answers) |> json_response(422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"answers" => ["invalid"]}
               }
      end

      assert stored() == [0, 0, 0, 0]
    end

    test "free text is accepted, trimmed and up to 2000 characters long when FEEDBACK_FREE_TEXT is true",
         %{conn: conn, program: program} do
      put_insights(feedback_free_text: true)

      answers = %{usefulness: "somewhat-useful", clarity: 3, suggestion: "  More examples.  "}

      assert conn |> feedback(program.slug, answers) |> json_response(200) == %{
               "already_recorded" => false
             }

      longest = String.duplicate("é", 2_000)
      other_conn = log_in_user(api_conn(), user_fixture())

      assert other_conn |> feedback(program.slug, %{suggestion: longest}) |> json_response(200) ==
               %{"already_recorded" => false}

      assert Repo.all(from f in FeedbackResponse, select: f.answers) |> Enum.sort() ==
               Enum.sort([
                 %{
                   "usefulness" => "somewhat-useful",
                   "clarity" => 3,
                   "suggestion" => "More examples."
                 },
                 %{"suggestion" => longest}
               ])
    end

    test "an answer that does not fit its question answers 422 with the member answers and stores nothing",
         %{conn: conn, program: program} do
      put_insights(feedback_free_text: true)

      cases = [
        %{suggestion: String.duplicate("a", 2_001)},
        %{suggestion: "before\u0000after"},
        %{suggestion: ""},
        %{suggestion: "   "},
        %{unknown: "very-useful"},
        %{clarity: 0},
        %{clarity: 6},
        %{clarity: "3"},
        %{clarity: 2.5},
        %{usefulness: "extremely-useful"},
        %{usefulness: 2},
        %{usefulness: "very-useful", clarity: 7},
        %{}
      ]

      # CastAndValidate rejects some answers before the context sees them, and
      # a failed oneOf names a reason per branch, so only the member is fixed.
      for answers <- cases do
        body = conn |> feedback(program.slug, answers) |> json_response(422)

        assert %{"error" => "validation_failed", "fields" => %{"answers" => [_ | _]} = fields} =
                 body,
               inspect(answers)

        assert Map.keys(fields) == ["answers"], inspect(answers)
      end

      assert stored() == [0, 0, 0, 0]

      assert conn |> feedback(program.slug, %{clarity: 5}) |> json_response(200) == %{
               "already_recorded" => false
             }
    end

    test "an unknown program and a program without a feedback station answer 404",
         %{conn: conn, program: program} do
      answers = %{usefulness: "very-useful"}

      assert conn |> feedback("no-such-program", answers) |> json_response(404) == %{
               "error" => "not_found"
             }

      {1, _rows} =
        Repo.delete_all(
          from s in Station, where: s.program_id == ^program.id and s.kind == :feedback
        )

      assert conn |> feedback(program.slug, answers) |> json_response(404) == %{
               "error" => "not_found"
             }

      assert stored() == [0, 0, 0, 0]
    end

    # The free text "3" fits both branches of the oneOf in FeedbackRequest,
    # because OpenApiSpex casts the string "3" to an integer as well.
    test "a free text that reads as a number from 1 to 5 is accepted when FEEDBACK_FREE_TEXT is true",
         %{conn: conn, program: program} do
      put_insights(feedback_free_text: true)

      assert conn |> feedback(program.slug, %{suggestion: "3"}) |> json_response(200) == %{
               "already_recorded" => false
             }

      assert [%FeedbackResponse{answers: %{"suggestion" => "3"}}] = Repo.all(FeedbackResponse)
    end

    test "an extra member answers 422", %{conn: conn, user: user, program: program} do
      body = %{program_slug: program.slug, answers: %{clarity: 4}, user_id: user.id}

      assert conn |> json_request(:post, "/api/feedback", body) |> json_response(422) == %{
               "error" => "validation_failed",
               "fields" => %{"user_id" => ["unexpected_field"]}
             }

      assert stored() == [0, 0, 0, 0]
    end
  end

  describe "GET /api/me/participation" do
    test "reports false, false and [] before the answers and true, true and the format id after them",
         %{conn: conn, program: program, spec: spec} do
      none = %{"self_assessment" => false, "feedback" => false, "format_votes" => []}
      assert participation(conn, program.slug) == none

      workshop = format!(program, "workshop")
      assert json_response(self_assess(conn, program.slug, "non-users"), 200)
      assert json_response(vote(conn, workshop.id), 200)
      assert json_response(feedback(conn, program.slug, %{usefulness: "very-useful"}), 200)

      body = participation(conn, program.slug)
      assert_schema(body, "Participation", spec)

      assert body == %{
               "self_assessment" => true,
               "feedback" => true,
               "format_votes" => [workshop.id]
             }

      other_conn = log_in_user(api_conn(), user_fixture())
      assert participation(other_conn, program.slug) == none
    end

    test "answers 404 for an unknown program and 422 without the parameter", %{conn: conn} do
      assert participation(conn, "no-such-program", 404) == %{"error" => "not_found"}

      assert conn |> json_request(:get, "/api/me/participation") |> json_response(422) == %{
               "error" => "validation_failed",
               "fields" => %{"program" => ["missing_field"]}
             }
    end
  end

  test "the anonymous rows carry no user reference and no answer carries a user id",
       %{conn: conn, user: user, program: program} do
    put_insights(feedback_free_text: true)
    workshop = format!(program, "workshop")

    responses = [
      self_assess(conn, program.slug, "daily-users"),
      vote(conn, workshop.id),
      feedback(conn, program.slug, %{usefulness: "very-useful", suggestion: "Shorter videos."}),
      json_request(conn, :get, "/api/me/participation?program=#{program.slug}")
    ]

    for response <- responses do
      assert response.status == 200
      refute response.resp_body =~ user.id
      refute response.resp_body =~ user.email
    end

    raw_id = Ecto.UUID.dump!(user.id)

    for table <- @anonymous_tables do
      %{columns: columns, rows: rows} = Repo.query!("SELECT * FROM #{table}")
      assert length(rows) == 1, table
      assert Enum.filter(columns, &(&1 =~ "user")) == [], table

      for value <- List.flatten(rows) do
        refute value in [raw_id, user.id], table
      end
    end
  end
end
