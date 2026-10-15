defmodule EspalierWeb.Credentials.LearnerRoutesTest do
  @moduledoc """
  The learner routes of task 0013 (spec steps 11, 17 and 24): policies with
  their acknowledgements, the approved tool list, the requirements per
  qualification in the order of `qualifications.yaml` or by the `position`
  of its entries (issue #39), the own credentials and the repeated module
  completion.

  The routes sit behind a session (ASVS 8.2.1), a credential of another
  user answers 404 (ASVS 8.2.2), a body with an extra member answers 422
  (ASVS 15.3.3), and no answer carries a score, percentage or rank (README
  principle 2).
  """
  use EspalierWeb.ConnCase, async: true

  import Ecto.Query
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures
  import OpenApiSpex.TestAssertions

  alias Espalier.{Catalog, PackFixtures}
  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.{PackImport, Station}
  alias Espalier.Learning.ModuleCompletion
  alias Espalier.Policies
  alias Espalier.Policies.Acknowledgement
  alias Espalier.Repo
  alias EspalierWeb.ApiSpec

  setup do
    program = publish_demo!()
    user = user_fixture(%{display_name: "Robin Example"})

    %{
      program: program,
      user: user,
      scope: scope_for(user),
      conn: log_in_user(api_conn(), user),
      spec: ApiSpec.spec()
    }
  end

  defp get_json(conn, path, status \\ 200),
    do: conn |> json_request(:get, path) |> json_response(status)

  defp acknowledge(conn, id, body \\ nil),
    do: json_request(conn, :post, "/api/policy-versions/#{id}/acknowledgements", body)

  defp station_position(program, kind, module \\ nil) do
    query = from s in Station, where: s.program_id == ^program.id and s.kind == ^kind

    query =
      if module,
        do: where(query, [s], s.module_id == ^module.id),
        else: query

    Repo.one!(select(query, [s], s.position))
  end

  # Requirement entries as sorted tuples, so that the assertions do not
  # depend on the order within `met` and `open`.
  defp entries(list),
    do: list |> Enum.map(&{&1["kind"], &1["target_key"], &1["station_position"]}) |> Enum.sort()

  defp qualification(body, code), do: Enum.find(body["qualifications"], &(&1["code"] == code))

  # Publishes a copy of the demo pack whose qualifications.yaml holds
  # `entries`. The module runs async, so the copy takes a key of its own,
  # which the publisher locks apart from the demo pack.
  defp publish_qualifications!(entries) do
    key = "qualification-order-#{System.unique_integer([:positive])}"
    pack = PackFixtures.copy_pack!(PackFixtures.demo_path())
    PackFixtures.update_yaml!(pack, "pack.yaml", &Map.put(&1, "key", key))
    PackFixtures.write_yaml!(pack, "qualifications.yaml", entries)
    {:ok, %PackImport{status: :validated} = pack_import} = Importer.import(pack, nil)
    {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    Catalog.get_program_by_slug(key)
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

  # Every member name of a JSON value, nested members included.
  defp member_names(map) when is_map(map),
    do: Enum.flat_map(map, fn {key, value} -> [key | member_names(value)] end)

  defp member_names(list) when is_list(list), do: Enum.flat_map(list, &member_names/1)
  defp member_names(_value), do: []

  test "every learner route of task 0013 answers 401 without a session", %{program: program} do
    version = published_policy!("usage-policy")
    credential = credential_fixture(user_fixture(), qualification!(program, "basics"))

    routes = [
      {:get, "/api/policies"},
      {:post, "/api/policy-versions/#{version.id}/acknowledgements"},
      {:get, "/api/approved-tools"},
      {:get, "/api/me/requirements?program=#{program.slug}"},
      {:get, "/api/me/credentials"},
      {:get, "/api/me/credentials/#{credential.id}"}
    ]

    for {method, path} <- routes do
      conn = json_request(api_conn(), method, path)
      assert json_response(conn, 401) == %{"error" => "unauthenticated"}, "#{method} #{path}"
    end

    assert Repo.aggregate(Acknowledgement, :count) == 0
  end

  describe "policies" do
    test "GET /api/policies lists the current versions with acknowledged_at null, then the acknowledgement",
         %{conn: conn, spec: spec} do
      usage = policy_fixture(%{key: "usage-policy", title: "Usage policy"})
      published_version_fixture(usage, %{body: "First text."})

      current =
        published_version_fixture(usage, %{body: "Second text.", effective_from: ~D[2026-06-01]})

      draft_version_fixture(usage, %{body: "A draft."})
      input = published_policy!("input-rules")

      body = get_json(conn, "/api/policies")
      assert_schema(body, "PolicyList", spec)

      assert body["policies"] == [
               %{
                 "id" => input.id,
                 "key" => "input-rules",
                 "title" => "A policy",
                 "number" => 1,
                 "effective_from" => "2026-01-01",
                 "body" => "The text of the policy.",
                 "acknowledged_at" => nil
               },
               %{
                 "id" => current.id,
                 "key" => "usage-policy",
                 "title" => "Usage policy",
                 "number" => 2,
                 "effective_from" => "2026-06-01",
                 "body" => "Second text.",
                 "acknowledged_at" => nil
               }
             ]

      created = conn |> acknowledge(current.id) |> json_response(200)
      assert_schema(created, "AcknowledgementView", spec)
      assert %{"policy_version_id" => id, "acknowledged_at" => acknowledged_at} = created
      assert id == current.id
      assert {:ok, _at, 0} = DateTime.from_iso8601(acknowledged_at)

      body = get_json(conn, "/api/policies")

      assert Enum.map(body["policies"], &{&1["key"], &1["acknowledged_at"]}) == [
               {"input-rules", nil},
               {"usage-policy", acknowledged_at}
             ]

      other_conn = log_in_user(api_conn(), user_fixture())
      body = get_json(other_conn, "/api/policies")
      assert Enum.all?(body["policies"], &(&1["acknowledged_at"] == nil))
    end

    test "POST /api/policy-versions/:id/acknowledgements answers 404 for a draft and for an unknown id",
         %{conn: conn} do
      draft = draft_version_fixture(policy_fixture(%{key: "usage-policy"}))

      for id <- [draft.id, Ecto.UUID.generate()] do
        assert conn |> acknowledge(id) |> json_response(404) == %{"error" => "not_found"}
      end

      assert Repo.aggregate(Acknowledgement, :count) == 0
    end

    test "a repeated acknowledgement answers 200 with the stored acknowledged_at and keeps one row",
         %{conn: conn, user: user} do
      version = published_policy!("usage-policy")
      first = conn |> acknowledge(version.id) |> json_response(200)
      assert first["policy_version_id"] == version.id

      earlier = ~U[2026-01-02 03:04:05Z]

      {1, _rows} =
        Repo.update_all(
          from(a in Acknowledgement, where: a.user_id == ^user.id),
          set: [acknowledged_at: earlier]
        )

      second = conn |> acknowledge(version.id) |> json_response(200)

      assert second == %{
               "policy_version_id" => version.id,
               "acknowledged_at" => "2026-01-02T03:04:05Z"
             }

      assert [%Acknowledgement{acknowledged_at: ^earlier}] = Repo.all(Acknowledgement)
    end

    test "a body with an extra member answers 422 validation_failed and stores nothing",
         %{conn: conn} do
      version = published_policy!("usage-policy")
      body = %{"acknowledged_at" => "2026-01-02T03:04:05Z"}

      assert conn |> acknowledge(version.id, body) |> json_response(422) == %{
               "error" => "validation_failed",
               "fields" => %{"acknowledged_at" => ["unexpected_field"]}
             }

      assert Repo.aggregate(Acknowledgement, :count) == 0
    end

    test "GET /api/approved-tools returns the tools ordered by position", %{
      conn: conn,
      spec: spec
    } do
      third =
        approved_tool_fixture(%{
          name: "Third tool",
          vendor: "Vendor C",
          status: :not_approved,
          conditions: nil,
          reviewed_on: nil,
          position: 3
        })

      first = approved_tool_fixture(%{name: "First tool", vendor: "Vendor A", position: 1})

      second =
        approved_tool_fixture(%{
          name: "Second tool",
          vendor: "Vendor B",
          status: :restricted,
          conditions: "Public sources only.",
          reviewed_on: ~D[2026-08-15],
          position: 2
        })

      body = get_json(conn, "/api/approved-tools")
      assert_schema(body, "ApprovedToolList", spec)

      assert body["tools"] == [
               %{
                 "id" => first.id,
                 "name" => "First tool",
                 "vendor" => "Vendor A",
                 "status" => "approved",
                 "conditions" => "Internal drafts only.",
                 "reviewed_on" => "2026-09-01",
                 "position" => 1
               },
               %{
                 "id" => second.id,
                 "name" => "Second tool",
                 "vendor" => "Vendor B",
                 "status" => "restricted",
                 "conditions" => "Public sources only.",
                 "reviewed_on" => "2026-08-15",
                 "position" => 2
               },
               %{
                 "id" => third.id,
                 "name" => "Third tool",
                 "vendor" => "Vendor C",
                 "status" => "not_approved",
                 "conditions" => nil,
                 "reviewed_on" => nil,
                 "position" => 3
               }
             ]
    end
  end

  describe "GET /api/me/requirements" do
    test "lists the met and open requirements per qualification with the satisfying station",
         %{conn: conn, scope: scope, program: program, spec: spec} do
      module_1 = station_position(program, :module, module!(program, 1))
      module_2 = station_position(program, :module, module!(program, 2))
      formats = station_position(program, :companion_formats)
      path = "/api/me/requirements?program=#{program.slug}"

      body = get_json(conn, path)
      assert_schema(body, "RequirementList", spec)
      assert Enum.map(body["qualifications"], & &1["code"]) == ~w(basics workshop)

      basics = qualification(body, "basics")

      assert %{
               "title" => "AI assistant basics",
               "add_on" => false,
               "credential" => nil,
               "met" => []
             } = basics

      assert basics["unlocks"] == qualification!(program, "basics").unlocks

      assert entries(basics["open"]) == [
               {"assessment_passed", "module-1-exam", module_1},
               {"module_completed", "1", module_1},
               {"module_completed", "2", module_2},
               {"policy_acknowledged", "usage-policy", nil}
             ]

      workshop = qualification(body, "workshop")
      assert %{"add_on" => true, "credential" => nil, "met" => []} = workshop

      assert entries(workshop["open"]) == [
               {"attendance", "workshop", formats},
               {"qualification_held", "basics", nil}
             ]

      {:ok, _ack} = Policies.acknowledge(scope, published_policy!("usage-policy"))

      basics = conn |> get_json(path) |> qualification("basics")
      assert entries(basics["met"]) == [{"policy_acknowledged", "usage-policy", nil}]
      assert length(basics["open"]) == 3
      assert basics["credential"] == nil
    end

    test "carries the credential once every requirement of a qualification holds",
         %{conn: conn, scope: scope, program: program, spec: spec} do
      credential = qualify_basics!(scope, program)
      assert %{status: :active} = credential

      body = get_json(conn, "/api/me/requirements?program=#{program.slug}")
      assert_schema(body, "RequirementList", spec)

      basics = qualification(body, "basics")
      assert basics["open"] == []
      assert length(basics["met"]) == 4

      assert basics["credential"] == %{
               "id" => credential.id,
               "status" => "active",
               "issued_at" => DateTime.to_iso8601(credential.issued_at),
               "valid_until" => Date.to_iso8601(Date.shift(Date.utc_today(), month: 12))
             }

      workshop = qualification(body, "workshop")
      assert entries(workshop["met"]) == [{"qualification_held", "basics", nil}]
      assert [%{"kind" => "attendance", "target_key" => "workshop"}] = workshop["open"]
      assert workshop["credential"] == nil
    end

    # The add-on `a` stands between two base qualifications, where the order
    # by add-on flag and code would put it last.
    test "lists the qualifications in the order of qualifications.yaml",
         %{conn: conn, spec: spec} do
      program =
        publish_qualifications!([
          qualification_entry("c", false),
          qualification_entry("a", true),
          qualification_entry("b", false)
        ])

      body = get_json(conn, "/api/me/requirements?program=#{program.slug}")
      assert_schema(body, "RequirementList", spec)

      assert Enum.map(body["qualifications"], &{&1["code"], &1["add_on"]}) == [
               {"c", false},
               {"a", true},
               {"b", false}
             ]
    end

    test "lists the qualifications by position when every entry sets one", %{conn: conn} do
      program =
        publish_qualifications!([
          qualification_entry("c", false, 30),
          qualification_entry("a", true, 20),
          qualification_entry("b", false, 10)
        ])

      body = get_json(conn, "/api/me/requirements?program=#{program.slug}")
      assert Enum.map(body["qualifications"], & &1["code"]) == ~w(b a c)
    end

    test "answers 404 for an unknown program and 422 without the parameter", %{conn: conn} do
      assert get_json(conn, "/api/me/requirements?program=no-such-program", 404) == %{
               "error" => "not_found"
             }

      assert get_json(conn, "/api/me/requirements", 422)["fields"] == %{
               "program" => ["missing_field"]
             }
    end
  end

  describe "credentials" do
    test "GET /api/me/credentials lists the own credentials only",
         %{conn: conn, user: user, program: program, spec: spec} do
      basics = qualification!(program, "basics")
      workshop = qualification!(program, "workshop")
      own = credential_fixture(user, basics, %{issued_at: ~U[2026-03-01 08:00:00Z]})
      other = user_fixture()
      credential_fixture(other, basics)
      credential_fixture(other, workshop)

      body = get_json(conn, "/api/me/credentials")
      assert_schema(body, "CredentialList", spec)

      assert [%{"id" => id, "holder_display_name" => "Robin Example"}] = body["credentials"]
      assert id == own.id

      other_conn = log_in_user(api_conn(), other)
      body = get_json(other_conn, "/api/me/credentials")
      assert length(body["credentials"]) == 2
      refute own.id in Enum.map(body["credentials"], & &1["id"])
    end

    test "GET /api/me/credentials/:id returns an own credential",
         %{conn: conn, user: user, program: program, spec: spec} do
      basics = qualification!(program, "basics")

      credential =
        credential_fixture(user, basics, %{
          status: :refresh_due,
          issued_at: ~U[2026-03-01 08:00:00Z],
          valid_until: ~D[2027-03-01],
          refresh_due_at: ~U[2027-01-30 03:00:00Z]
        })

      body = get_json(conn, "/api/me/credentials/#{credential.id}")
      assert_schema(body, "CredentialView", spec)

      assert body == %{
               "id" => credential.id,
               "qualification_code" => "basics",
               "qualification_title" => "AI assistant basics",
               "locale" => "en",
               "holder_display_name" => "Robin Example",
               "status" => "refresh_due",
               "issued_at" => "2026-03-01T08:00:00Z",
               "valid_until" => "2027-03-01",
               "unlocks_snapshot" => basics.unlocks
             }
    end

    test "GET /api/me/credentials/:id answers 404 for the credential of another user and for an unknown id",
         %{conn: conn, program: program} do
      other = credential_fixture(user_fixture(), qualification!(program, "basics"))

      for id <- [other.id, Ecto.UUID.generate()] do
        assert get_json(conn, "/api/me/credentials/#{id}", 404) == %{"error" => "not_found"}
      end
    end
  end

  test "POST /api/modules/:id/completion a second time answers 200 with a new completed_at",
       %{conn: conn, user: user, scope: scope, program: program} do
    enroll!(scope)
    exam = assessment!(program)
    module = module!(program, 1)
    path = "/api/modules/#{module.id}/completion"

    attempt =
      json_request(conn, :post, "/api/assessments/#{exam.id}/attempts", %{
        answers: exam_answers(exam)
      })

    assert %{"outcome" => "passed"} = json_response(attempt, 201)

    first = conn |> json_request(:post, path) |> json_response(200)
    assert first["module_id"] == module.id

    earlier = ~U[2026-01-02 03:04:05Z]
    :ok = set_completed_at!(user, program, 1, earlier)

    second = conn |> json_request(:post, path) |> json_response(200)
    assert second["module_id"] == module.id
    {:ok, completed_at, 0} = DateTime.from_iso8601(second["completed_at"])
    assert DateTime.after?(completed_at, earlier)

    assert [%ModuleCompletion{completed_at: ^completed_at}] =
             Repo.all(from c in ModuleCompletion, where: c.user_id == ^user.id)
  end

  test "no learner response carries a score, percentage or rank member",
       %{conn: conn, scope: scope, program: program} do
    approved_tool_fixture()
    credential = qualify_basics!(scope, program)
    version = Policies.current_version("usage-policy")

    bodies = [
      get_json(conn, "/api/policies"),
      conn |> acknowledge(version.id) |> json_response(200),
      get_json(conn, "/api/approved-tools"),
      get_json(conn, "/api/me/requirements?program=#{program.slug}"),
      get_json(conn, "/api/me/credentials"),
      get_json(conn, "/api/me/credentials/#{credential.id}")
    ]

    names = bodies |> member_names() |> Enum.uniq()
    assert "unlocks_snapshot" in names
    assert Enum.filter(names, &(&1 =~ ~r/score|percent|rank/i)) == []
  end
end
