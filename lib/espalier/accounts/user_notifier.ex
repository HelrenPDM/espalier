# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule Espalier.Accounts.UserNotifier do
  @moduledoc """
  Plain-text account mails in English. `Espalier.Accounts.MailWorker` calls
  these functions, so every mail goes out through Oban. Links are built from
  `PUBLIC_URL` and carry tokens in the URL fragment, which reaches neither
  the server log nor the `Referer` header. No mail contains a password, a
  code or a session token.
  """
  import Swoosh.Email

  alias Espalier.Mailer

  # Delivers the email using the application mailer.
  defp deliver(recipient, subject, body) do
    email = build(recipient, subject, body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  defp build(recipient, subject, body) do
    new()
    |> to(recipient)
    |> from(Application.get_env(:espalier, :mail_from, {"Espalier", "noreply@localhost"}))
    |> subject(subject)
    |> text_body(body)
  end

  defp link(path_and_fragment) do
    String.trim_trailing(Application.fetch_env!(:espalier, :public_url), "/") <> path_and_fragment
  end

  @doc "Delivers the invitation link, valid for 10 minutes."
  def deliver_invitation(user, token) do
    email = invitation_email(user, token)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc "Builds the invitation mail."
  def invitation_email(user, token) do
    build(user.email, "Your invitation to Espalier", """
    Hi #{user.display_name},

    You have been invited to Espalier. Open the link below within 10 minutes
    to set up your sign-in:

    #{link("/invite#token=" <> token)}

    The link works once. If you did not expect this invitation, ignore this
    message.
    """)
  end

  @doc "Delivers the confirmation link of an e-mail change to the new address."
  def deliver_change_email(new_email, token) do
    deliver(new_email, "Confirm your new e-mail address", """
    Hi,

    Open the link below within 10 minutes, while you are signed in, to use
    this address for your Espalier account:

    #{link("/account/email/confirm#token=" <> token)}

    If you did not request this change, ignore this message.
    """)
  end

  @doc "Tells the old address that the account address has changed."
  def deliver_email_changed(old_email) do
    deliver(old_email, "Your e-mail address was changed", """
    Hi,

    The e-mail address of your Espalier account was changed. Messages now go
    to the new address.

    If you did not make this change, contact your administrator.
    """)
  end

  @doc "Tells the user that the password has changed."
  def deliver_password_changed(user) do
    deliver(user.email, "Your password was changed", """
    Hi #{user.display_name},

    The password of your Espalier account was changed, and every other
    session of the account was ended.

    If you did not make this change, contact your administrator.
    """)
  end

  @doc "Tells the user about a sign-in after repeated failed attempts."
  def deliver_failed_attempts(user, count) do
    deliver(user.email, "Sign-in after failed attempts", """
    Hi #{user.display_name},

    Your Espalier account was signed in with the password after #{count}
    failed attempts.

    If this was not you, change your password and contact your administrator.
    """)
  end
end
