defmodule EspalierWeb.Insights.RateLimitTest do
  @moduledoc """
  The per-user bucket `insights_write` of the three POST routes of task
  0014 (spec steps 4 and 13, ASVS 2.4.1): the third POST of one user within
  a minute answers 429 with `retry-after` and logs
  `excess_rate_limit_exceeded` with the bucket in `reason`, the three routes
  share the bucket, a denied request stores nothing, and another user is
  not limited.
  """
  # put_rate_limit/2 changes :rate_limits for the node.
  use EspalierWeb.ConnCase, async: false

  import Espalier.LearningFixtures

  alias Espalier.Insights.{FeedbackResponse, InterestVote, ParticipationMarker}
  alias Espalier.Repo

  setup do
    program = publish_demo!()
    user = user_fixture()
    %{program: program, user: user, conn: log_in_user(api_conn(), user)}
  end

  defp self_assessment(program),
    do: {"/api/self-assessments", %{program_slug: program.slug, segment_key: "daily-users"}}

  defp format_vote(program),
    do: {"/api/formats/#{format!(program, "workshop").id}/votes", %{choice: "would_use"}}

  defp feedback(program),
    do: {"/api/feedback", %{program_slug: program.slug, answers: %{usefulness: "very-useful"}}}

  defp post_json(conn, {path, body}), do: json_request(conn, :post, path, body)

  defp assert_rate_limited(conn) do
    assert json_response(conn, 429) == %{"error" => "rate_limited"}
    assert [retry_after] = get_resp_header(conn, "retry-after")
    assert String.to_integer(retry_after) in 1..60
  end

  test "the third self-assessment of one user within a minute answers 429, another user passes",
       %{conn: conn, program: program} do
    put_rate_limit(:insights_write, {:timer.minutes(1), 2})
    ref = attach_security_events()
    request = self_assessment(program)

    conn = post_json(conn, request)
    assert json_response(conn, 200) == %{"path" => "short", "already_recorded" => false}
    conn = post_json(conn, request)
    assert json_response(conn, 200) == %{"path" => "short", "already_recorded" => true}

    conn = post_json(conn, request)
    assert_rate_limited(conn)
    assert_receive {^ref, %{name: :excess_rate_limit_exceeded, reason: "insights_write"}}

    other = log_in_user(api_conn(), user_fixture())
    assert json_response(post_json(other, request), 200)["already_recorded"] == false
  end

  test "the three POST routes count in the one bucket insights_write, and a denied request stores nothing",
       %{conn: conn, program: program} do
    put_rate_limit(:insights_write, {:timer.minutes(1), 2})
    ref = attach_security_events()

    conn = post_json(conn, self_assessment(program))
    assert json_response(conn, 200)["already_recorded"] == false
    conn = post_json(conn, format_vote(program))
    assert json_response(conn, 200) == %{"already_recorded" => false}

    conn = post_json(conn, feedback(program))
    assert_rate_limited(conn)
    assert_receive {^ref, %{name: :excess_rate_limit_exceeded, reason: "insights_write"}}

    assert Repo.aggregate(FeedbackResponse, :count) == 0
    assert Repo.aggregate(ParticipationMarker, :count) == 2
  end

  test "after one POST of a user, each of the other two routes answers 429",
       %{conn: conn, program: program} do
    put_rate_limit(:insights_write, {:timer.minutes(1), 1})

    conn = post_json(conn, feedback(program))
    assert json_response(conn, 200) == %{"already_recorded" => false}

    for request <- [self_assessment(program), format_vote(program)] do
      conn |> post_json(request) |> assert_rate_limited()
    end

    assert Repo.aggregate(InterestVote, :count) == 0
    assert Repo.aggregate(ParticipationMarker, :count) == 1
  end
end
