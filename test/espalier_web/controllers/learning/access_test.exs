defmodule EspalierWeb.Learning.AccessTest do
  @moduledoc """
  Access rules of the learner routes (task 0009, ASVS 8.2.2, 8.2.3, 15.3.3,
  15.3.7 and 1.3.3): the `:authenticated` pipeline, the scope of the
  signed-in user, `additionalProperties: false` and the parameter locations
  of `CastAndValidate`.
  """
  use EspalierWeb.ConnCase, async: true

  import Espalier.LearningFixtures

  alias Espalier.Insights.ItemStat
  alias Espalier.Learning.{AssessmentAttempt, Enrollment, ItemResponse}
  alias Espalier.Repo

  setup do
    program = publish_demo!()
    user = user_fixture()
    %{program: program, user: user, conn: log_in_user(api_conn(), user)}
  end

  # Every learner route of step 13 with a body that passes CastAndValidate.
  defp routes(program) do
    item = item!(program, "m1-how-models-write")
    exam = assessment!(program)
    module = module!(program, 1)
    slug = program.slug

    [
      {:get, "/api/programs", nil},
      {:get, "/api/programs/#{slug}", nil},
      {:get, "/api/programs/#{slug}/glossary", nil},
      {:get, "/api/programs/#{slug}/handbook", nil},
      {:get, "/api/modules/#{module.id}", nil},
      {:post, "/api/modules/#{module.id}/completion", nil},
      {:post, "/api/enrollments", %{program_slug: slug, path: "short"}},
      {:patch, "/api/enrollments/#{Ecto.UUID.generate()}", %{path: "full"}},
      {:post, "/api/items/#{item.id}/responses", %{answer: correct_answer(item)}},
      {:post, "/api/assessments/#{exam.id}/attempts", %{answers: exam_answers(exam)}},
      {:get, "/api/me/progress?program=#{slug}", nil}
    ]
  end

  test "every learner route answers 401 without a session", %{program: program} do
    for {method, path, body} <- routes(program) do
      conn = json_request(api_conn(), method, path, body)
      assert json_response(conn, 401) == %{"error" => "unauthenticated"}, "#{method} #{path}"
    end
  end

  test "every learner route answers 403 enrollment_required with an enrollment session",
       %{program: program, user: user} do
    conn = log_in_user(api_conn(), user, %{strength: :enrollment, auth_methods: [:email_code]})

    for {method, path, body} <- routes(program) do
      response = json_request(conn, method, path, body)

      assert json_response(response, 403) == %{"error" => "enrollment_required"},
             "#{method} #{path}"
    end

    assert Repo.aggregate(Enrollment, :count) == 0
  end

  test "PATCH /api/enrollments/:id with the enrollment of another user answers 404",
       %{conn: conn} do
    other = scope_for(user_fixture())
    enrollment = enroll!(other)

    conn = json_request(conn, :patch, "/api/enrollments/#{enrollment.id}", %{path: "full"})
    assert json_response(conn, 404) == %{"error" => "not_found"}
    assert %Enrollment{path: :short, path_chosen_manually: false} = Repo.reload!(enrollment)
  end

  describe "a body with a member the server sets" do
    test "answers 422 on POST /api/enrollments and creates no row", %{
      conn: conn,
      program: program
    } do
      for {member, value} <- [{"user_id", Ecto.UUID.generate()}, {"path_chosen_manually", true}] do
        body = %{"program_slug" => program.slug, "path" => "short"} |> Map.put(member, value)
        response = json_request(conn, :post, "/api/enrollments", body)

        assert json_response(response, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{member => ["unexpected_field"]}
               }
      end

      assert Repo.aggregate(Enrollment, :count) == 0
    end

    test "answers 422 on PATCH /api/enrollments/:id and changes nothing", %{
      conn: conn,
      user: user
    } do
      enrollment = enroll!(scope_for(user))

      for {member, value} <- [{"path_chosen_manually", true}, {"user_id", Ecto.UUID.generate()}] do
        body = %{"path" => "full"} |> Map.put(member, value)
        response = json_request(conn, :patch, "/api/enrollments/#{enrollment.id}", body)
        assert json_response(response, 422)["fields"] == %{member => ["unexpected_field"]}
      end

      assert Repo.reload!(enrollment) == enrollment
    end

    test "answers 422 on POST /api/assessments/:id/attempts and stores no attempt",
         %{conn: conn, user: user, program: program} do
      enroll!(scope_for(user))
      exam = assessment!(program)
      body = %{"answers" => exam_answers(exam), "outcome" => "passed"}

      response = json_request(conn, :post, "/api/assessments/#{exam.id}/attempts", body)
      assert json_response(response, 422)["fields"] == %{"outcome" => ["unexpected_field"]}
      assert Repo.aggregate(AssessmentAttempt, :count) == 0
    end

    test "answers 422 on POST /api/items/:id/responses and counts nothing",
         %{conn: conn, user: user, program: program} do
      enroll!(scope_for(user))
      item = item!(program, "m1-how-models-write")

      for body <- [
            %{"answer" => correct_answer(item), "user_id" => Ecto.UUID.generate()},
            %{"answer" => Map.put(correct_answer(item), "correct", true)}
          ] do
        response = json_request(conn, :post, "/api/items/#{item.id}/responses", body)
        assert %{"error" => "validation_failed"} = json_response(response, 422)
      end

      assert Repo.aggregate(ItemStat, :count) == 0
    end

    test "answers 422 on POST /api/modules/:id/completion", %{conn: conn, program: program} do
      module = module!(program, 2)
      body = %{"completed_at" => "2026-01-01T00:00:00Z"}
      response = json_request(conn, :post, "/api/modules/#{module.id}/completion", body)
      assert json_response(response, 422)["fields"] == %{"completed_at" => ["unexpected_field"]}
    end
  end

  test "a body with the member _json answers 422 and changes nothing",
       %{conn: conn, user: user, program: program} do
    enrollment = enroll!(scope_for(user))
    item = item!(program, "m1-how-models-write")
    exam = assessment!(program)

    for {method, path, inner} <- [
          {:post, "/api/enrollments", %{program_slug: program.slug, path: "full"}},
          {:patch, "/api/enrollments/#{enrollment.id}", %{path: "full"}},
          {:post, "/api/items/#{item.id}/responses", %{answer: correct_answer(item)}},
          {:post, "/api/assessments/#{exam.id}/attempts", %{answers: exam_answers(exam)}},
          {:post, "/api/modules/#{module!(program, 2).id}/completion", %{}}
        ],
        body <- [%{"_json" => inner}, %{"_json" => inner, "user_id" => Ecto.UUID.generate()}] do
      response = json_request(conn, method, path, body)

      assert json_response(response, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"body" => ["invalid_type"]}
             },
             "#{method} #{path}"
    end

    response = json_request(conn, :post, "/api/enrollments", [%{path: "full"}])
    assert json_response(response, 422)["fields"] == %{"body" => ["invalid_type"]}

    assert Repo.reload!(enrollment) == enrollment
    assert Repo.aggregate(ItemStat, :count) == 0
    assert Repo.aggregate(AssessmentAttempt, :count) == 0
    assert Repo.aggregate(Espalier.Learning.ModuleCompletion, :count) == 0
  end

  test "a key with a trailing line break answers 422", %{conn: conn, program: program} do
    body = %{program_slug: program.slug <> "\n", path: "short"}
    response = json_request(conn, :post, "/api/enrollments", body)
    assert json_response(response, 422)["fields"] == %{"program_slug" => ["invalid_format"]}
    assert Repo.aggregate(Enrollment, :count) == 0
  end

  test "an archived item, an archived exam and an archived program answer 404",
       %{conn: conn, user: user, program: program} do
    enroll!(scope_for(user))
    now = DateTime.utc_now(:second)
    item = item!(program, "m1-how-models-write")
    exam = assessment!(program)
    item |> Ecto.Changeset.change(archived_at: now) |> Repo.update!()
    exam |> Ecto.Changeset.change(archived_at: now) |> Repo.update!()

    response =
      json_request(conn, :post, "/api/items/#{item.id}/responses", %{answer: correct_answer(item)})

    assert json_response(response, 404) == %{"error" => "not_found"}

    response =
      json_request(conn, :post, "/api/assessments/#{exam.id}/attempts", %{
        answers: exam_answers(exam)
      })

    assert json_response(response, 404) == %{"error" => "not_found"}

    module =
      conn |> json_request(:get, "/api/modules/#{module!(program, 1).id}") |> json_response(200)

    assert module["exams"] == []
    refute "m1-how-models-write" in Enum.map(module["practice_items"], & &1["key"])

    program |> Ecto.Changeset.change(status: :archived) |> Repo.update!()

    assert conn |> json_request(:get, "/api/programs/#{program.slug}") |> json_response(404) ==
             %{"error" => "not_found"}

    other = item!(program, "m1-fluent-figure")

    response =
      json_request(conn, :post, "/api/items/#{other.id}/responses", %{
        answer: correct_answer(other)
      })

    assert json_response(response, 404) == %{"error" => "not_found"}
    assert Repo.aggregate(ItemStat, :count) == 0
    assert Repo.aggregate(AssessmentAttempt, :count) == 0
  end

  test "PATCH /api/enrollments/:id reads path from the body only", %{conn: conn, user: user} do
    enrollment = enroll!(scope_for(user))

    response = json_request(conn, :patch, "/api/enrollments/#{enrollment.id}?path=full")
    assert %{"error" => "validation_failed"} = json_response(response, 422)

    response = json_request(conn, :patch, "/api/enrollments/#{enrollment.id}?path=full", %{})
    assert json_response(response, 422)["fields"] == %{"path" => ["missing_field"]}

    assert Repo.reload!(enrollment).path == :short
  end

  test "a string above its maxLength or outside its set answers 422", %{conn: conn} do
    long = String.duplicate("a", 256)

    response = json_request(conn, :post, "/api/enrollments", %{program_slug: long, path: "short"})
    assert json_response(response, 422)["fields"] == %{"program_slug" => ["max_length"]}

    response =
      json_request(conn, :post, "/api/enrollments", %{program_slug: "demo", path: "medium"})

    assert json_response(response, 422)["fields"] == %{"path" => ["invalid_enum"]}

    response = json_request(conn, :get, "/api/programs/#{String.duplicate("a", 256)}")
    assert json_response(response, 422)["fields"] == %{"slug" => ["max_length"]}
  end

  test "an id that is no UUID answers 422", %{conn: conn} do
    response = json_request(conn, :get, "/api/modules/not-a-uuid")
    assert json_response(response, 422)["fields"] == %{"id" => ["invalid_format"]}
  end

  test "an exam item on POST /api/items/:id/responses answers 404",
       %{conn: conn, user: user, program: program} do
    enroll!(scope_for(user))
    item = item!(program, "m1-exam-check-claims")

    response =
      json_request(conn, :post, "/api/items/#{item.id}/responses", %{answer: correct_answer(item)})

    assert json_response(response, 404) == %{"error" => "not_found"}
    assert Repo.aggregate(ItemStat, :count) == 0
  end

  test "a draft program and an archived module answer 404", %{conn: conn, program: program} do
    module = module!(program, 1)
    module |> Ecto.Changeset.change(archived_at: DateTime.utc_now(:second)) |> Repo.update!()

    assert conn |> json_request(:get, "/api/modules/#{module.id}") |> json_response(404) ==
             %{"error" => "not_found"}

    response = json_request(conn, :post, "/api/modules/#{module.id}/completion")
    assert json_response(response, 404) == %{"error" => "not_found"}

    program |> Ecto.Changeset.change(status: :draft) |> Repo.update!()

    for path <- [
          "/api/programs/#{program.slug}",
          "/api/programs/#{program.slug}/glossary",
          "/api/programs/#{program.slug}/handbook",
          "/api/me/progress?program=#{program.slug}",
          "/api/modules/#{module!(program, 2).id}"
        ] do
      assert conn |> json_request(:get, path) |> json_response(404) == %{"error" => "not_found"},
             path
    end

    assert conn |> json_request(:get, "/api/programs") |> json_response(200) == %{
             "programs" => []
           }

    response =
      json_request(conn, :post, "/api/enrollments", %{program_slug: program.slug, path: "short"})

    assert json_response(response, 404) == %{"error" => "not_found"}
  end

  test "writes without an enrollment answer 409 not_enrolled", %{conn: conn, program: program} do
    item = item!(program, "m1-how-models-write")
    exam = assessment!(program)

    for {path, body} <- [
          {"/api/items/#{item.id}/responses", %{answer: correct_answer(item)}},
          {"/api/assessments/#{exam.id}/attempts", %{answers: exam_answers(exam)}},
          {"/api/modules/#{module!(program, 1).id}/completion", nil}
        ] do
      assert conn |> json_request(:post, path, body) |> json_response(409) ==
               %{"error" => "not_enrolled"},
             path
    end
  end

  test "two POST /api/enrollments calls leave one row and keep a manual path",
       %{conn: conn, program: program} do
    body = %{program_slug: program.slug, path: "short"}
    conn = json_request(conn, :post, "/api/enrollments", body)
    %{"id" => id} = json_response(conn, 201)

    conn = json_request(conn, :patch, "/api/enrollments/#{id}", %{path: "full"})
    assert %{"path" => "full", "path_chosen_manually" => true} = json_response(conn, 200)

    conn = json_request(conn, :post, "/api/enrollments", body)

    assert %{"id" => ^id, "path" => "full", "path_chosen_manually" => true} =
             json_response(conn, 200)

    assert Repo.aggregate(Enrollment, :count) == 1
  end

  test "two answers by users without an org unit leave one item_stats row with attempts 2",
       %{conn: conn, user: user, program: program} do
    item = item!(program, "m1-how-models-write")
    other = user_fixture()

    for {conn, user} <- [{conn, user}, {log_in_user(api_conn(), other), other}] do
      enroll!(scope_for(user))

      response =
        json_request(conn, :post, "/api/items/#{item.id}/responses", %{
          answer: correct_answer(item)
        })

      assert json_response(response, 200)["correct"] == true
    end

    assert [%ItemStat{attempts: 2, correct: 2, org_unit: nil}] = Repo.all(ItemStat)
    assert Repo.aggregate(ItemResponse, :count) == 0
  end

  test "an answer that does not fit the item answers 422", %{
    conn: conn,
    user: user,
    program: program
  } do
    enroll!(scope_for(user))
    item = item!(program, "m1-how-models-write")

    response =
      json_request(conn, :post, "/api/items/#{item.id}/responses", %{answer: %{checks: ["x"]}})

    assert json_response(response, 422) == %{
             "error" => "validation_failed",
             "fields" => %{"answer" => ["invalid"]}
           }
  end

  test "exam answers with a missing item answer 422 incomplete",
       %{conn: conn, user: user, program: program} do
    enroll!(scope_for(user))
    exam = assessment!(program)
    answers = exam |> exam_answers() |> Enum.drop(1) |> Map.new()

    response =
      json_request(conn, :post, "/api/assessments/#{exam.id}/attempts", %{answers: answers})

    assert json_response(response, 422) == %{
             "error" => "validation_failed",
             "fields" => %{"answers" => ["incomplete"]}
           }
  end

  test "POST /api/modules/:id/completion answers 409 assessments_open before and 200 after a passed exam",
       %{conn: conn, user: user, program: program} do
    enroll!(scope_for(user))
    module = module!(program, 1)
    exam = assessment!(program)

    conn = json_request(conn, :post, "/api/modules/#{module.id}/completion")

    assert json_response(conn, 409) == %{
             "error" => "assessments_open",
             "assessments" => [%{"id" => exam.id, "key" => exam.key, "title" => exam.title}]
           }

    conn =
      json_request(conn, :post, "/api/assessments/#{exam.id}/attempts", %{
        answers: exam_answers(exam)
      })

    assert json_response(conn, 201)["outcome"] == "passed"

    conn = json_request(conn, :post, "/api/modules/#{module.id}/completion")
    assert %{"module_id" => module_id, "completed_at" => completed_at} = json_response(conn, 200)
    assert module_id == module.id

    conn = json_request(conn, :post, "/api/modules/#{module.id}/completion")
    assert json_response(conn, 200) == %{"module_id" => module_id, "completed_at" => completed_at}
  end

  test "the demo exam returns failed_core, passed and failed_errors",
       %{conn: conn, user: user, program: program} do
    enroll!(scope_for(user))
    exam = assessment!(program)
    path = "/api/assessments/#{exam.id}/attempts"

    for {wrong, outcome, wrong_count, core_failed} <- [
          {["m1-exam-check-claims"], "failed_core", 1, true},
          {["m1-exam-next-word"], "passed", 1, false},
          {["m1-exam-next-word", "m1-exam-varying-answers"], "failed_errors", 2, false}
        ] do
      response = json_request(conn, :post, path, %{answers: exam_answers(exam, wrong)})

      assert %{
               "outcome" => ^outcome,
               "wrong_count" => ^wrong_count,
               "core_failed" => ^core_failed
             } =
               json_response(response, 201)
    end
  end
end
