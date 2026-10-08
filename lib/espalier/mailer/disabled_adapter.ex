defmodule Espalier.Mailer.DisabledAdapter do
  @moduledoc """
  Mail adapter of a production instance without `SMTP_HOST`. Every delivery
  fails with `{:error, :mail_disabled}`, so `Espalier.Accounts.MailWorker`
  logs it and no mail content reaches a log or a store.
  """
  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(_email, _config), do: {:error, :mail_disabled}
end
