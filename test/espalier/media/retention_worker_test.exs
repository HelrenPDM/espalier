defmodule Espalier.Media.RetentionWorkerTest do
  @moduledoc """
  The retention of imported media of task 0018, step 8: an asset of origin
  `pack` that no program, draft or validated import uses and that has not
  been updated for `unused_days` is deleted with its files; every other
  asset stays.

  Each test runs with a store of its own, and the module is synchronous
  because it removes store files and changes the application environment.
  """
  use Espalier.DataCase, async: false

  alias Espalier.Catalog.PackImport
  alias Espalier.LearningFixtures
  alias Espalier.Media.{Asset, RetentionWorker, Store}
  alias Espalier.MediaFixtures
  alias Espalier.PackFixtures
  alias Espalier.Workbench.{PackDraft, PackDraftMedia}

  @day 86_400

  setup do
    MediaFixtures.media_env!()
    :ok
  end

  defp ago(seconds), do: DateTime.add(DateTime.utc_now(:second), -seconds, :second)

  defp run, do: assert(perform_job(RetentionWorker, %{}) == :ok)

  # A ready asset with a delivery file and a poster in the store.
  defp stored!(attrs) do
    sha256 = MediaFixtures.store_file!("delivery #{System.unique_integer()}", "svg")
    poster = MediaFixtures.store_file!("poster #{System.unique_integer()}", "webp")
    MediaFixtures.insert_asset!(Map.merge(%{sha256: sha256, poster_sha256: poster}, attrs))
  end

  defp exists?(%Asset{id: id}), do: Repo.exists?(from a in Asset, where: a.id == ^id)

  defp put_retention!(days) do
    previous = Application.fetch_env(:espalier, :media_retention)
    Application.put_env(:espalier, :media_retention, unused_days: days)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, :media_retention, value)
        :error -> Application.delete_env(:espalier, :media_retention)
      end
    end)
  end

  test "an unused pack asset older than unused_days is deleted with its files" do
    old = stored!(%{origin: :pack, updated_at: ago(31 * @day)})
    shared = MediaFixtures.insert_asset!(%{origin: :upload, poster_sha256: old.poster_sha256})

    run()

    refute exists?(old)
    refute File.exists?(Store.path(old.sha256, "svg"))
    # Another asset names the poster.
    assert exists?(shared)
    assert File.exists?(Store.path(old.poster_sha256, "webp"))
  end

  test "unused_days comes from config :espalier, :media_retention" do
    put_retention!(2)
    old = stored!(%{origin: :pack, updated_at: ago(3 * @day)})
    young = stored!(%{origin: :pack, updated_at: ago(1 * @day)})

    run()

    refute exists?(old)
    assert exists?(young)
  end

  test "a recently updated pack asset and an asset of origin upload stay" do
    recent = stored!(%{origin: :pack, updated_at: ago(29 * @day)})
    uploaded = stored!(%{origin: :upload, updated_at: ago(400 * @day)})

    run()

    assert exists?(recent)
    assert exists?(uploaded)
    assert File.exists?(Store.path(recent.sha256, "svg"))
    assert File.exists?(Store.path(uploaded.sha256, "svg"))
  end

  test "an old pack asset that a program, a draft or a validated import uses stays" do
    LearningFixtures.publish_demo!()
    mapping = MediaFixtures.media_for(PackFixtures.demo_path())
    in_program = Repo.get!(Asset, mapping["media/release-checks.svg"])

    in_draft = stored!(%{origin: :pack})
    draft = Repo.insert!(%PackDraft{title: "Draft", lock_version: 1})

    Repo.insert!(%PackDraftMedia{
      pack_draft_id: draft.id,
      media_asset_id: in_draft.id,
      path: "media/chart.svg"
    })

    in_import = stored!(%{origin: :pack})

    Repo.insert!(%PackImport{
      pack_key: "media-pack",
      pack_version: "1.0.0",
      status: :validated,
      report: %{},
      payload: %{},
      media_asset_ids: [in_import.id]
    })

    old = ago(60 * @day)
    ids = [in_program.id, in_draft.id, in_import.id]
    {3, _rows} = Repo.update_all(from(a in Asset, where: a.id in ^ids), set: [updated_at: old])

    run()

    for asset <- [in_program, in_draft, in_import] do
      assert exists?(asset)
      assert File.exists?(Store.path(asset.sha256, asset.ext))
    end
  end

  test "unused_days rejects a value that is no positive integer" do
    put_retention!(0)
    assert_raise ArgumentError, ~r/unused_days must be a positive integer/, fn -> run() end
  end
