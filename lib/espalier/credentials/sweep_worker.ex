defmodule Espalier.Credentials.SweepWorker do
  @moduledoc """
  The daily credential sweep: the crontab of `config :espalier, Oban` runs
  it at 03:00 UTC, and it calls `Espalier.Credentials.sweep/1` with
  today's date (README section 7, domain rule 7).
  """
  use Oban.Worker, queue: :default

  alias Espalier.Credentials

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _moved} = Credentials.sweep(Date.utc_today())
    :ok
  end
end
