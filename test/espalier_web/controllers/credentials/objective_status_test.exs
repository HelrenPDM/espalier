defmodule EspalierWeb.Credentials.ObjectiveStatusTest do
  @moduledoc """
  Attendance certificates as evidence for learning objectives (task 0013,
  spec steps 10 and 16, the bullet "Objective status" of step 24 and the
  matching acceptance item; README section 7, domain rules 11 and 15).

  `Espalier.Credentials.attended_format_ids/2` reads only the certificates
  of the scope user (ASVS 8.2.2), so the objective status of
  `GET /api/me/progress` reflects only the learner's own certificates. A
  certificate for a format without `attendance_counts` evidences nothing.
  The demo pack runs with `TRACKING_DETAIL=minimal`.
  """
  # put_setting/2 changes :learning for the node.
  use EspalierWeb.ConnCase, async: false

  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Credentials

  @order ~w(m1-subject-next-word m1-subject-varying-answers m1-method-check-claims
            m1-self-own-responsibility m1-social-team-transparency m2-subject-prompt-parts
            m2-method-judge-output m2-method-release-check)

  @workshop_objectives ~w(m1-self-own-responsibility m1-social-team-transparency)

  setup do
    put_setting(:learning, tracking_detail: :minimal, insights_org_unit: false)
    program = publish_demo!()
    learner = user_fixture()
    facilitator = user_with_role_fixture(:facilitator)

    %{
      program: program,
      learner: learner,
      conn: log_in_user(api_conn(), learner),
      facilitator_conn: log_in_user(api_conn(), facilitator)
    }
  end

  defp progress(conn, program) do
    conn |> json_request(:get, "/api/me/progress?program=#{program.slug}") |> json_response(200)
  end

  defp statuses(body), do: Map.new(body["objectives"], &{&1["key"], &1["status"]})

  defp evidenced(body), do: for({key, "evidenced"} <- statuses(body), do: key) |> Enum.sort()

  defp attend(conn, format, users, held_on \\ Date.utc_today()) do
    body = %{user_ids: Enum.map(users, & &1.id), held_on: Date.to_iso8601(held_on)}

    conn
    |> json_request(:post, "/api/formats/#{format.id}/attendance", body)
    |> json_response(200)
  end

  defp assert_workshop_evidence(body) do
    assert Enum.map(body["objectives"], & &1["key"]) == @order
    assert evidenced(body) == @workshop_objectives

    for key <- @order -- @workshop_objectives do
      assert statuses(body)[key] == "open", key
    end
  end

  describe "attended_format_ids/2" do
    test "returns [] without a certificate", %{learner: learner, program: program} do
      assert Credentials.attended_format_ids(scope_for(learner), program) == []
    end

    test "returns the id of workshop once after two certificates with different held_on",
         %{learner: learner, program: program} do
      workshop = format!(program, "workshop")
      certificate_fixture(learner, workshop, ~D[2026-09-01])
      certificate_fixture(learner, workshop, ~D[2026-09-02])

      assert Credentials.attended_format_ids(scope_for(learner), program) == [workshop.id]
    end

    test "returns a format without attendance_counts as well",
         %{learner: learner, program: program} do
      help_desk = format!(program, "help-desk")
      refute help_desk.attendance_counts
      certificate_fixture(learner, help_desk, ~D[2026-09-01])

      assert Credentials.attended_format_ids(scope_for(learner), program) == [help_desk.id]
    end

    test "ignores the certificates of another user", %{learner: learner, program: program} do
      other = user_fixture()
      workshop = format!(program, "workshop")
      certificate_fixture(other, workshop, ~D[2026-09-01])
      certificate_fixture(other, format!(program, "help-desk"), ~D[2026-09-01])

      assert Credentials.attended_format_ids(scope_for(learner), program) == []
      assert workshop.id in Credentials.attended_format_ids(scope_for(other), program)
    end
  end

  describe "GET /api/me/progress after POST /api/formats/:id/attendance" do
    test "an enrolled learner sees the two objectives of workshop as evidenced and six open",
         %{conn: conn, facilitator_conn: facilitator_conn, learner: learner, program: program} do
      enroll!(scope_for(learner))

      before = progress(conn, program)
      assert before["enrollment"] != nil
      assert evidenced(before) == []

      assert attend(facilitator_conn, format!(program, "workshop"), [learner]) == %{
               "results" => [%{"user_id" => learner.id, "result" => "issued"}]
             }

      body = progress(conn, program)
      assert body["enrollment"] != nil
      assert_workshop_evidence(body)
    end

    test "a learner without an enrollment sees the same, with enrollment null",
         %{conn: conn, facilitator_conn: facilitator_conn, learner: learner, program: program} do
      assert %{"results" => [%{"result" => "issued"}]} =
               attend(facilitator_conn, format!(program, "workshop"), [learner])

      body = progress(conn, program)
      assert body["enrollment"] == nil
      assert_workshop_evidence(body)
    end

    test "a certificate for help-desk, whose attendance does not count, changes no status",
         %{conn: conn, facilitator_conn: facilitator_conn, learner: learner, program: program} do
      enroll!(scope_for(learner))
      help_desk = format!(program, "help-desk")

      assert %{"results" => [%{"result" => "issued"}]} =
               attend(facilitator_conn, help_desk, [learner])

      assert Credentials.attended_format_ids(scope_for(learner), program) == [help_desk.id]

      body = progress(conn, program)
      assert Enum.map(body["objectives"], & &1["key"]) == @order
      assert Enum.all?(body["objectives"], &(&1["status"] == "open"))
    end

    test "a certificate for workshop issued to another user leaves every objective of the learner open",
         %{conn: conn, facilitator_conn: facilitator_conn, learner: learner, program: program} do
      enroll!(scope_for(learner))
      other = user_fixture()

      assert %{"results" => [%{"user_id" => other_id, "result" => "issued"}]} =
               attend(facilitator_conn, format!(program, "workshop"), [other])

      assert other_id == other.id

      body = progress(conn, program)
      assert Enum.map(body["objectives"], & &1["key"]) == @order
      assert Enum.all?(body["objectives"], &(&1["status"] == "open"))

      other_conn = log_in_user(api_conn(), other)
      assert_workshop_evidence(progress(other_conn, program))
    end
  end
end
