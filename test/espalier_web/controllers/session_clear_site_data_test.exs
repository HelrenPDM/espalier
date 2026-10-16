defmodule EspalierWeb.SessionClearSiteDataTest do
  @moduledoc """
  `DELETE /api/session` answers with `Clear-Site-Data: "cache"`, so the
  browser drops the media files that it cached during the session (task
  0018, step 13; ASVS 14.3.1).
  """
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts

  describe "DELETE /api/session" do
    setup :register_and_log_in_user

    test "answers 204 with clear-site-data: \"cache\" and ends the session", %{
      conn: conn,
      token: token
    } do
      conn = api_request(conn, :delete, "/api/session")

      assert response(conn, 204) == ""
      assert get_resp_header(conn, "clear-site-data") == [~s("cache")]
      assert get_resp_header(conn, "cache-control") == ["no-store"]
      assert Accounts.get_session_by_token(token) == {:error, :not_found}
    end

    test "the sign-out of a demo session clears the cache too" do
      user = user_fixture()
      conn = log_in_user(api_conn(), user, %{strength: :demo, auth_methods: [:demo]})

      conn = api_request(conn, :delete, "/api/session")
      assert response(conn, 204) == ""
      assert get_resp_header(conn, "clear-site-data") == [~s("cache")]
    end
  end

  test "DELETE /api/session without a session answers 204 with clear-site-data", %{conn: conn} do
    conn = api_request(conn, :delete, "/api/session")

    assert response(conn, 204) == ""
    assert get_resp_header(conn, "clear-site-data") == [~s("cache")]
  end

  test "GET /api/session carries no clear-site-data", %{conn: conn} do
    conn = get(conn, "/api/session")
    assert conn.status == 200
    assert get_resp_header(conn, "clear-site-data") == []
  end
end

defmodule EspalierWeb.SessionClearSiteDataOidcTest do
  @moduledoc """
  The sign-out of an OIDC session with an RP-initiated logout answers 200
  with the logout URL and `Clear-Site-Data: "cache"` as well (task 0018,
  step 13).
  """
  use Espalier.OidcCase

  defp entra(overrides), do: provider_env("entra", "entra", overrides)

  test "DELETE /api/session with a logout URL answers 200 with clear-site-data", %{conn: conn} do
    setup_providers([entra(%{"MFA" => "idp_trusted"})])

    conn = sign_in!(conn, "entra", "ben")
    conn = api_request(conn, :delete, "/api/session")

    assert %{"logout_url" => url} = json_response(conn, 200)
    assert is_binary(url)
    assert get_resp_header(conn, "clear-site-data") == [~s("cache")]
  end
end
