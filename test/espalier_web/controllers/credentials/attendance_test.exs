defmodule EspalierWeb.Credentials.AttendanceTest do
  @moduledoc """
  Attendance and the user lookup of facilitators (task 0013, spec steps 16
  and 24, bullet "Routes"): `POST /api/formats/:id/attendance` and
  `POST /api/facilitator/user-lookups` require the role `facilitator` and
  log a rejected role as `authz_fail` (ASVS 8.2.1 and 16.3.2). Attendance
  is accepted only for a format of a published program and a day no later
  than today (ASVS 2.2.3), answers `issued`, `exists` or `not_found` per
  distinct user id in request order, writes each certificate for the
  learner with the facilitator in `issued_by_id`, and records
  `attendance.issued` per new certificate. The lookup takes the exact
  address in the body (ASVS 14.2.1) and returns id, display name and org
  unit only. Both routes reject an extra member (ASVS 15.3.3), answer with
  `cache-control: no-store` (ASVS 14.2.2 and 14.3.2), and the log holds no
  looked-up address (ASVS 16.2.5).
  """
  # Logger.put_module_level/2 changes the level of Phoenix.Logger for the
  # node.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import ExUnit.CaptureLog
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Audit.AuditEvent
  alias Espalier.Credentials.AttendanceCertificate
  alias Espalier.Repo

  @lookup "/api/facilitator/user-lookups"

  setup do
    program = publish_demo!()
    facilitator = user_with_role_fixture(:facilitator)

    %{
      program: program,
      format: format!(program, "workshop"),
      facilitator: facilitator,
      conn: log_in_user(api_conn(), facilitator)
    }
  end

  defp attendance_path(format_id), do: "/api/formats/#{format_id}/attendance"

  defp past_day, do: Date.add(Date.utc_today(), -7)

  defp disabled_user_fixture(attrs \\ %{}) do
    attrs |> user_fixture() |> Ecto.Changeset.change(status: :disabled) |> Repo.update!()
  end

  defp certificates(user) do
    Repo.all(from c in AttendanceCertificate, where: c.user_id == ^user.id)
  end

  defp audit_events(action) do
    Repo.all(from e in AuditEvent, where: e.action == ^action)
  end

  describe "access" do
    test "attendance and lookup answer 403 forbidden and log authz_fail for a learner",
         %{format: format} do
      learner = user_fixture()
      conn = log_in_user(api_conn(), learner)
      ref = attach_security_events()
      learner_id = learner.id

      conn =
        json_request(conn, :post, attendance_path(format.id), %{
          user_ids: [learner.id],
          held_on: Date.to_iso8601(Date.utc_today())
        })

      assert json_response(conn, 403) == %{"error" => "forbidden"}
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert_received {^ref, %{name: :authz_fail, reason: "forbidden", user_id: ^learner_id}}

      conn = json_request(conn, :post, @lookup, %{email: learner.email})

      assert json_response(conn, 403) == %{"error" => "forbidden"}
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert_received {^ref, %{name: :authz_fail, reason: "forbidden", user_id: ^learner_id}}

      assert certificates(learner) == []
    end

    test "attendance and lookup answer 401 without a session", %{format: format} do
      learner = user_fixture()

      conn =
        json_request(api_conn(), :post, attendance_path(format.id), %{
          user_ids: [learner.id],
          held_on: Date.to_iso8601(Date.utc_today())
        })

      assert json_response(conn, 401) == %{"error" => "unauthenticated"}

      conn = json_request(api_conn(), :post, @lookup, %{email: learner.email})
      assert json_response(conn, 401) == %{"error" => "unauthenticated"}
      assert certificates(learner) == []
    end
  end

  describe "POST /api/formats/:id/attendance" do
    test "answers issued, exists and not_found per distinct user id in request order",
         %{conn: conn, format: format, facilitator: facilitator} do
      held_on = past_day()
      issued = user_fixture()
      existing = user_fixture()
      disabled = disabled_user_fixture()
      unknown = Ecto.UUID.generate()
      certificate_fixture(existing, format, held_on)

      conn =
        json_request(conn, :post, attendance_path(format.id), %{
          user_ids: [issued.id, unknown, issued.id, disabled.id, existing.id, unknown],
          held_on: Date.to_iso8601(held_on)
        })

      assert json_response(conn, 200) == %{
               "results" => [
                 %{"user_id" => issued.id, "result" => "issued"},
                 %{"user_id" => unknown, "result" => "not_found"},
                 %{"user_id" => disabled.id, "result" => "not_found"},
                 %{"user_id" => existing.id, "result" => "exists"}
               ]
             }

      assert get_resp_header(conn, "cache-control") == ["no-store"]

      # The certificate belongs to the learner; the facilitator issued it.
      assert [certificate] = certificates(issued)

      assert %AttendanceCertificate{
               user_id: user_id,
               companion_format_id: format_id,
               held_on: ^held_on,
               issued_by_id: issued_by_id
             } = certificate

      assert {user_id, format_id, issued_by_id} == {issued.id, format.id, facilitator.id}
      assert length(certificates(existing)) == 1
      assert certificates(disabled) == []

      # One audit event per new certificate, none for an existing one.
      assert [event] = audit_events("attendance.issued")

      assert {event.subject_id, event.actor_id} == {certificate.id, facilitator.id}
      assert event.details["format_key"] == "workshop"
      assert event.details["held_on"] == Date.to_iso8601(held_on)
    end

    test "an upper-case user id names the same user and collapses with its lower-case form",
         %{conn: conn, format: format} do
      learner = user_fixture()

      conn =
        json_request(conn, :post, attendance_path(format.id), %{
          user_ids: [String.upcase(learner.id), learner.id],
          held_on: Date.to_iso8601(past_day())
        })

      assert json_response(conn, 200) == %{
               "results" => [%{"user_id" => learner.id, "result" => "issued"}]
             }

      assert [_certificate] = certificates(learner)
    end

    test "a repeated request for the same day answers exists and writes no audit event",
         %{conn: conn, format: format} do
      learner = user_fixture()
      body = %{user_ids: [learner.id], held_on: Date.to_iso8601(past_day())}

      conn = json_request(conn, :post, attendance_path(format.id), body)

      assert json_response(conn, 200)["results"] == [
               %{"user_id" => learner.id, "result" => "issued"}
             ]

      conn = json_request(conn, :post, attendance_path(format.id), body)

      assert json_response(conn, 200)["results"] == [
               %{"user_id" => learner.id, "result" => "exists"}
             ]

      assert length(certificates(learner)) == 1
      assert length(audit_events("attendance.issued")) == 1
    end

    test "answers 422 held_on past for a day before 2000-01-01, also before the range of the database",
         %{conn: conn, format: format} do
      learner = user_fixture()

      for held_on <- ["1999-12-31", "0001-01-01", "-5000-01-01"] do
        conn =
          json_request(conn, :post, attendance_path(format.id), %{
            user_ids: [learner.id],
            held_on: held_on
          })

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"held_on" => ["past"]}
               },
               held_on
      end

      assert certificates(learner) == []

      conn =
        json_request(conn, :post, attendance_path(format.id), %{
          user_ids: [learner.id],
          held_on: "2000-01-01"
        })

      assert json_response(conn, 200)["results"] == [
               %{"user_id" => learner.id, "result" => "issued"}
             ]
    end

    test "accepts today and answers 422 held_on future for a day after today",
         %{conn: conn, format: format} do
      learner = user_fixture()
      today = Date.utc_today()

      conn =
        json_request(conn, :post, attendance_path(format.id), %{
          user_ids: [learner.id],
          held_on: today |> Date.add(1) |> Date.to_iso8601()
        })

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"held_on" => ["future"]}
             }

      assert certificates(learner) == []

      conn =
        json_request(conn, :post, attendance_path(format.id), %{
          user_ids: [learner.id],
          held_on: Date.to_iso8601(today)
        })

      assert json_response(conn, 200)["results"] == [
               %{"user_id" => learner.id, "result" => "issued"}
             ]

      assert [%AttendanceCertificate{held_on: ^today}] = certificates(learner)
    end

    test "answers 404 for a format of a draft program and for an unknown format",
         %{conn: conn, program: program, format: format} do
      learner = user_fixture()
      body = %{user_ids: [learner.id], held_on: Date.to_iso8601(past_day())}

      conn = json_request(conn, :post, attendance_path(Ecto.UUID.generate()), body)
      assert json_response(conn, 404) == %{"error" => "not_found"}

      program |> Ecto.Changeset.change(status: :draft) |> Repo.update!()

      conn = json_request(conn, :post, attendance_path(format.id), body)
      assert json_response(conn, 404) == %{"error" => "not_found"}

      assert certificates(learner) == []
      assert audit_events("attendance.issued") == []
    end

    test "answers 422 validation_failed for a body with an extra member",
         %{conn: conn, format: format, facilitator: facilitator} do
      learner = user_fixture()

      conn =
        json_request(conn, :post, attendance_path(format.id), %{
          user_ids: [learner.id],
          held_on: Date.to_iso8601(past_day()),
          issued_by_id: facilitator.id
        })

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"issued_by_id" => ["unexpected_field"]}
             }

      assert certificates(learner) == []
    end

    test "evaluates the learner, so a holder of basics receives the add-on workshop",
         %{conn: conn, program: program, format: format} do
      learner = user_fixture()
      credential_fixture(learner, qualification!(program, "basics"))

      conn =
        json_request(conn, :post, attendance_path(format.id), %{
          user_ids: [learner.id],
          held_on: Date.to_iso8601(Date.utc_today())
        })

      assert json_response(conn, 200)["results"] == [
               %{"user_id" => learner.id, "result" => "issued"}
             ]

      assert %{status: :active} = credential_for(learner, program, "workshop")
    end
  end

  describe "POST /api/facilitator/user-lookups" do
    test "finds a user by the exact address in any letter case and with surrounding spaces",
         %{conn: conn} do
      user =
        %{display_name: "Ada Example"}
        |> user_fixture()
        |> Ecto.Changeset.change(org_unit: "Unit A")
        |> Repo.update!()

      for email <- [user.email, String.upcase(user.email), "  #{user.email}  "] do
        conn = json_request(conn, :post, @lookup, %{email: email})

        assert json_response(conn, 200) == %{
                 "id" => user.id,
                 "display_name" => "Ada Example",
                 "org_unit" => "Unit A"
               }

        assert get_resp_header(conn, "cache-control") == ["no-store"]
      end
    end

    test "answers 404 for a partial address, an unknown address and a disabled user",
         %{conn: conn} do
      user = user_fixture()
      disabled = disabled_user_fixture()
      [local, domain] = String.split(user.email, "@")

      for email <- [
            local,
            "@" <> domain,
            String.slice(user.email, 0..-2//1),
            "x" <> user.email,
            unique_user_email(),
            disabled.email
          ] do
        conn = json_request(conn, :post, @lookup, %{email: email})
        assert json_response(conn, 404) == %{"error" => "not_found"}, email
        assert get_resp_header(conn, "cache-control") == ["no-store"]
      end
    end

    test "answers 422 validation_failed for a body with an extra member", %{conn: conn} do
      user = user_fixture()

      conn = json_request(conn, :post, @lookup, %{email: user.email, display_name: "Ada"})

      assert json_response(conn, 422) == %{
               "error" => "validation_failed",
               "fields" => %{"display_name" => ["unexpected_field"]}
             }
    end

    test "the log holds no looked-up address", %{conn: conn, format: format} do
      user = user_fixture()
      Logger.put_module_level(Phoenix.Logger, :debug)
      on_exit(fn -> Logger.delete_module_level(Phoenix.Logger) end)

      log =
        capture_log([level: :debug], fn ->
          conn = json_request(conn, :post, @lookup, %{email: String.upcase(user.email)})
          assert json_response(conn, 200)["id"] == user.id

          conn = json_request(conn, :post, @lookup, %{email: "nobody-" <> user.email})
          assert json_response(conn, 404)

          conn =
            json_request(conn, :post, attendance_path(format.id), %{
              user_ids: [user.id],
              held_on: Date.to_iso8601(Date.utc_today())
            })

          assert json_response(conn, 200)
        end)

      assert log =~ "Parameters"
      assert log =~ ~s("email" => "[FILTERED]")
      refute log =~ user.email
      refute log =~ String.upcase(user.email)
    end
  end
end
