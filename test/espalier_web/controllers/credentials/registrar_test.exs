defmodule EspalierWeb.Credentials.RegistrarTest do
  @moduledoc """
  The registrar list of task 0013 (spec steps 18 and 24, bullet "Routes";
  README section 10): `GET /api/registrar/credentials?qualification=code`
  answers 404 while `REGISTRAR_ENABLED` is false, for every caller and
  before the role check, answers 403 with a logged `authz_fail` for a
  learner while it is true (ASVS 8.2.1 and 16.3.2), returns display name,
  org unit, status, issue time and validity per credential to a registrar,
  so that a person who holds the code in two programs appears once per
  program, and carries `cache-control: no-store` (ASVS 14.2.2 and 14.3.2).
  """
  # put_setting/2 changes the application environment.
  use EspalierWeb.ConnCase, async: false

  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.{PackImport, Program}
  alias Espalier.{PackFixtures, Repo}

  @path "/api/registrar/credentials?qualification=basics"

  setup do
    %{program: publish_demo!(), registrar: user_with_role_fixture(:registrar)}
  end

  defp with_org_unit(user, org_unit) do
    user |> Ecto.Changeset.change(org_unit: org_unit) |> Repo.update!()
  end

  # The fixture pack minimal also defines a qualification with the code basics.
  defp publish_minimal_pack! do
    path = PackFixtures.copy_pack!("minimal")
    {:ok, %PackImport{status: :validated} = pack_import} = Importer.import(path, nil)
    {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    Repo.get_by!(Program, slug: "minimal-pack")
  end

  describe "while REGISTRAR_ENABLED is false" do
    setup do
      put_setting(:registrar_enabled, false)
    end

    test "answers 404 not_found to a registrar, a learner and a signed-out caller",
         %{program: program, registrar: registrar} do
      credential_fixture(user_fixture(), qualification!(program, "basics"))
      ref = attach_security_events()

      for conn <- [
            log_in_user(api_conn(), registrar),
            log_in_user(api_conn(), user_fixture()),
            api_conn()
          ] do
        conn = get(conn, @path)
        assert json_response(conn, 404) == %{"error" => "not_found"}
        assert get_resp_header(conn, "cache-control") == ["no-store"]
      end

      # The flag check runs before the role check, so nothing is logged.
      refute_received {^ref, %{name: :authz_fail}}
    end
  end

  describe "while REGISTRAR_ENABLED is true" do
    setup do
      put_setting(:registrar_enabled, true)
    end

    test "answers 403 forbidden and logs authz_fail for a learner", %{program: program} do
      credential_fixture(user_fixture(), qualification!(program, "basics"))
      learner = user_fixture()
      ref = attach_security_events()

      conn = api_conn() |> log_in_user(learner) |> get(@path)

      assert json_response(conn, 403) == %{"error" => "forbidden"}
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      learner_id = learner.id

      assert_received {^ref, %{name: :authz_fail, reason: "forbidden", user_id: ^learner_id}}
    end

    test "answers 401 without a session" do
      conn = get(api_conn(), @path)
      assert json_response(conn, 401) == %{"error" => "unauthenticated"}
    end

    test "returns display name, org unit, status, issued_at and valid_until per person",
         %{program: program, registrar: registrar} do
      basics = qualification!(program, "basics")

      ben = user_fixture(%{display_name: "Ben Example"}) |> with_org_unit("Unit B")
      ada = user_fixture(%{display_name: "Ada Example"}) |> with_org_unit("Unit A")
      other = user_fixture(%{display_name: "Cleo Example"})

      credential_fixture(ben, basics, %{
        status: :expired,
        issued_at: ~U[2025-03-01 09:30:00Z],
        valid_until: ~D[2026-03-01],
        refresh_due_at: ~U[2026-01-30 03:00:00Z]
      })

      credential_fixture(ada, basics, %{
        issued_at: ~U[2026-09-01 08:00:00Z],
        valid_until: ~D[2027-09-01]
      })

      # A credential of another qualification stays out of the list.
      credential_fixture(other, qualification!(program, "workshop"))

      conn = api_conn() |> log_in_user(registrar) |> get(@path)

      assert json_response(conn, 200) == %{
               "credentials" => [
                 %{
                   "display_name" => "Ada Example",
                   "org_unit" => "Unit A",
                   "status" => "active",
                   "issued_at" => "2026-09-01T08:00:00Z",
                   "valid_until" => "2027-09-01"
                 },
                 %{
                   "display_name" => "Ben Example",
                   "org_unit" => "Unit B",
                   "status" => "expired",
                   "issued_at" => "2025-03-01T09:30:00Z",
                   "valid_until" => "2026-03-01"
                 }
               ]
             }

      assert get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "lists a person who holds the code in two published programs once per program",
         %{program: program, registrar: registrar} do
      minimal = publish_minimal_pack!()
      ada = user_fixture(%{display_name: "Ada Example"}) |> with_org_unit("Unit A")

      credential_fixture(ada, qualification!(program, "basics"), %{
        issued_at: ~U[2026-09-01 08:00:00Z],
        valid_until: ~D[2027-09-01]
      })

      credential_fixture(ada, qualification!(minimal, "basics"), %{
        status: :refresh_due,
        issued_at: ~U[2025-10-02 08:00:00Z],
        valid_until: ~D[2026-10-02],
        refresh_due_at: ~U[2026-09-02 03:00:00Z]
      })

      conn = api_conn() |> log_in_user(registrar) |> get(@path)

      # The contract orders by display name only, so the test sorts the two
      # entries of one person by issue time.
      assert %{"credentials" => credentials} = json_response(conn, 200)

      assert Enum.sort_by(credentials, & &1["issued_at"]) == [
               %{
                 "display_name" => "Ada Example",
                 "org_unit" => "Unit A",
                 "status" => "refresh_due",
                 "issued_at" => "2025-10-02T08:00:00Z",
                 "valid_until" => "2026-10-02"
               },
               %{
                 "display_name" => "Ada Example",
                 "org_unit" => "Unit A",
                 "status" => "active",
                 "issued_at" => "2026-09-01T08:00:00Z",
                 "valid_until" => "2027-09-01"
               }
             ]
    end

    test "returns an empty list for a code without credentials", %{registrar: registrar} do
      conn =
        api_conn()
        |> log_in_user(registrar)
        |> get("/api/registrar/credentials?qualification=unknown-code")

      assert json_response(conn, 200) == %{"credentials" => []}
    end

    test "answers 422 for a missing or malformed qualification", %{registrar: registrar} do
      conn = log_in_user(api_conn(), registrar)

      for path <- [
            "/api/registrar/credentials",
            "/api/registrar/credentials?qualification=Basics%20Code"
          ] do
        assert json_response(get(conn, path), 422)["error"] == "validation_failed", path
      end
    end
  end
end
