defmodule EspalierWeb.Auth.PasswordControllerTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts
  alias Espalier.Accounts.FailureCounters

  defp sign_in(conn, email, password) do
    conn |> with_csrf_token() |> post("/api/auth/password", %{email: email, password: password})
  end

  setup do
    %{user: user_fixture()}
  end

  test "a correct password answers second_factor and sets only the pending state",
       %{conn: conn, user: user} do
    conn = sign_in(conn, user.email, valid_user_password())
    assert json_response(conn, 200) == %{"next" => "second_factor"}
    assert get_session(conn, :user_token) == nil
    assert get_session(conn, :pending_second_factor)["user_id"] == user.id

    body = conn |> next_request() |> get("/api/session") |> json_response(200)
    assert body["user"] == nil
    assert body["session"] == nil
    assert body["pending"]["next"] == "second_factor"
    assert {:ok, _expires_at, 0} = DateTime.from_iso8601(body["pending"]["expires_at"])
  end

  test "a password sign-in in a conn that holds a session deletes that session row",
       %{conn: conn, user: user} do
    conn = log_in_user(conn, user)
    token = get_session(conn, :user_token)

    conn = sign_in(conn, user.email, valid_user_password())
    assert json_response(conn, 200) == %{"next" => "second_factor"}
    assert Accounts.get_session_by_token(token) == {:error, :not_found}
  end

  test "failures answer the identical 401 body", %{conn: conn, user: user} do
    locked = user_fixture()
    now = DateTime.utc_now()
    for _ <- 1..5, do: FailureCounters.record_failure(locked, :password, now)

    broken = user_fixture()

    broken
    |> Ecto.Changeset.change(hashed_password: "not an argon2 hash")
    |> Espalier.Repo.update!()

    attempts = [
      {user.email, "a wrong but long password"},
      {unique_user_email(), valid_user_password()},
      {user.email, String.duplicate("a", 129)},
      {locked.email, valid_user_password()},
      {broken.email, valid_user_password()}
    ]

    bodies =
      for {email, password} <- attempts do
        conn |> sign_in(email, password) |> json_response(401)
      end

    assert Enum.uniq(bodies) == [%{"error" => "invalid_credentials"}]
  end

  test "an unknown address appears in the log only as account_hash", %{conn: conn} do
    ref = attach_security_events()
    email = unique_user_email()
    sign_in(conn, email, valid_user_password())

    assert_received {^ref, %{name: :authn_login_fail, account_hash: hash} = event}
    assert hash == Espalier.RateLimit.account_hash(email)
    refute inspect(event) =~ email
  end

  test "a request without the fields answers 400", %{conn: conn} do
    conn = conn |> with_csrf_token() |> post("/api/auth/password", %{email: "x@example.org"})
    assert json_response(conn, 400) == %{"error" => "bad_request"}
  end
end
