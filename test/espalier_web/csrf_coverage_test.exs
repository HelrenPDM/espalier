defmodule EspalierWeb.CsrfCoverageTest do
  @moduledoc """
  The CSRF proof of the router (README section 6.5, ASVS 3.5.1 to 3.5.3).
  Sobelow's `Config.CSRF` check compares plug names only, so these tests
  carry the proof that every mutating route checks the token. Every
  exemption needs a row in `docs/security/asvs-l2.md`.
  """
  use EspalierWeb.ConnCase, async: true

  # The integration API of task 0013 authenticates by a bearer token in the
  # authorization header and runs without session and CSRF layer; row 3.5.1
  # of docs/security/asvs-l2.md records the reason.
  @exemptions [{:post, "/api/integration/credential-lookups"}]
  @mutating ~w(POST PUT PATCH DELETE)

  defp routes, do: Phoenix.Router.routes(EspalierWeb.Router)

  defp concrete_path(path) do
    path
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":" <> _param -> Ecto.UUID.generate()
      "*" <> _param -> "any"
      segment -> segment
    end)
  end

  test "every mutating route answers 403 csrf without x-csrf-token", %{conn: conn} do
    user = user_fixture()

    mutating =
      for %{verb: verb} = route <- routes(),
          String.upcase(to_string(verb)) in @mutating,
          do: route

    assert mutating != []

    for %{verb: verb, path: path} <- mutating, {verb, path} not in @exemptions do
      method = verb |> to_string() |> String.upcase()

      response =
        conn
        |> log_in_user(user)
        |> dispatch(@endpoint, method, concrete_path(path), %{})

      assert response.status == 403, "#{method} #{path} answered #{response.status}"
      assert JSON.decode!(response.resp_body) == %{"error" => "csrf"}, "#{method} #{path}"
    end
  end

  # Task 0013 step 19 and its acceptance item on CSRF coverage.
  test "the covered routes include the browser POST routes of task 0013 and the integration API is the only exemption" do
    mutating =
      for %{verb: verb, path: path} <- routes(),
          String.upcase(to_string(verb)) in @mutating,
          do: {verb, path}

    covered = mutating -- @exemptions

    for route <- [
          {:post, "/api/policy-versions/:id/acknowledgements"},
          {:post, "/api/formats/:id/attendance"},
          {:post, "/api/facilitator/user-lookups"}
        ] do
      assert route in covered, inspect(route)
    end

    assert @exemptions == [{:post, "/api/integration/credential-lookups"}]
    assert {:post, "/api/integration/credential-lookups"} in mutating

    info =
      Phoenix.Router.route_info(
        EspalierWeb.Router,
        "POST",
        "/api/integration/credential-lookups",
        "localhost"
      )

    assert info.pipe_through == [:integration]
  end

  test "the browser POST routes of task 0013 answer 403 csrf without x-csrf-token, also for a facilitator",
       %{conn: conn} do
    facilitator = Espalier.CredentialsFixtures.user_with_role_fixture(:facilitator)
    ref = attach_security_events()

    for path <- [
          "/api/policy-versions/#{Ecto.UUID.generate()}/acknowledgements",
          "/api/formats/#{Ecto.UUID.generate()}/attendance",
          "/api/facilitator/user-lookups"
        ] do
      response =
        conn
        |> log_in_user(facilitator)
        |> put_req_header("content-type", "application/json")
        |> post(path, JSON.encode!(%{email: facilitator.email}))

      assert json_response(response, 403) == %{"error" => "csrf"}, path
      assert_received {^ref, %{name: :malicious_csrf}}
    end
  end

  test "every /api route pipes through :api" do
    # The integration route skips :api; row 3.5.1 of docs/security/asvs-l2.md
    # records the reason.
    for %{verb: verb, path: "/api" <> _ = path} <- routes(), {verb, path} not in @exemptions do
      method = verb |> to_string() |> String.upcase()

      info =
        Phoenix.Router.route_info(EspalierWeb.Router, method, concrete_path(path), "localhost")

      assert :api in info.pipe_through, "#{method} #{path}"
    end
  end

  test "every route of :oidc_transaction is a GET" do
    for %{verb: verb, path: path} <- routes() do
      method = verb |> to_string() |> String.upcase()

      info =
        Phoenix.Router.route_info(EspalierWeb.Router, method, concrete_path(path), "localhost")

      if :oidc_transaction in info.pipe_through do
        assert method == "GET", "#{method} #{path}"
      end
    end
  end

  test "no GET route of /api changes the sign-in state", %{conn: conn} do
    for %{verb: :get, path: "/api" <> _ = path} <- routes() do
      response = get(conn, concrete_path(path))
      assert get_resp_header(response, "set-cookie") |> Enum.all?(&(&1 =~ "__Host-espalier="))
    end

    assert Espalier.Repo.aggregate(Espalier.Accounts.UserToken, :count) == 0
  end
end
