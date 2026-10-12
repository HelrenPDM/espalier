defmodule EspalierWeb.Admin.UserAdminJSON do
  @moduledoc """
  The user views of the admin area (task 0015): id, display name, status,
  roles, grants, `last_login_at`, `enrolled` and the provider keys of the
  external identities. A view carries no address and no subject (ASVS
  15.3.1).
  """

  alias Espalier.Accounts.RoleGrant

  @doc "Renders one page of users."
  def index(%{entries: entries, page: page, per_page: per_page, total: total}) do
    %{users: Enum.map(entries, &user/1), page: page, per_page: per_page, total: total}
  end

  @doc "Renders the users with a grant beyond `learner`."
  def holders(%{entries: entries}), do: %{users: Enum.map(entries, &user/1)}

  @doc "Renders one entry of `Espalier.Accounts.list_users/2`."
  def user(%{user: user, grants: grants, roles: roles} = entry) do
    %{
      id: user.id,
      display_name: user.display_name,
      status: user.status,
      roles: roles,
      last_login_at: user.last_login_at,
      enrolled: entry.enrolled,
      provider_keys: entry.provider_keys,
      grants: Enum.map(grants, &grant/1)
    }
  end

  @doc "Renders a role grant."
  def grant(%RoleGrant{} = grant) do
    %{
      id: grant.id,
      user_id: grant.user_id,
      role: grant.role,
      source: grant.source,
      provider_key: grant.provider_key
    }
  end
end
