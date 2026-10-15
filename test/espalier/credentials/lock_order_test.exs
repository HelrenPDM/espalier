defmodule Espalier.Credentials.LockOrderTest do
  @moduledoc """
  Task 0013, steps 10 and 12: `Espalier.Credentials.sweep/1` and
  `Espalier.Credentials.evaluate/2` lock the credential rows of one user in
  the same order, so the daily sweep and an evaluation that run at the same
  time both complete.

  The SQL sandbox serves every process of a test through one connection,
  so it cannot show a lock conflict between two transactions. The test runs
  each transaction on a connection of its own through
  `Ecto.Adapters.SQL.Sandbox.unboxed_run/2`, commits its rows and deletes
  them again on exit. The module is synchronous, so no sandboxed test sees
  these rows.

  The scenario: another user's credential is due for its notice, and a
  third transaction holds it. The user holds one credential due for its
  notice and one past its grace period, both in one program. The sweep
  starts and waits for the held row; the evaluation of the user starts;
  then the held row is released. With the rows locked in different orders,
  PostgreSQL ends one of the two transactions with `deadlock_detected`.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Espalier.Accounts.{Scope, User}
  alias Espalier.{AccountsFixtures, Credentials, CredentialsFixtures, Repo}
  alias Espalier.Catalog.{Program, Qualification}
  alias Espalier.Credentials.Credential

  # Long enough for a started transaction to reach its lock wait.
  @settle_ms 300

  defp unboxed(fun), do: Sandbox.unboxed_run(Repo, fun)

  setup do
    today = Date.utc_today()
    data = unboxed(fn -> insert_scenario!(today) end)
    on_exit(fn -> unboxed(fn -> delete_scenario!(data) end) end)
    Map.put(data, :today, today)
  end

  defp insert_scenario!(today) do
    suffix = System.unique_integer([:positive])

    program =
      Repo.insert!(%Program{
        slug: "lock-order-#{suffix}",
        title: "Lock order",
        locale: "en",
        status: :published,
        pack_version: "1.0.0"
      })

    [first, second] =
      for {code, position} <- Enum.with_index(["first", "second"], 1) do
        Repo.insert!(%Qualification{
          program_id: program.id,
          code: code,
          title: "Qualification #{code}",
          audience: "Everyone",
          unlocks: ["A task"],
          add_on: false,
          validity_kind: :months,
          validity_months: 12,
          refresher_mode: :update_unit,
          position: position
        })
      end
      |> Enum.sort_by(& &1.id)

    other = AccountsFixtures.user_fixture()
    user = AccountsFixtures.user_fixture()

    # Inserted in this order, so a scan of the notice condition meets the
    # held row of the other user first.
    held =
      CredentialsFixtures.credential_fixture(other, first, valid_until: Date.add(today, 5))

    notice =
      CredentialsFixtures.credential_fixture(user, first, valid_until: Date.add(today, 5))

    expiry =
      CredentialsFixtures.credential_fixture(user, second,
        status: :refresh_due,
        refresh_due_at: ~U[2026-01-01 00:00:00Z],
        valid_until: Date.add(today, -90)
      )

    %{
      program: program,
      qualifications: [first, second],
      users: [other, user],
      user: user,
      held: held,
      notice: notice,
      expiry: expiry
    }
  end

  defp delete_scenario!(data) do
    user_ids = Enum.map(data.users, & &1.id)
    credential_ids = Enum.map([data.held, data.notice, data.expiry], & &1.id)

    Repo.delete_all(
      from j in Oban.Job, where: fragment("?->>'credential_id'", j.args) in ^credential_ids
    )

    Repo.delete_all(from c in Credential, where: c.user_id in ^user_ids)
    Repo.delete_all(from q in Qualification, where: q.program_id == ^data.program.id)
    Repo.delete_all(from p in Program, where: p.id == ^data.program.id)
    Repo.delete_all(from u in User, where: u.id in ^user_ids)
  end

  # Runs `fun` on a connection of its own and returns its result, or the
  # message of an exception, such as a deadlock that PostgreSQL detected.
  defp concurrently(fun) do
    Task.async(fn ->
      unboxed(fn ->
        try do
          fun.()
        rescue
          exception -> {:raised, Exception.message(exception)}
        end
      end)
    end)
  end

  test "the sweep and an evaluation of the same user both complete", data do
    parent = self()

    holder =
      Task.async(fn ->
        unboxed(fn ->
          Repo.transact(fn ->
            Repo.one!(from c in Credential, where: c.id == ^data.held.id, lock: "FOR UPDATE")
            send(parent, :held)

            receive do
              :release -> {:ok, :released}
            end
          end)
        end)
      end)

    assert_receive :held, 5_000

    sweep = concurrently(fn -> Credentials.sweep(data.today) end)
    Process.sleep(@settle_ms)

    evaluation =
      concurrently(fn -> Credentials.evaluate(Scope.for_user(data.user), data.program) end)

    Process.sleep(@settle_ms)

    send(holder.pid, :release)
    assert {:ok, :released} = Task.await(holder, 10_000)

    assert {:ok, %{refresh_due: refresh_due, expired: expired}} = Task.await(sweep, 15_000)
    assert {:ok, []} = Task.await(evaluation, 15_000)

    assert data.expiry.id in Enum.map(expired, & &1.id)
    assert data.notice.id in Enum.map(refresh_due, & &1.id)
    assert data.held.id in Enum.map(refresh_due, & &1.id)
  end
end
