defmodule Espalier.Accounts.Bootstrap do
  @moduledoc """
  Grants `admin` to the addresses in `BOOTSTRAP_ADMIN_EMAILS` at every boot
  (README section 6.11, `docs/security/authentication.md`).

  An unknown address becomes a local user with a `manual` grant `admin` and
  an invitation. A known local account (active, no external identity, so no
  demo user either) receives the grant when it lacks it. Every other known
  account receives no grant and is skipped with a warning that names the
  user id: an e-mail claim of an identity provider never authorizes. With
  `LOCAL_ACCOUNTS=false`, unknown addresses are skipped with a warning.
  """

  require Logger

  alias Espalier.Accounts
  alias Espalier.Accounts.{Scope, User}

  @doc "The child spec of the boot task."
  def child_spec(_arg) do
    %{id: __MODULE__, start: {Task, :start_link, [&run/0]}, restart: :temporary}
  end

  @doc "Runs the bootstrap for the configured addresses."
  def run do
    run(Application.get_env(:espalier, :bootstrap_admin_emails, []))
  end

  @doc "Runs the bootstrap for `emails`."
  def run(emails) when is_list(emails) do
    Enum.each(emails, &bootstrap/1)
  end

  defp bootstrap(email) do
    scope = Scope.system()

    case Accounts.get_user_by_email(email) do
      nil ->
        invite(scope, email)

      %User{} = user ->
        if Accounts.local_account?(user) do
          {:ok, _grant} = Accounts.grant_role(scope, user, :admin)
        else
          Logger.warning("bootstrap admin skipped user #{user.id}: no active local account")
        end
    end
  end

  defp invite(scope, email) do
    if Application.get_env(:espalier, :local_accounts, true) do
      {:ok, user} = Accounts.invite_user(scope, %{email: email})
      {:ok, _grant} = Accounts.grant_role(scope, user, :admin)
    else
      Logger.warning("bootstrap admin skipped an unknown address: LOCAL_ACCOUNTS=false")
    end
  end
end
