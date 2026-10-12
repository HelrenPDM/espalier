defmodule EspalierWeb.Insights.SessionFlagsTest do
  @moduledoc """
  Task 0014, step 11: the session payload of `GET /api/session` carries the
  flags `test_notes` and `feedback_free_text` from
  `config :espalier, :insights` (step 10), false by default and true when
  the settings are set, for a signed-out client and a signed-in learner, and
  the payload matches the schema `SessionPayload` of its operation.
  """
  # put_insights/1 and put_setting/2 change the settings of the node.
  use EspalierWeb.ConnCase, async: false

  import Espalier.InsightsFixtures, only: [put_insights: 1]
  import OpenApiSpex.TestAssertions

  alias EspalierWeb.ApiSpec

  setup do
    %{spec: ApiSpec.spec()}
  end

  defp session_flags(conn, spec) do
    body = conn |> get("/api/session") |> json_response(200)
    assert_schema(body, "SessionPayload", spec)
    body["flags"]
  end

  defp signed_in(user), do: log_in_user(api_conn(), user)

  test "the schema SessionPayload requires both flags as booleans", %{spec: spec} do
    flags = spec.components.schemas["SessionPayload"].properties.flags

    for name <- [:test_notes, :feedback_free_text] do
      assert name in flags.required
      assert flags.properties[name].type == :boolean
    end

    assert flags.additionalProperties == false
  end

  test "both flags are false by default", %{conn: conn, spec: spec} do
    assert %{"test_notes" => false, "feedback_free_text" => false} = session_flags(conn, spec)

    assert %{"test_notes" => false, "feedback_free_text" => false} =
             session_flags(signed_in(user_fixture()), spec)
  end

  test "both flags are false when config :espalier, :insights names neither", %{
    conn: conn,
    spec: spec
  } do
    put_setting(:insights, [])

    assert %{"test_notes" => false, "feedback_free_text" => false} = session_flags(conn, spec)
  end

  test "both flags are true when config :espalier, :insights sets them", %{
    conn: conn,
    spec: spec
  } do
    put_insights(test_notes: true, feedback_free_text: true)

    assert %{"test_notes" => true, "feedback_free_text" => true} = session_flags(conn, spec)

    assert %{"test_notes" => true, "feedback_free_text" => true} =
             session_flags(signed_in(user_fixture()), spec)
  end

  test "each flag follows its own setting", %{conn: conn, spec: spec} do
    put_insights(test_notes: true, feedback_free_text: false)
    assert %{"test_notes" => true, "feedback_free_text" => false} = session_flags(conn, spec)

    put_insights(test_notes: false, feedback_free_text: true)

    assert %{"test_notes" => false, "feedback_free_text" => true} =
             session_flags(api_conn(), spec)
  end
end
