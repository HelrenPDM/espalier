defmodule EspalierWeb.DevE2EController do
  @moduledoc """
  Seeding routes for the Playwright tests of task 0011 under
  `/api/dev/e2e`. The module compiles in development and test only
  (`elixirc_paths/1` in `mix.exs`), and the router mounts it only with
  `dev_routes: true`, which `config/dev.exs` alone sets. A release contains
  neither the module nor its routes.

  `invitations/2` is the one place where a request reaches
  `Espalier.Accounts.Scope.system/0`; task 0004 keeps that scope away from
  every other request.
  """
  use EspalierWeb, :controller

  import Ecto.Query

  alias Espalier.Accounts
  alias Espalier.Accounts.{Demo, ExternalIdentity, Scope, User, UserToken}
  alias Espalier.Repo

  @doc "Invites `email` as `Accounts.invite_user/2` does for an admin: 202, or 409 for a known address."
  def invitations(conn, %{"email" => email}) when is_binary(email) do
    case Accounts.invite_user(Scope.system(), %{email: email, display_name: "E2E " <> email}) do
      {:ok, _user} -> send_resp(conn, :accepted, "")
      {:error, :user_exists} -> conn |> put_status(:conflict) |> json(%{error: "user_exists"})
    end
  end

  def invitations(conn, _params), do: bad_request(conn)

  @doc "Deletes every user that holds an external identity of one of `provider_keys`."
  def reset(conn, %{"provider_keys" => keys}) when is_list(keys) do
    if Enum.all?(keys, &is_binary/1) do
      user_ids =
        from i in ExternalIdentity, where: i.provider_key in ^keys, select: i.user_id

      Repo.delete_all(from u in User, where: u.id in subquery(user_ids))
      send_resp(conn, :no_content, "")
    else
      bad_request(conn)
    end
  end

  def reset(conn, _params), do: bad_request(conn)

  @doc """
  Deletes the demo users of `slots` (task 0014), so that a spec starts them
  without records while the specs that run beside it keep their own slots.
  """
  def reset_demo(conn, %{"slots" => slots}) when is_list(slots) and slots != [] do
    if Enum.all?(slots, &(is_integer(&1) and &1 in Demo.slots())) do
      user_ids = for slot <- slots, %User{id: id} <- [Demo.get_user(slot)], do: id
      Repo.delete_all(from u in User, where: u.id in ^user_ids)
      send_resp(conn, :no_content, "")
    else
      bad_request(conn)
    end
  end

  def reset_demo(conn, _params), do: bad_request(conn)

  @doc """
  Moves `mfa_at` of the current session row 11 minutes into the past, so
  the next change behind `require_recent_auth/2` answers 403
  `reauth_required`.
  """
  def age_recent_auth(conn, _params) do
    case conn.assigns[:current_scope] do
      %Scope{session: %UserToken{id: id}} ->
        aged = DateTime.add(DateTime.utc_now(:second), -11, :minute)
        Repo.update_all(from(t in UserToken, where: t.id == ^id), set: [mfa_at: aged])
        send_resp(conn, :no_content, "")

      _other ->
        conn |> put_status(:unauthorized) |> json(%{error: "unauthenticated"})
    end
  end

  defp bad_request(conn), do: conn |> put_status(:bad_request) |> json(%{error: "bad_request"})
end
