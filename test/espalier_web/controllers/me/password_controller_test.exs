defmodule EspalierWeb.Me.PasswordControllerTest do
  # One test sets PASSWORD_BREACH_CHECK=hibp for the whole node.
  use EspalierWeb.ConnCase, async: false

  alias Espalier.Accounts
  alias Espalier.Accounts.{BreachedPasswords, MailWorker, User, UserToken}

  @new_password "another long passphrase 1"

  defp update(conn, attrs), do: conn |> with_csrf_token() |> put("/api/me/password", attrs)

  defp codes(conn), do: json_response(conn, 422)["fields"]

  setup %{conn: conn} do
    user = user_fixture()

    conn =
      conn
      |> put_req_header("user-agent", "Mozilla/5.0 (Windows NT 10.0) Chrome/129.0 Safari/537.36")

    %{user: user, conn: conn}
  end

  test "answers 403 reauth_required when the second factor is older than 10 minutes", %{
    conn: conn,
    user: user
  } do
    stale = DateTime.add(DateTime.utc_now(:second), -11, :minute)

    conn =
      conn
      |> log_in_user(user, %{mfa_at: stale})
      |> update(%{current_password: valid_user_password(), password: @new_password})

    assert json_response(conn, 403) == %{"error" => "reauth_required"}
  end

  test "changes the password, ends the other sessions and keeps the client signed in", %{
    conn: conn,
    user: user
  } do
    {other, _} = session_fixture(user)
    conn = log_in_user(conn, user, %{device_summary: "Chrome on Windows"})
    previous = get_session(conn, :user_token)
    conn = with_csrf_token(conn)
    [old_csrf] = get_req_header(conn, "x-csrf-token")

    conn =
      put(conn, "/api/me/password", %{
        current_password: valid_user_password(),
        password: @new_password
      })

    body = json_response(conn, 200)

    assert body["csrf_token"] != old_csrf
    assert User.valid_password?(Accounts.get_user!(user.id), @new_password)
    assert Accounts.get_session_by_token(other) == {:error, :not_found}
    assert Accounts.get_session_by_token(previous) == {:error, :not_found}

    token = get_session(conn, :user_token)
    assert %UserToken{device_summary: "Chrome on Windows"} = session_row(token)
    assert conn |> next_request() |> get("/api/me/sessions") |> json_response(200)

    assert [job] = all_enqueued(worker: MailWorker, args: %{"kind" => "password_changed"})
    assert :ok = perform_job(MailWorker, job.args)
    assert_email_sent(fn email -> assert email.to == [{"", user.email}] end)
  end

  test "keeps the bytes of idp_sid_hash in the new row", %{conn: conn, user: user} do
    sid_hash = UserToken.hash_idp_sid("sid-1")
    conn = log_in_user(conn, user, %{idp_sid_hash: sid_hash, provider_key: "x"})
    conn = update(conn, %{current_password: valid_user_password(), password: @new_password})
    assert json_response(conn, 200)

    assert [row] = sessions_with_idp_sid("x", sid_hash)
    assert row.token_hash == UserToken.hash(get_session(conn, :user_token))
  end

  test "needs the current password", %{conn: conn, user: user} do
    conn = log_in_user(conn, user)

    assert codes(update(conn, %{password: @new_password})) == %{
             "current_password" => ["required"]
           }

    conn = update(conn, %{current_password: "a wrong but long password", password: @new_password})
    assert codes(conn) == %{"current_password" => ["invalid"]}
  end

  test "rejects a common password and a context word", %{conn: conn, user: user} do
    conn = log_in_user(conn, user)
    [common | _] = File.read!("priv/security/common-passwords.txt") |> String.split("\n")

    assert codes(update(conn, %{current_password: valid_user_password(), password: common})) ==
             %{"password" => ["common"]}

    assert codes(
             update(conn, %{
               current_password: valid_user_password(),
               password: "espalier 2026 2026!"
             })
           ) == %{"password" => ["context"]}
  end

  test "a body without password answers 422 validation_failed", %{conn: conn, user: user} do
    conn = conn |> log_in_user(user) |> update(%{current_password: valid_user_password()})

    assert json_response(conn, 422) == %{
             "error" => "validation_failed",
             "fields" => %{"password" => ["required"]}
           }
  end

  describe "with PASSWORD_BREACH_CHECK=hibp" do
    setup do
      put_setting(:password_breach_check, :hibp)
      :ok
    end

    test "rejects a breached password", %{conn: conn, user: user} do
      <<_::binary-size(5), suffix::binary>> = :crypto.hash(:sha, @new_password) |> Base.encode16()
      Req.Test.stub(BreachedPasswords, &Req.Test.text(&1, "#{suffix}:12\r\n"))

      conn =
        conn
        |> log_in_user(user)
        |> update(%{current_password: valid_user_password(), password: @new_password})

      assert codes(conn) == %{"password" => ["breached"]}
    end

    test "falls back to the lists and logs breach_check_unavailable", %{conn: conn, user: user} do
      Req.Test.stub(BreachedPasswords, &Req.Test.transport_error(&1, :timeout))
      ref = attach_security_events()

      conn =
        conn
        |> log_in_user(user)
        |> update(%{current_password: valid_user_password(), password: @new_password})

      assert json_response(conn, 200)
      assert_received {^ref, %{name: :breach_check_unavailable}}
    end
  end
end
