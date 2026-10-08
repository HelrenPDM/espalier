defmodule Espalier.Accounts.MailWorker do
  @moduledoc """
  Sends every account mail through Oban, so that response times reveal
  nothing about accounts (README section 6.10).

  Oban stores job arguments as plain JSON in `oban_jobs`, so the arguments
  carry only the kind, the user id, a count, and addresses encrypted with
  `Espalier.Vault.encrypt!/1` and Base64 (`docs/security/crypto-inventory.md`,
  "Values encrypted outside Ecto types"). The worker generates every e-mail
  token itself, inserts its hashed row and sends the link, so a raw token
  never reaches the database or the job table.

  A skipped job returns `:ok` and logs nothing about the address. A failed
  delivery logs a warning with the job id and the mail kind, without the
  address and without the reason, and returns the error, so Oban retries.
  """
  use Oban.Worker, queue: :mail, max_attempts: 5

  require Logger

  alias Espalier.Accounts
  alias Espalier.Accounts.{User, UserNotifier, UserToken}
  alias Espalier.Repo

  @kinds ~w(invitation signup change_email email_changed password_changed failed_attempts none)

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
    case run(kind, args) do
      {:ok, _email} ->
        :ok

      :skip ->
        :ok

      {:error, _reason} ->
        Logger.warning("mail delivery failed: job #{job.id}, kind #{kind}")
        {:error, :delivery_failed}
    end
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

  defp run("failed_attempts", %{"user_id" => user_id, "count" => count}) do
    case Accounts.get_user(user_id) do
      %User{email: email} = user when is_binary(email) ->
        UserNotifier.deliver_failed_attempts(user, count)

      _ ->
        :skip
    end
  end

  defp send_invitation(user) do
    {token, row} = UserToken.build_email_token(user, :invite, user.email)
    Repo.insert!(row)
    UserNotifier.deliver_invitation(user, token)
  end
end
