defmodule Espalier.Accounts.PurgeExpiredTokensWorker do
  @moduledoc """
  Daily job (Oban cron, 02:00 UTC) that deletes every token row past
  `expires_at`, every session row idle for `SESSION_IDLE_MINUTES` and
  every WebAuthn challenge past `expires_at`.
  """
  use Oban.Worker, queue: :default

  import Ecto.Query

  require Logger

  alias Espalier.Accounts.{AuthChallenge, UserToken}
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

    {challenges, _} = Repo.delete_all(from c in AuthChallenge, where: c.expires_at < ^now)

    Logger.info(
      "purged #{expired} expired token rows, #{idle} idle session rows and " <>
        "#{challenges} expired challenges"
    )

    :ok
  end
end
