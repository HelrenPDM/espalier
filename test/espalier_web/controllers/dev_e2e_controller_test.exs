defmodule EspalierWeb.DevE2EControllerTest do
  @moduledoc """
  The seeding controller of the end-to-end tests (task 0011, step 16). The
  test environment mounts no development routes, so the tests call the
  actions directly; the last test checks that the router of this
  environment carries no `/api/dev` route.
  """
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts
  alias Espalier.Accounts.{MailWorker, Scope, UserToken}
  alias Espalier.Repo
  alias EspalierWeb.DevE2EController

  defp call(action, params, assigns \\ %{}) do
    conn = Phoenix.ConnTest.build_conn(:post, "/api/dev/e2e", params)
    conn = Enum.reduce(assigns, conn, fn {key, value}, conn -> assign(conn, key, value) end)
    DevE2EController.call(conn, DevE2EController.init(action))
  end

  test "invitations creates an invited user, enqueues the mail and answers 409 for a known address" do
    email = "e2e-#{System.unique_integer([:positive])}@example.test"

    assert call(:invitations, %{"email" => email}).status == 202

    user = Accounts.get_user_by_email(email)
    assert user.display_name == "E2E " <> email
    assert_enqueued(worker: MailWorker, args: %{"kind" => "invitation", "user_id" => user.id})

    conn = call(:invitations, %{"email" => email})
    assert json_response(conn, 409) == %{"error" => "user_exists"}
  end

  test "reset deletes the users of the listed providers only" do
    linked = user_fixture()
    external_identity_fixture(linked, provider_key: "oidc")
    other = user_fixture()
    external_identity_fixture(other, provider_key: "ldap")
    local = user_fixture()

    assert call(:reset, %{"provider_keys" => ["oidc"]}).status == 204

    assert Accounts.get_user(linked.id) == nil
    assert Accounts.get_user(other.id)
    assert Accounts.get_user(local.id)
  end

  test "reset answers 400 without a list of keys" do
    assert json_response(call(:reset, %{"provider_keys" => "oidc"}), 400) == %{
             "error" => "bad_request"
           }
  end

  test "age-recent-auth moves mfa_at of the current session 11 minutes back" do
    user = user_fixture()
    {_token, session} = session_fixture(user)
    scope = %{Scope.for_user(user) | session: session}

    assert call(:age_recent_auth, %{}, %{current_scope: scope}).status == 204

    aged = Repo.get!(UserToken, session.id)
    assert DateTime.diff(DateTime.utc_now(), aged.mfa_at, :second) in 659..662
    refute Scope.recent_auth?(%{scope | session: aged})
  end

  test "the router of the test environment has no development route" do
    paths = for route <- Phoenix.Router.routes(EspalierWeb.Router), do: route.path
    refute Enum.any?(paths, &String.starts_with?(&1, "/api/dev"))
  end
end
