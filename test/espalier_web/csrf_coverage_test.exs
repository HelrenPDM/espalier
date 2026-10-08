defmodule EspalierWeb.CsrfCoverageTest do
  @moduledoc """
  The CSRF proof of the router (README section 6.5, ASVS 3.5.1 to 3.5.3).
  Sobelow's `Config.CSRF` check compares plug names only, so these tests
  carry the proof that every mutating route checks the token. The exemption
  list is empty; an entry would need a row in `docs/security/asvs-l2.md`.
  """
  use EspalierWeb.ConnCase, async: true

  @exemptions []
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

  test "every /api route pipes through :api" do
    for %{verb: verb, path: "/api" <> _ = path} <- routes() do
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
