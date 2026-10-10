defmodule EspalierWeb.Learning.ProgressTest do
  @moduledoc """
  The objective status of `GET /api/me/progress` with the demo pack (README
  section 7, domain rule 15). Evidence through attendance is covered by
  `Espalier.Learning.ObjectiveStatus.derive/2`; the route test with an
  attendance certificate belongs to task 0013.
  """
  # put_setting/2 changes :learning for the node.
  use EspalierWeb.ConnCase, async: false

  import Espalier.LearningFixtures

  @order ~w(m1-subject-next-word m1-subject-varying-answers m1-method-check-claims
            m1-self-own-responsibility m1-social-team-transparency m2-subject-prompt-parts
            m2-method-judge-output m2-method-release-check)

  @exam_objectives ~w(m1-subject-next-word m1-subject-varying-answers m1-method-check-claims)

  setup do
    put_setting(:learning, tracking_detail: :minimal, insights_org_unit: false)
    program = publish_demo!()
    user = user_fixture()
    %{program: program, user: user, conn: log_in_user(api_conn(), user)}
  end

  defp progress(conn, program) do
    conn |> json_request(:get, "/api/me/progress?program=#{program.slug}") |> json_response(200)
  end

  defp statuses(body), do: Map.new(body["objectives"], &{&1["key"], &1["status"]})

  defp evidenced(body), do: for({key, "evidenced"} <- statuses(body), do: key) |> Enum.sort()

  defp attempt(conn, exam, wrong \\ []) do
    path = "/api/assessments/#{exam.id}/attempts"
    conn |> json_request(:post, path, %{answers: exam_answers(exam, wrong)}) |> json_response(201)
  end

  defp answer(conn, item, answer) do
    path = "/api/items/#{item.id}/responses"
    conn |> json_request(:post, path, %{answer: answer}) |> json_response(200)
  end

  test "without an enrollment, the answer carries enrollment null and eight open objectives",
       %{conn: conn, program: program} do
    body = progress(conn, program)

    assert body["enrollment"] == nil
    assert body["completed_module_ids"] == []
    assert body["exams"] == []
    assert Enum.map(body["objectives"], & &1["key"]) == @order
    assert Enum.all?(body["objectives"], &(&1["status"] == "open"))
    refute Map.has_key?(body, "answered_item_ids")
  end

  test "after the enrollment all eight objectives are open, in module and position order",
       %{conn: conn, program: program} do
    conn =
      json_request(conn, :post, "/api/enrollments", %{program_slug: program.slug, path: "full"})

    assert json_response(conn, 201)

    body = progress(conn, program)
    assert %{"path" => "full", "path_chosen_manually" => false} = body["enrollment"]
    assert Enum.map(body["objectives"], & &1["key"]) == @order
    assert evidenced(body) == []
  end

  test "a failed attempt leaves them open, a passed attempt evidences the exam objectives",
       %{conn: conn, user: user, program: program} do
    enroll!(scope_for(user))
    exam = assessment!(program)

    assert %{"outcome" => "failed_core"} = attempt(conn, exam, ["m1-exam-check-claims"])
    assert evidenced(progress(conn, program)) == []

    assert %{"outcome" => "passed"} = attempt(conn, exam)
    body = progress(conn, program)
    assert evidenced(body) == Enum.sort(@exam_objectives)
    assert body["exams"] == [%{"assessment_id" => exam.id, "outcome" => "passed"}]
  end

  test "a passed attempt of another user leaves every objective of the scope user open",
       %{conn: conn, user: user, program: program} do
    enroll!(scope_for(user))
    other = user_fixture()
    enroll!(scope_for(other))

    other_conn = log_in_user(api_conn(), other)
    assert %{"outcome" => "passed"} = attempt(other_conn, assessment!(program))

    assert evidenced(progress(conn, program)) == []
    assert evidenced(progress(other_conn, program)) == Enum.sort(@exam_objectives)
  end

  test "with standard, a correct checklist drill evidences m2-method-release-check",
       %{conn: conn, user: user, program: program} do
    put_setting(:learning, tracking_detail: :standard, insights_org_unit: false)
    enroll!(scope_for(user))
    drill = item!(program, "m2-release-drill")

    assert %{"correct" => false} = answer(conn, drill, wrong_answer(drill))
    body = progress(conn, program)
    assert statuses(body)["m2-method-release-check"] == "open"
    assert body["answered_item_ids"] == [drill.id]

    assert %{"correct" => true} = answer(conn, drill, correct_answer(drill))
    assert evidenced(progress(conn, program)) == ["m2-method-release-check"]
  end

  test "with minimal, a correct checklist drill leaves m2-method-release-check open",
       %{conn: conn, user: user, program: program} do
    enroll!(scope_for(user))
    drill = item!(program, "m2-release-drill")

    assert %{"correct" => true} = answer(conn, drill, correct_answer(drill))
    body = progress(conn, program)
    assert statuses(body)["m2-method-release-check"] == "open"
    refute Map.has_key?(body, "answered_item_ids")
  end
end
