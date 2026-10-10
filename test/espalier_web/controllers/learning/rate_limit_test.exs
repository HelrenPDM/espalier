defmodule EspalierWeb.Learning.RateLimitTest do
  @moduledoc """
  The per-user buckets of the learner write routes (task 0009, ASVS 2.4.1):
  `learner_write` and `assessment_attempt`.
  """
  # put_rate_limit/2 changes :rate_limits for the node.
  use EspalierWeb.ConnCase, async: false

  import Espalier.LearningFixtures

  setup do
    program = publish_demo!()
    user = user_fixture()
    enroll!(scope_for(user))
    %{program: program, user: user, conn: log_in_user(api_conn(), user)}
  end

  test "the third answer of one user within a minute answers 429, another user passes",
       %{conn: conn, program: program} do
    put_rate_limit(:learner_write, {:timer.minutes(1), 2})
    ref = attach_security_events()

    item = item!(program, "m1-how-models-write")
    path = "/api/items/#{item.id}/responses"
    body = %{answer: correct_answer(item)}

    conn = json_request(conn, :post, path, body)
    assert json_response(conn, 200)
    conn = json_request(conn, :post, path, body)
    assert json_response(conn, 200)

    conn = json_request(conn, :post, path, body)
    assert json_response(conn, 429) == %{"error" => "rate_limited"}
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) in 1..60

    assert_receive {^ref, %{name: :excess_rate_limit_exceeded, reason: "learner_write"}}

    other = user_fixture()
    enroll!(scope_for(other))
    response = json_request(log_in_user(api_conn(), other), :post, path, body)
    assert json_response(response, 200)
  end

  test "every learner write route counts in learner_write", %{conn: conn, program: program} do
    put_rate_limit(:learner_write, {:timer.minutes(1), 1})

    conn =
      json_request(conn, :post, "/api/enrollments", %{program_slug: program.slug, path: "short"})

    assert json_response(conn, 200)

    for {method, path, body} <- [
          {:post, "/api/enrollments", %{program_slug: program.slug, path: "short"}},
          {:patch, "/api/enrollments/#{Ecto.UUID.generate()}", %{path: "full"}},
          {:post, "/api/modules/#{module!(program, 2).id}/completion", nil}
        ] do
      response = json_request(conn, method, path, body)
      assert json_response(response, 429) == %{"error" => "rate_limited"}, "#{method} #{path}"
    end
  end

  test "the second exam attempt of one user answers 429", %{conn: conn, program: program} do
    put_rate_limit(:assessment_attempt, {:timer.minutes(10), 1})
    ref = attach_security_events()

    exam = assessment!(program)
    path = "/api/assessments/#{exam.id}/attempts"
    body = %{answers: exam_answers(exam)}

    conn = json_request(conn, :post, path, body)
    assert json_response(conn, 201)

    conn = json_request(conn, :post, path, body)
    assert json_response(conn, 429) == %{"error" => "rate_limited"}
    assert [_retry_after] = get_resp_header(conn, "retry-after")
    assert_receive {^ref, %{name: :excess_rate_limit_exceeded, reason: "assessment_attempt"}}
  end
end
