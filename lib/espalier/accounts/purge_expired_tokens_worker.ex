defmodule Espalier.Accounts.PurgeExpiredTokensWorker do
  @moduledoc """
  Daily job (Oban cron, 02:00 UTC) that deletes every token row past
  `expires_at` and every session row idle for `SESSION_IDLE_MINUTES`.
  """
  use Oban.Worker, queue: :default

  import Ecto.Query

  require Logger

  alias Espalier.Accounts.UserToken
  alias Espalier.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    idle_minutes = Application.get_env(:espalier, :session_idle_minutes, 60)
    idle_since = DateTime.add(now, -idle_minutes, :minute)

    {expired, _} = Repo.delete_all(from t in UserToken, where: t.expires_at <= ^now)

    {idle, _} =
      Repo.delete_all(
        from t in UserToken, where: t.context == :session and t.last_seen_at <= ^idle_since
      )

    Logger.info("purged #{expired} expired token rows and #{idle} idle session rows")
    :ok
  end
end
