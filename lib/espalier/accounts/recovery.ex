defmodule Espalier.Accounts.Recovery do
  @moduledoc """
  The recovery pathway of local accounts (README sections 6.2 and 6.6): a
  saved recovery code and a link sent by e-mail lead to a `recovery`
  session, which reaches only the enrollment routes. Enrolling a new factor
  completes the recovery (`Espalier.Accounts.Factors.complete_enrollment/3`).

  The start answers the same for known and unknown addresses, and every
  request causes one lookup and one job insert (ASVS 6.3.8). The worker
  creates the e-mail token, so no raw token reaches the database or the job
  table, and only the link of the latest request works (ASVS 6.6.2).
  """

  import Ecto.Query

  alias Espalier.Accounts

  alias Espalier.Accounts.{
    ExternalIdentity,
    Factors,
    MailWorker,
    RecoveryCode,
    RecoveryCodes,
    User,
    UserToken
  }

  alias Espalier.Repo

  @doc """
  Handles `POST /api/auth/recovery/start`: one lookup by `email_hash` and one
  job insert. An active local user with unused recovery codes receives the
  link (`recovery_instructions`), one without codes a mail about the
  admin-assisted reset (`recovery_unavailable`), and every other address the
  no-op job `none`. Always returns `:ok`.
  """
  def start(email) when is_binary(email) do
    found =
      Repo.one(
        from u in User,
          as: :user,
          where: u.email_hash == ^Accounts.normalize_email(email),
          select:
            {u.id, u.status,
             exists(
               from i in ExternalIdentity, where: i.user_id == parent_as(:user).id, select: 1
             ),
             exists(
               from r in RecoveryCode,
                 where: r.user_id == parent_as(:user).id and is_nil(r.used_at),
                 select: 1
             )}
      )

    job =
      case found do
        {user_id, :active, false, true} ->
          MailWorker.job("recovery_instructions", %{user_id: user_id})

        {user_id, :active, false, false} ->
          MailWorker.job("recovery_unavailable", %{user_id: user_id})

        _ ->
          MailWorker.job("none")
      end

    Oban.insert!(job)
    :ok
  end

  def start(_email), do: :ok

  @doc """
  Resolves a recovery e-mail token by hash, context and age to its active
  local user. The token must have been sent to the user's current address.
  Returns `{:ok, user}` or `:error`.
  """
  def resolve_token(token, now \\ DateTime.utc_now()) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, :recovery_email, now),
         {%User{} = user, _row} <-
           Repo.one(
             from [t, u] in query,
               where: t.sent_to_hash == u.email_hash and u.status == :active
           ),
         true <- Accounts.local_account?(user) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  @doc """
  Verifies a saved recovery code for `user` behind the failure counter of
  kind `:recovery_code`. On success it deletes the user's recovery e-mail
  tokens and mails "recovery used". Returns `{:ok, remaining}` or
  `{:error, reason}`; a failure leaves the e-mail token valid.
  """
  def verify(%User{} = user, code, meta) do
    with {:ok, remaining} <-
           Factors.verify(user, :recovery_code, fn -> RecoveryCodes.use(user, code) end, meta) do
      Repo.delete_all(
        from t in UserToken, where: t.user_id == ^user.id and t.context == :recovery_email
      )

      Oban.insert!(MailWorker.job("recovery_used", %{user_id: user.id, count: remaining}))
      {:ok, remaining}
    end
  end
end
