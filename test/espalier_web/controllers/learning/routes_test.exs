defmodule EspalierWeb.Learning.RoutesTest do
  @moduledoc """
  One check per learner route: the JSON body matches the schema of its
  operation in `EspalierWeb.ApiSpec` (`OpenApiSpex.TestAssertions`). The
  response schemas set `additionalProperties: false`, so an undocumented
  member fails the check.
  """
  use EspalierWeb.ConnCase, async: true

  import Espalier.LearningFixtures
  import OpenApiSpex.TestAssertions

  alias EspalierWeb.ApiSpec

  setup do
    program = publish_demo!()
    user = user_fixture()
    %{program: program, user: user, conn: log_in_user(api_conn(), user), spec: ApiSpec.spec()}
  end

  defp enum(spec, schema, path) do
    spec.components.schemas
    |> Map.fetch!(schema)
    |> get_in([Access.key!(:properties) | Enum.map(path, &Access.key!/1)])
    |> Map.fetch!(:enum)
    |> Enum.sort()
  end

  test "the objective schemas list the allowed values as enums", %{spec: spec} do
    assert enum(spec, "ObjectiveView", [:area]) == ~w(method self social subject)
    assert enum(spec, "ObjectiveView", [:depth]) == ~w(apply judge know)
    assert enum(spec, "ObjectiveView", [:phase]) == ~w(anchor apply orient understand update)
    assert enum(spec, "ObjectiveEvidence", [:kind]) == ~w(format item)
    assert enum(spec, "ObjectiveProgress", [:status]) == ~w(evidenced open)

    assert spec.components.schemas["CompanionFormatView"].properties.phases.items.enum ==
             ~w(orient understand apply anchor update)
  end

  test "GET /api/programs", %{conn: conn, spec: spec} do
    body = conn |> json_request(:get, "/api/programs") |> json_response(200)
    assert_schema(body, "ProgramList", spec)
    assert [%{"slug" => "ai-assistant-basics-demo"}] = body["programs"]
  end

  test "GET /api/programs/:slug", %{conn: conn, program: program, spec: spec} do
    body = conn |> json_request(:get, "/api/programs/#{program.slug}") |> json_response(200)
    assert_schema(body, "ProgramView", spec)

    assert Enum.map(body["stations"], & &1["kind"]) ==
             ~w(self_assessment overview module module credential companion_formats feedback)

    assert Enum.map(body["companion_formats"], & &1["key"]) == ~w(handbook workshop help-desk)
    assert Enum.all?(body["companion_formats"], &assert_schema(&1, "CompanionFormatView", spec))

    assert [%{"question" => question}] =
             Enum.filter(body["stations"], &(&1["kind"] == "self_assessment"))

    assert is_binary(question)

    assert [%{"questions" => [_, _, _]}] =
             Enum.filter(body["stations"], &(&1["kind"] == "feedback"))
  end

  test "GET /api/modules/:id", %{conn: conn, program: program, spec: spec} do
    for number <- [1, 2] do
      module = module!(program, number)
      body = conn |> json_request(:get, "/api/modules/#{module.id}") |> json_response(200)
      assert_schema(body, "ModuleView", spec)
      assert body["program_slug"] == program.slug
      assert Enum.all?(body["objectives"], &assert_schema(&1, "ObjectiveView", spec))

      for objective <- body["objectives"], evidence <- objective["evidence"] do
        assert_schema(evidence, "ObjectiveEvidence", spec)
      end
    end
  end

  test "GET /api/modules/:id lists exams with their items and practice items without them",
       %{conn: conn, program: program} do
    body =
      conn |> json_request(:get, "/api/modules/#{module!(program, 1).id}") |> json_response(200)

    assert [%{"key" => "module-1-exam", "max_wrong" => 1, "counts_for_credential" => true} = exam] =
             body["exams"]

    assert Enum.map(exam["items"], & &1["key"]) ==
             ~w(m1-exam-next-word m1-exam-varying-answers m1-exam-check-claims m1-exam-confident-answer)

    assert Enum.map(body["practice_items"], & &1["key"]) ==
             ~w(m1-how-models-write m1-fluent-figure m1-why-answers-vary m1-before-use m1-first-task-poll)

    assert Enum.all?(exam["items"], &(&1["lesson_id"] == nil))
    assert Enum.all?(body["practice_items"], &is_binary(&1["lesson_id"]))
  end

  test "GET /api/programs/:slug/glossary", %{conn: conn, program: program, spec: spec} do
    body =
      conn |> json_request(:get, "/api/programs/#{program.slug}/glossary") |> json_response(200)

    assert_schema(body, "Glossary", spec)
    assert length(body["terms"]) == 8
    assert body["terms"] == Enum.sort_by(body["terms"], & &1["slug"])
  end

  test "GET /api/programs/:slug/handbook", %{conn: conn, program: program, spec: spec} do
    body =
      conn |> json_request(:get, "/api/programs/#{program.slug}/handbook") |> json_response(200)

    assert_schema(body, "Handbook", spec)
    assert Enum.map(body["modules"], &{&1["number"], length(&1["rules"])}) == [{1, 6}, {2, 4}]
    assert body["placeholders"] == ["input-rules"]
  end

  test "POST /api/enrollments and PATCH /api/enrollments/:id",
       %{conn: conn, program: program, spec: spec} do
    body = %{program_slug: program.slug, path: "short"}
    conn = json_request(conn, :post, "/api/enrollments", body)
    created = json_response(conn, 201)
    assert_schema(created, "EnrollmentView", spec)

    conn = json_request(conn, :post, "/api/enrollments", %{body | path: "full"})
    existing = json_response(conn, 200)
    assert_schema(existing, "EnrollmentView", spec)
    assert existing["path"] == "full"

    conn = json_request(conn, :patch, "/api/enrollments/#{created["id"]}", %{path: "short"})
    patched = json_response(conn, 200)
    assert_schema(patched, "EnrollmentView", spec)
    assert %{"path" => "short", "path_chosen_manually" => true} = patched
  end

  test "POST /api/items/:id/responses", %{conn: conn, user: user, program: program, spec: spec} do
    enroll!(scope_for(user))

    for key <- ~w(m1-how-models-write m1-why-answers-vary m1-first-task-poll m2-prompt-builder
                  m2-judge-drafts m2-release-drill) do
      item = item!(program, key)

      for answer <- [
            correct_answer(item) | if(item.kind == :poll, do: [], else: [wrong_answer(item)])
          ] do
        response = json_request(conn, :post, "/api/items/#{item.id}/responses", %{answer: answer})
        body = json_response(response, 200)
        assert_schema(body, "ItemResult", spec)
        assert body["item_id"] == item.id
      end
    end
  end

  test "POST /api/assessments/:id/attempts",
       %{conn: conn, user: user, program: program, spec: spec} do
    enroll!(scope_for(user))
    exam = assessment!(program)
    path = "/api/assessments/#{exam.id}/attempts"

    body = conn |> json_request(:post, path, %{answers: exam_answers(exam)}) |> json_response(201)
    assert_schema(body, "AttemptResult", spec)
    assert %{"number" => 1, "outcome" => "passed", "wrong_count" => 0} = body
    assert Enum.map(body["results"], & &1["item_id"]) == Enum.map(exam_items!(exam), & &1.id)
  end

  test "POST /api/modules/:id/completion", %{conn: conn, user: user, program: program, spec: spec} do
    enroll!(scope_for(user))
    module = module!(program, 1)
    path = "/api/modules/#{module.id}/completion"

    open = conn |> json_request(:post, path) |> json_response(409)
    assert_schema(open, "AssessmentsOpenError", spec)

    exam = assessment!(program)

    json_request(conn, :post, "/api/assessments/#{exam.id}/attempts", %{
      answers: exam_answers(exam)
    })

    body = conn |> json_request(:post, path) |> json_response(200)
    assert_schema(body, "ModuleCompletionView", spec)
  end

  test "GET /api/me/progress", %{conn: conn, user: user, program: program, spec: spec} do
    path = "/api/me/progress?program=#{program.slug}"

    body = conn |> json_request(:get, path) |> json_response(200)
    assert_schema(body, "Progress", spec)
    assert body["enrollment"] == nil

    enroll!(scope_for(user))
    body = conn |> json_request(:get, path) |> json_response(200)
    assert_schema(body, "Progress", spec)
    assert Enum.all?(body["objectives"], &assert_schema(&1, "ObjectiveProgress", spec))
  end

  test "GET /api/me/progress needs the query parameter program", %{conn: conn, program: program} do
    response = json_request(conn, :get, "/api/me/progress")
    assert json_response(response, 422)["fields"] == %{"program" => ["missing_field"]}

    response = json_request(conn, :get, "/api/me/progress?program=#{program.slug}&user_id=x")
    assert json_response(response, 422)["fields"] == %{"user_id" => ["unexpected_field"]}
  end
end
