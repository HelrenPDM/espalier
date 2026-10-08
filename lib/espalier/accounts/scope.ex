# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule Espalier.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  A scope carries the current user, the roles and the session row of the
  request. Every signed-in user holds the role `learner`. `system/0` is the
  scope of release functions and the boot task; no request reaches it.

  It is registered as the default scope in `config/config.exs`, so that
  `mix phx.gen.context` and `mix phx.gen.json` generate user-scoped code.
  """

  alias Espalier.Accounts.{User, UserToken}

  # Window of a recent second factor (ASVS 7.5.1).
  @recent_auth_minutes 10

  defstruct user: nil, roles: [], session: nil, system: false

  @type t :: %__MODULE__{
          user: struct() | nil,
          roles: [atom()],
          session: struct() | nil,
          system: boolean()
        }

  @doc """
  Creates a scope for the given user.

  Returns nil if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user, roles: [:learner]}
  end

  def for_user(nil), do: nil

  @doc """
  Creates the scope of a request from the user, its session row and its
  role grants. `learner` is always included.
  """
  def for_session(%User{} = user, %UserToken{} = session, grants) do
    roles = Enum.uniq([:learner | Enum.map(grants, & &1.role)])
    %__MODULE__{user: user, roles: roles, session: session}
  end

  @doc "The scope of release functions and the boot task."
  def system, do: %__MODULE__{system: true, roles: [:admin]}

  @doc "True when the scope holds `role`."
  def has_role?(%__MODULE__{roles: roles}, role), do: role in roles
  def has_role?(_scope, _role), do: false

  @doc "True when the scope holds the role `admin`."
  def admin?(scope), do: has_role?(scope, :admin)

  @doc "True when the session recorded a second factor within the last 10 minutes."
  def recent_auth?(scope, now \\ DateTime.utc_now())

  def recent_auth?(%__MODULE__{session: %UserToken{mfa_at: %DateTime{} = mfa_at}}, now) do
    DateTime.after?(recent_auth_until(mfa_at), now)
  end

  def recent_auth?(_scope, _now), do: false

  @doc "Returns the end of the recent-auth window for a second factor at `mfa_at`."
  def recent_auth_until(%DateTime{} = mfa_at),
    do: DateTime.add(mfa_at, @recent_auth_minutes, :minute)
end
