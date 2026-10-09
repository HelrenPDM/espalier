defmodule Espalier.Accounts.MailWorker do
  @moduledoc """
  Sends every account mail through Oban, so that response times reveal
  nothing about accounts (README section 6.10).

  Oban stores job arguments as plain JSON in `oban_jobs`, so the arguments
  carry only the kind, the user id, a count, a factor name, and addresses
  encrypted with `Espalier.Vault.encrypt!/1` and Base64
  (`docs/security/crypto-inventory.md`, "Values encrypted outside Ecto
  types"). The worker generates every e-mail token itself, inserts its
  hashed row and sends the link, so a raw token never reaches the database
  or the job table.

  A skipped job returns `:ok` and logs nothing about the address. A failed
  delivery logs a warning with the job id and the mail kind, without the
  address and without the reason, and returns the error, so Oban retries.
  """
  use Oban.Worker, queue: :mail, max_attempts: 5

  import Ecto.Query

  require Logger

  alias Espalier.Accounts
  alias Espalier.Accounts.{User, UserNotifier, UserToken}
  alias Espalier.Repo

  @kinds ~w(invitation signup change_email email_changed password_changed failed_attempts
            factor_added factor_removed recovery_codes_regenerated recovery_used
            authenticator_disabled recovery_instructions recovery_unavailable none)

  # Factor names of the job arguments, mapped without creating atoms.
  @factors %{
    "password" => :password,
    "passkey" => :passkey,
    "totp" => :totp,
    "recovery_code" => :recovery_code
  }

  @doc "Builds a job of `kind`; addresses in `args` must already be encrypted with `encrypt_arg/1`."
  def job(kind, args \\ %{}) when kind in @kinds do
    new(Map.put(args, :kind, kind))
  end

  @doc "Encrypts an address for the job arguments."
  @spec encrypt_arg(String.t()) :: String.t()
  def encrypt_arg(value) when is_binary(value) do
    value |> Espalier.Vault.encrypt!() |> Base.encode64()
  end

  @doc "Decrypts an address of the job arguments."
  @spec decrypt_arg(String.t()) :: String.t()
  def decrypt_arg(value) when is_binary(value) do
    value |> Base.decode64!() |> Espalier.Vault.decrypt!()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"kind" => kind} = args} = job) do
    case run(kind, args, job) do
      {:ok, _email} ->
        :ok

      :skip ->
        :ok

      {:error, _reason} ->
        Logger.warning("mail delivery failed: job #{job.id}, kind #{kind}")
        {:error, :delivery_failed}
    end
  end

  # Only the link of the latest recovery request works. Jobs can run out of
  # request order, because the mail queue runs five at a time and a failed
  # delivery retries later. The transaction locks the user row, and a job
  # yields to a newer recovery_instructions job of the same user; Oban job
  # ids follow the insert order of the requests.
  defp run("recovery_instructions", %{"user_id" => user_id}, job) do
    with %User{email: email} = user when is_binary(email) <- Accounts.get_user(user_id),
         true <- Accounts.local_account?(user),
         {:ok, token} <- replace_recovery_token(user, job) do
      UserNotifier.deliver_recovery_instructions(user, UserNotifier.recovery_url(token))
    else
      _ -> :skip
    end
  end

  defp run(kind, args, _job), do: run(kind, args)

  defp replace_recovery_token(user, job) do
    {token, row} = UserToken.build_email_token(user, :recovery_email, user.email)

    Repo.transact(fn ->
      Accounts.lock_user!(user)

      if newer_recovery_request?(user, job) do
        {:error, :superseded}
      else
        Repo.delete_all(
          from t in UserToken, where: t.user_id == ^user.id and t.context == :recovery_email
        )

        Repo.insert!(row)
        {:ok, token}
      end
    end)
  end

  # A job that Oban.Testing.perform_job/3 builds has no id and no successor.
  defp newer_recovery_request?(_user, %Oban.Job{id: nil}), do: false

  defp newer_recovery_request?(user, %Oban.Job{id: id}) do
    Repo.exists?(
      from j in Oban.Job,
        where: j.worker == ^inspect(__MODULE__) and j.id > ^id,
        where: j.state not in ["discarded", "cancelled"],
        where: fragment("?->>'kind'", j.args) == "recovery_instructions",
        where: fragment("?->>'user_id'", j.args) == ^user.id
    )
  end

  defp run("none", _args), do: :skip

  defp run("invitation", %{"user_id" => user_id}) do
    with %User{email: email} = user when is_binary(email) <- Accounts.get_user(user_id),
         true <- Accounts.invitable?(user) do
      send_invitation(user)
    else
      _ -> :skip
    end
  end

  defp run("signup", %{"email" => encrypted}) do
    email = decrypt_arg(encrypted)

    case Accounts.create_signup_user(email) do
      {:ok, user} -> send_invitation(user)
      {:error, _reason} -> :skip
    end
  end

  defp run("change_email", %{"user_id" => user_id, "email" => encrypted}) do
    new_email = decrypt_arg(encrypted)

    with %User{status: :active} = user <- Accounts.get_user(user_id),
         nil <- Accounts.get_user_by_email(new_email) do
      {token, row} =
        UserToken.build_email_token(user, :change_email, new_email, new_email: new_email)

      Repo.insert!(row)
      UserNotifier.deliver_change_email(new_email, token)
    else
      _ -> :skip
    end
  end

  defp run("email_changed", %{"email" => encrypted}) do
    encrypted |> decrypt_arg() |> UserNotifier.deliver_email_changed()
  end

  defp run("password_changed", %{"user_id" => user_id}) do
    case Accounts.get_user(user_id) do
      %User{email: email} = user when is_binary(email) ->
        UserNotifier.deliver_password_changed(user)

      _ ->
        :skip
    end
  end

  defp run("failed_attempts", %{"user_id" => user_id, "count" => count} = args) do
    factor = Map.get(@factors, args["factor"], :password)
    with_mailbox(user_id, &UserNotifier.deliver_failed_attempts(&1, count, factor))
  end

  defp run("factor_added", %{"user_id" => user_id, "factor" => factor}) do
    with_mailbox(user_id, &UserNotifier.deliver_factor_added(&1, Map.fetch!(@factors, factor)))
  end

  defp run("factor_removed", %{"user_id" => user_id, "factor" => factor}) do
    with_mailbox(user_id, &UserNotifier.deliver_factor_removed(&1, Map.fetch!(@factors, factor)))
  end

  defp run("recovery_codes_regenerated", %{"user_id" => user_id}) do
    with_mailbox(user_id, &UserNotifier.deliver_recovery_codes_regenerated/1)
  end

  defp run("recovery_used", %{"user_id" => user_id, "count" => remaining}) do
    with_mailbox(user_id, &UserNotifier.deliver_recovery_used(&1, remaining))
  end

  defp run("authenticator_disabled", %{"user_id" => user_id, "factor" => factor}) do
    with_mailbox(
      user_id,
      &UserNotifier.deliver_authenticator_disabled(&1, Map.fetch!(@factors, factor))
    )
  end

  defp run("recovery_unavailable", %{"user_id" => user_id}) do
    with_mailbox(user_id, &UserNotifier.deliver_recovery_unavailable/1)
  end

  defp with_mailbox(user_id, deliver) do
    case Accounts.get_user(user_id) do
      %User{email: email} = user when is_binary(email) -> deliver.(user)
      _ -> :skip
    end
  end

  defp send_invitation(user) do
    {token, row} = UserToken.build_email_token(user, :invite, user.email)
    Repo.insert!(row)
    UserNotifier.deliver_invitation(user, token)
  end
end
