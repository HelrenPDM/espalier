defmodule EspalierWeb.Plugs.RequireAdminPasskey do
  @moduledoc """
  The passkey gate of the admin routes (README section 6.11, task 0015).

  While `ADMIN_REQUIRE_PASSKEY=true`, the default, an admin reaches the
  routes of the pipelines `:admin` and `:admin_write` only with a passkey
  (`Espalier.Accounts.Factors.holds_passkey?/1`). Without one, the plug
  answers 403 `{"error":"passkey_required"}`, halts and logs `authz_fail`
  with the reason `passkey_required` (ASVS 16.3.2). The account settings
  under `/api/me` stay open, so the admin enrolls a passkey there.

  The plug runs after `require_role`, so it sees a signed-in admin only.
  """
  @behaviour Plug

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  alias Espalier.Accounts.{Factors, Scope}
  alias Espalier.SecurityLog

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    if Application.fetch_env!(:espalier, :admin_require_passkey) and not passkey?(conn) do
      SecurityLog.event(:authz_fail, %{
        user_id: user_id(conn),
        ip: conn.remote_ip,
        reason: "passkey_required"
      })

      conn
      |> put_status(:forbidden)
      |> json(%{error: "passkey_required"})
      |> halt()
    else
      conn
    end
  end

  defp passkey?(conn) do
    case conn.assigns[:current_scope] do
      %Scope{user: %{id: _id} = user} -> Factors.holds_passkey?(user)
      _other -> false
    end
  end

  defp user_id(conn) do
    case conn.assigns[:current_scope] do
      %Scope{user: %{id: id}} -> id
      _other -> nil
    end
  end
end
