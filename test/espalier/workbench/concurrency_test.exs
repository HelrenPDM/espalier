defmodule Espalier.Workbench.ConcurrencyTest do
  @moduledoc """
  Task 0016a, steps 4, 5 and 14 (bullets "Schemas and limits" and
  "Optimistic locking"; ASVS 2.3.2 and 2.3.3): two creations that race for
  the last free draft give one draft and one `:draft_limit`, because each
  creation counts and inserts under the transaction-scoped advisory lock
  `hashtext('espalier.pack_drafts')`; and two file updates that race with
  the same `lock_version` give one change and one `{:stale_draft, 2}`,
  because each change locks the draft row with `FOR UPDATE` before it
  compares the version.

  The SQL sandbox serves every process of a test through one connection,
  so it cannot show a lock conflict between two transactions. The test runs
  each transaction on a connection of its own through
  `Ecto.Adapters.SQL.Sandbox.unboxed_run/2`, commits its rows and deletes
  them again on exit, as `Espalier.Credentials.LockOrderTest` does. The
  module is synchronous, so no sandboxed test sees these rows.

  To make the race certain, a third transaction holds the lock that both
  changes need, both changes start and wait for it, and the test releases
  it only when the database reports both of them waiting on a lock.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Espalier.Accounts.{Scope, User}
  alias Espalier.{AccountsFixtures, Repo, Workbench}
  alias Espalier.Audit.AuditEvent
  alias Espalier.Workbench.{PackDraft, PackDraftFile}

  @wait_ms 10_000

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  setup do
    user = unboxed(fn -> AccountsFixtures.user_fixture() end)
    on_exit(fn -> unboxed(fn -> delete_rows!(user) end) end)
    %{user: user, scope: %{Scope.for_user(user) | roles: [:learner, :author]}}
  end

  # Every draft of these tests carries the test user in created_by_id, the
  # drafts that the test inserts directly included.
  defp delete_rows!(user) do
    draft_ids = Repo.all(from d in PackDraft, where: d.created_by_id == ^user.id, select: d.id)

    Repo.delete_all(
      from e in AuditEvent,
        where: e.subject_id in ^draft_ids or e.subject_id == ^user.id or e.actor_id == ^user.id
    )

    Repo.delete_all(from d in PackDraft, where: d.id in ^draft_ids)
    Repo.delete_all(from u in User, where: u.id == ^user.id)
  end

  defp put_drafts_setting(value) do
    previous = Application.fetch_env(:espalier, :pack_drafts)
    Application.put_env(:espalier, :pack_drafts, value)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, :pack_drafts, value)
        :error -> Application.delete_env(:espalier, :pack_drafts)
      end
    end)
  end

  # Runs `lock_fun` in a transaction on a connection of its own, which holds
  # the lock that `lock_fun` takes until the test sends :release, and
  # returns the task once the lock is held.
  defp hold(lock_fun) do
    parent = self()
    holder = Task.async(fn -> unboxed(fn -> hold_transaction(lock_fun, parent) end) end)
    assert_receive :held, @wait_ms
    holder
  end

  defp hold_transaction(lock_fun, parent) do
    Repo.transact(fn ->
      lock_fun.()
      send(parent, :held)

      receive do
        :release -> {:ok, :released}
      end
    end)
  end

  defp release(holder) do
    send(holder.pid, :release)
    assert {:ok, :released} = Task.await(holder, @wait_ms)
  end

  # Runs `fun` on a connection of its own.
  defp concurrently(fun), do: Task.async(fn -> unboxed(fun) end)

  # Waits until `count` backends of this database wait on a heavyweight
  # lock, a row lock or an advisory lock.
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

  test "two concurrent creations at max_drafts/0 minus one drafts give one draft and one draft_limit",
       %{scope: scope, user: user} do
    existing = unboxed(fn -> Repo.aggregate(PackDraft, :count) end)
    max = existing + 3
    put_drafts_setting(max_drafts: max, max_parallel_checks: 2)
    now = DateTime.utc_now(:second)

    rows =
      for n <- 1..2 do
        %{
          id: Ecto.UUID.generate(),
          title: "Filler #{n}",
          lock_version: 1,
          created_by_id: user.id,
          inserted_at: now,
          updated_at: now
        }
      end

    unboxed(fn -> {2, nil} = Repo.insert_all(PackDraft, rows) end)
    assert unboxed(fn -> Repo.aggregate(PackDraft, :count) end) == max - 1

    holder =
      hold(fn ->
        Repo.query!("SELECT pg_advisory_xact_lock(hashtext('espalier.pack_drafts'))")
      end)

    first = concurrently(fn -> Workbench.create_empty(scope, "First") end)
    second = concurrently(fn -> Workbench.create_empty(scope, "Second") end)
    await_waiting(2)
    release(holder)

    results = Enum.map([first, second], &Task.await(&1, @wait_ms))

    assert [{:error, :draft_limit}, {:ok, %PackDraft{} = draft}] =
             Enum.sort_by(results, &match?({:ok, _draft}, &1))

    assert draft.title in ["First", "Second"]
    assert draft.created_by_id == user.id

    unboxed(fn ->
      assert Repo.aggregate(PackDraft, :count) == max

      assert Repo.aggregate(from(f in PackDraftFile, where: f.pack_draft_id == ^draft.id), :count) ==
               6

      assert [event] =
               Repo.all(
                 from e in AuditEvent,
                   where: e.action == "pack_draft.created" and e.actor_id == ^user.id
               )

      assert event.subject_id == draft.id
    end)
  end

  test "two concurrent updates with the same lock_version give one change and one stale_draft",
       %{scope: scope} do
    {:ok, draft} = unboxed(fn -> Workbench.create_empty(scope, "New pack") end)
    file = Enum.find(draft.files, &(&1.path == "stations.yaml"))
    assert draft.lock_version == 1

    holder =
      hold(fn ->
        Repo.one!(from d in PackDraft, where: d.id == ^draft.id, lock: "FOR UPDATE")
      end)

    first = concurrently(fn -> Workbench.update_file(scope, draft.id, file.id, "first\n", 1) end)

    second =
      concurrently(fn -> Workbench.update_file(scope, draft.id, file.id, "second\n", 1) end)

    await_waiting(2)
    release(holder)

    results = Enum.map([first, second], &Task.await(&1, @wait_ms))

    assert [{:error, {:stale_draft, 2}}, {:ok, %PackDraft{lock_version: 2}}] =
             Enum.sort_by(results, &match?({:ok, _draft}, &1))

    winner =
      if match?({:ok, _draft}, hd(results)), do: "first\n", else: "second\n"

    unboxed(fn ->
      assert Repo.get!(PackDraft, draft.id).lock_version == 2
      assert Repo.get!(PackDraftFile, file.id).content == winner
    end)
  end
end
