defmodule EspalierWeb.Auth.InvitationControllerTest do
  # Switches SIGNUP and LOCAL_ACCOUNTS for the whole node.
  use EspalierWeb.ConnCase, async: false

  alias Espalier.Accounts
  alias Espalier.Accounts.MailWorker

  defp request(conn, email) do
    conn |> with_csrf_token() |> post("/api/auth/invitations", %{email: email})
  end

  describe "POST /api/auth/invitations" do
    test "answers 404 with SIGNUP=closed", %{conn: conn} do
      put_setting(:signup, :closed)

      assert conn |> request(unique_user_email()) |> json_response(404) == %{
               "error" => "not_found"
             }

      refute_enqueued(worker: MailWorker)
    end

    test "known, unknown and listed-domain addresses get the same answer and one job each", %{
      conn: conn
    } do
      put_setting(:signup, :domain)
      put_setting(:signup_domains, ["listed.example.org"])
      known = unconfirmed_user_fixture()

      bodies =
        for email <- [known.email, "nobody@example.org", "new@listed.example.org"] do
          conn = request(conn, email)
          assert conn.status == 202
          json_response(conn, 202)
        end

      assert Enum.uniq(bodies) == [%{"status" => "accepted"}]

      kinds = for job <- all_enqueued(worker: MailWorker), do: job.args["kind"]
      assert Enum.sort(kinds) == ["invitation", "none", "signup"]
    end

    test "the signup job creates the user and sends the invitation", %{conn: conn} do
      put_setting(:signup, :domain)
      put_setting(:signup_domains, ["listed.example.org"])
      request(conn, "new@listed.example.org")

      [job] = all_enqueued(worker: MailWorker)
      refute JSON.encode!(job.args) =~ "listed.example.org"
      assert :ok = perform_job(MailWorker, job.args)

      user = Accounts.get_user_by_email("new@listed.example.org")
      assert user.display_name == "new"
      assert_email_sent(to: [{"", "new@listed.example.org"}])
    end

    test "with SIGNUP=invite an unknown address of a listed domain gets no account", %{conn: conn} do
      put_setting(:signup, :invite)
      put_setting(:signup_domains, ["listed.example.org"])
      request(conn, "new@listed.example.org")
      assert [%{args: %{"kind" => "none"}}] = all_enqueued(worker: MailWorker)
    end
  end

  describe "POST /api/auth/invitations/accept" do
    test "opens an enrollment session that only reaches enrollment routes", %{conn: conn} do
      user = unconfirmed_user_fixture()
      {token, _row} = email_token_fixture(user, :invite)

      conn = conn |> with_csrf_token() |> post("/api/auth/invitations/accept", %{token: token})
      body = json_response(conn, 200)
      assert body["session"]["strength"] == "enrollment"
      assert body["session"]["auth_methods"] == ["email_code"]
      assert body["user"]["id"] == user.id

      conn = conn |> next_request() |> get("/api/me/sessions")
      assert json_response(conn, 403) == %{"error" => "enrollment_required"}
    end

    test "a used or invalid token answers 400 invalid_token", %{conn: conn} do
      user = unconfirmed_user_fixture()
      {token, _row} = email_token_fixture(user, :invite)
      {:ok, _user} = Accounts.accept_invitation(token)

      for value <- [token, "garbage", nil] do
        conn = conn |> with_csrf_token() |> post("/api/auth/invitations/accept", %{token: value})
        assert json_response(conn, 400) == %{"error" => "invalid_token"}
      end
    end
  end

  test "LOCAL_ACCOUNTS=false answers 404 on the local sign-in routes", %{conn: conn} do
    put_setting(:local_accounts, false)
    put_setting(:signup, :invite)

    for {path, body} <- [
          {"/api/auth/password", %{email: "x@example.org", password: "y"}},
          {"/api/auth/invitations", %{email: "x@example.org"}},
          {"/api/auth/invitations/accept", %{token: "t"}}
        ] do
      conn = conn |> with_csrf_token() |> post(path, body)
      assert json_response(conn, 404) == %{"error" => "not_found"}, path
    end
  end
end