end

defmodule Espalier.Media.RetentionRecheckTest do
  @moduledoc """
  The re-check of `Espalier.Media.RetentionWorker` (task 0018, step 8): the
  worker locks each candidate with `FOR UPDATE` and checks its
  `updated_at` and its uses again in the same transaction, so an ingest or
  an attachment that comes between the selection and the deletion keeps
  the asset.

  A transaction on a connection of its own holds the row lock of the
  candidate, the worker starts and waits for it, and the transaction then
  changes the asset and commits. Each transaction runs through
  `Ecto.Adapters.SQL.Sandbox.unboxed_run/2`; the rows are committed and
  deleted again on exit, and the module is synchronous.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Espalier.Media.{Asset, RetentionWorker, Store}
  alias Espalier.MediaFixtures
  alias Espalier.Repo
  alias Espalier.Workbench.{PackDraft, PackDraftMedia}

  @wait_ms 10_000

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  # Runs `fun` in a transaction of its own in a task outside the sandbox.
  defp transact_async(fun), do: Task.async(fn -> unboxed(fn -> Repo.transact(fun) end) end)

  defp lock_row(asset, parent, change) do
    Repo.one!(from a in Asset, where: a.id == ^asset.id, lock: "FOR UPDATE")
    send(parent, :held)

    receive do
      :change -> {:ok, change.()}
    end
  end

  setup do
    MediaFixtures.media_env!()
    sha256 = MediaFixtures.store_file!("delivery #{System.unique_integer()}", "svg")
    old = DateTime.add(DateTime.utc_now(:second), -60 * 86_400, :second)

    asset =
      unboxed(fn ->
        MediaFixtures.insert_asset!(%{origin: :pack, sha256: sha256, updated_at: old})
      end)

    on_exit(fn ->
      unboxed(fn ->
        drafts =
          from(m in PackDraftMedia, where: m.media_asset_id == ^asset.id, select: m.pack_draft_id)
          |> Repo.all()

        Repo.delete_all(from d in PackDraft, where: d.id in ^drafts)
        Repo.delete_all(from a in Asset, where: a.id == ^asset.id)
      end)
    end)

    %{asset: asset}
  end

  # Holds the row lock of the asset until :change, then runs `change` in the
  # same transaction and commits.
  defp hold_row(asset, change) do
    parent = self()

    holder = transact_async(fn -> lock_row(asset, parent, change) end)

    assert_receive :held, @wait_ms
    holder
  end

  defp await_waiting(count, deadline \\ nil) do
    deadline = deadline || System.monotonic_time(:millisecond) + @wait_ms

    %{rows: [[waiting]]} =
      unboxed(fn ->
        Repo.query!("""
        SELECT count(*) FROM pg_stat_activity
        WHERE datname = current_database() AND wait_event_type = 'Lock'
          AND pid <> pg_backend_pid()
        """)
      end)

    cond do
      waiting >= count ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk("#{waiting} of #{count} transactions wait on a lock after #{@wait_ms} ms")

      true ->
        Process.sleep(20)
        await_waiting(count, deadline)
    end
  end

  defp run_against(holder) do
    worker =
      Task.async(fn -> unboxed(fn -> RetentionWorker.perform(%Oban.Job{args: %{}}) end) end)

    await_waiting(1)
    send(holder.pid, :change)
    assert {:ok, _changed} = Task.await(holder, @wait_ms)
    Task.await(worker, @wait_ms)
  end

  test "an asset whose updated_at an ingest renews while the worker waits stays", %{asset: asset} do
    holder =
      hold_row(asset, fn ->
        Repo.update_all(from(a in Asset, where: a.id == ^asset.id),
          set: [updated_at: DateTime.utc_now(:second)]
        )
      end)

    assert run_against(holder) == :ok
    assert unboxed(fn -> Repo.get(Asset, asset.id) end)
    assert File.exists?(Store.path(asset.sha256, "svg"))
  end

  test "an asset that a draft attaches while the worker waits stays", %{asset: asset} do
    holder =
      hold_row(asset, fn ->
        draft = Repo.insert!(%PackDraft{title: "Retention re-check", lock_version: 1})

        Repo.insert!(%PackDraftMedia{
          pack_draft_id: draft.id,
          media_asset_id: asset.id,
          path: "media/chart.svg"
        })
      end)

    assert run_against(holder) == :ok
    assert unboxed(fn -> Repo.get(Asset, asset.id) end)
    assert File.exists?(Store.path(asset.sha256, "svg"))
  end
end
