defmodule EspalierWeb.Me.EmailControllerTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts
  alias Espalier.Accounts.MailWorker

  setup %{conn: conn} do
    user = user_fixture()
    %{user: user, conn: log_in_user(conn, user)}
  end

  test "answers 403 reauth_required when the second factor is older than 10 minutes", %{
    user: user
  } do
    stale = DateTime.add(DateTime.utc_now(:second), -11, :minute)
    conn = api_conn() |> log_in_user(user, %{mfa_at: stale}) |> with_csrf_token()

    assert conn |> put("/api/me/email", %{email: "new@example.org"}) |> json_response(403) ==
             %{"error" => "reauth_required"}

    assert conn |> post("/api/me/email/confirm", %{token: "t"}) |> json_response(403) ==
             %{"error" => "reauth_required"}
  end

  test "mails the new address and the confirmation updates the address and mails the old one",
       %{conn: conn, user: user} do
    conn = conn |> with_csrf_token() |> put("/api/me/email", %{email: "next@example.org"})
    assert json_response(conn, 202) == %{"status" => "accepted"}

    [job] = all_enqueued(worker: MailWorker, args: %{"kind" => "change_email"})
    assert :ok = perform_job(MailWorker, job.args)

    token =
      receive do
        {:email, email} ->
          assert email.to == [{"", "next@example.org"}]
          assert email.text_body =~ "/account/email/confirm#token="
          extract_link_token(email)
      end

    conn =
      conn
      |> next_request()
      |> with_csrf_token()
      |> post("/api/me/email/confirm", %{token: token})

    assert json_response(conn, 200)["user"]["email"] == "next@example.org"
    assert Accounts.get_user_by_email("next@example.org").id == user.id

    [changed] = all_enqueued(worker: MailWorker, args: %{"kind" => "email_changed"})
    assert :ok = perform_job(MailWorker, changed.args)
    assert_email_sent(to: [{"", user.email}])
  end

  test "a taken address answers the same 202", %{conn: conn} do
    other = user_fixture()
    conn = conn |> with_csrf_token() |> put("/api/me/email", %{email: other.email})
    assert json_response(conn, 202) == %{"status" => "accepted"}
    assert [%{args: %{"kind" => "none"}}] = all_enqueued(worker: MailWorker)
  end

  test "an invalid token answers 400 invalid_token", %{conn: conn} do
    conn = conn |> with_csrf_token() |> post("/api/me/email/confirm", %{token: "garbage"})
    assert json_response(conn, 400) == %{"error" => "invalid_token"}
  end
end
