defmodule Espalier.Media.RetentionWorker do
  @moduledoc """
  The retention of imported media (task 0018, step 8), daily in the queue
  `default`. It deletes each asset of origin `pack` that has not been
  updated for `unused_days` (`config :espalier, :media_retention`, default
  30) and that no program, draft or validated import uses. Each candidate
  is locked with `FOR UPDATE`, and its uses and `updated_at` are checked
  again in the same transaction, so an import or a publish that came
  between the selection and the deletion keeps the asset. The files are
  removed after the commit. Assets of origin `upload` stay until an author
  deletes them.
  """
  use Oban.Worker, queue: :default, max_attempts: 1

  import Ecto.Query

  alias Espalier.Media
  alias Espalier.Media.Asset
  alias Espalier.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    cutoff = DateTime.add(DateTime.utc_now(:second), -Media.unused_days() * 86_400, :second)

    from(a in Asset, where: a.origin == :pack and a.updated_at < ^cutoff, select: a.id)
    |> Repo.all()
    |> Enum.each(&delete_unused(&1, cutoff))

    :ok
  end

  # The row lock waits for a publish that holds the asset with FOR KEY SHARE.
  defp delete_unused(id, cutoff) do
    result = Repo.transact(fn -> delete_locked(id, cutoff) end, timeout: Media.lock_timeout())

    case result do
      {:ok, %Asset{} = asset} -> Media.remove_files(asset)
      {:ok, nil} -> :ok
    end
  end

  defp delete_locked(id, cutoff) do
    with %Asset{} = asset <- Repo.one(from a in Asset, where: a.id == ^id, lock: "FOR UPDATE"),
         true <- asset.origin == :pack and DateTime.before?(asset.updated_at, cutoff),
         %{programs: [], drafts: [], imports: []} <- Media.uses(asset) do
      Repo.delete!(asset)
      {:ok, asset}
    else
      _kept -> {:ok, nil}
    end
  end
end
