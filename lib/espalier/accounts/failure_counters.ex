defmodule Espalier.Accounts.FailureCounters do
  @moduledoc """
  Durable counters of consecutive failures per user and authenticator
  (README section 6.10, ASVS 6.3.1).

  From the fifth consecutive failure, the authenticator is locked for
  `min(30 * 2^(n - 5), 3600)` seconds after failure `n`. The fiftieth
  failure disables it, below the NIST limit of 100. A locked or disabled
  authenticator rejects an attempt without verification and without
  counting it. A success resets the count and the lock; `disabled_at` is
  cleared only by a completed recovery (0005) or by an admin (0015). A
  locked password leaves passkey sign-in available, which is the protection
  against malicious lockout.

  Directory accounts (task 0007, step 15) follow their own policy, so that
  the platform stays below the directory's lockout threshold: each attempt
  reserves a count before its bind (`reserve_directory/5`), the count
  `AUTH_<KEY>_FAILURE_LIMIT` locks the account for
  `AUTH_<KEY>_LOCK_MINUTES`, and the fiftieth failure disables it until
  `reset_directory/3` or `reset_directory_for_user/2` clears the row.
  """

  import Ecto.Query

  alias Espalier.Accounts.{ExternalIdentity, FailureCounter, Scope}
  alias Espalier.{Audit, Repo}
  alias Espalier.SecurityLog

  @lock_from 5
  @disable_at 50
  @base_seconds 30
  @max_seconds 3600

  @doc "The failure that disables an authenticator."
  def disable_at, do: @disable_at

  @doc "Returns `:ok`, `{:locked, until}` or `:disabled` for the authenticator `kind` of `user`."
  def check(user, kind, now \\ DateTime.utc_now()) do
    case Repo.get_by(FailureCounter, user_id: user.id, authenticator: kind) do
      nil ->
        :ok

      %FailureCounter{disabled_at: %DateTime{}} ->
        :disabled

      %FailureCounter{locked_until: %DateTime{} = until} ->
        if DateTime.after?(until, now), do: {:locked, until}, else: :ok

      %FailureCounter{} ->
        :ok
    end
  end

  @doc """
  Counts a failure atomically and sets the lock or the disable mark.
  Returns `{:ok, counter}`.
  """
  def record_failure(user, kind, now \\ DateTime.utc_now()) do
    stamp = DateTime.truncate(now, :second)

    {:ok, counter} =
      Repo.insert(
        %FailureCounter{
          user_id: user.id,
          authenticator: kind,
          consecutive_failures: 1,
          inserted_at: stamp,
          updated_at: stamp
        },
        on_conflict: [inc: [consecutive_failures: 1], set: [updated_at: stamp]],
        conflict_target: [:user_id, :authenticator],
        returning: true
      )

    n = counter.consecutive_failures
    changes = lock_changes(counter, n, stamp)

    counter =
      if changes == [] do
        counter
      else
        counter |> Ecto.Changeset.change(changes) |> Repo.update!()
      end

    log(user, kind, n)
    {:ok, counter}
  end

  defp lock_changes(_counter, n, _now) when n < @lock_from, do: []

  defp lock_changes(counter, n, now) do
    seconds = min(@base_seconds * Integer.pow(2, n - @lock_from), @max_seconds)
    locked = [locked_until: DateTime.add(now, seconds, :second)]

    if n >= @disable_at and is_nil(counter.disabled_at) do
      Keyword.put(locked, :disabled_at, now)
    else
      locked
    end
  end

  defp log(user, kind, @lock_from) do
    SecurityLog.event(:authn_login_fail_max, %{user_id: user.id, factor: kind, count: @lock_from})
  end

  defp log(user, kind, @disable_at) do
    SecurityLog.event(:authn_login_lock, %{user_id: user.id, factor: kind, count: @disable_at})
  end

  defp log(_user, _kind, _n), do: :ok

  @doc """
  Sets the count of the authenticator `kind` of `user` to 0 and clears the
  lock. Returns the count before the reset.
  """
  def reset(user, kind) do
    query =
      from c in FailureCounter,
        where: c.user_id == ^user.id and c.authenticator == ^kind,
        select: c.consecutive_failures

    case Repo.one(query) do
      nil ->
        0

      0 ->
        0

      previous ->
        Repo.update_all(query |> exclude(:select),
          set: [consecutive_failures: 0, locked_until: nil, updated_at: DateTime.utc_now(:second)]
        )

        previous
    end
  end

  @doc """
  Sets the count to 0 and clears the lock and the disable mark on every
  counter of `user` with one update. A completed recovery calls it (task
  0005), which re-enables disabled authenticators.
  """
  def clear_all(user) do
    {count, _} =
      Repo.update_all(
        from(c in FailureCounter, where: c.user_id == ^user.id),
        set: [
          consecutive_failures: 0,
          locked_until: nil,
          disabled_at: nil,
          updated_at: DateTime.utc_now(:second)
        ]
      )

    count
  end

  ## Directory accounts (task 0007, step 15)

  @doc """
  Reserves one attempt of the directory account `subject` at the LDAP
  provider `provider_key` before its bind, so concurrent requests cannot
  pass the check together.

  In one transaction it creates the row if needed, locks it, and refuses
  the attempt with `{:error, :counter_disabled}` or `{:error, :locked}`.
  Otherwise it raises the count to `n`, locks the row for `period` minutes
  when `n >= limit`, and returns `{:ok, reservation}` with `id`, `count`,
  `limit`, `previous_locked_until` and `locked_until`. The row lock never
  spans a directory call.
  """
  def reserve_directory(provider_key, subject, limit, period, now \\ DateTime.utc_now())
      when is_binary(provider_key) and is_binary(subject) do
    stamp = DateTime.truncate(now, :second)
    hash_input = directory_hash_input(provider_key, subject)

    Repo.transact(fn ->
      Repo.insert!(
        %FailureCounter{
          authenticator: :ldap,
          provider_key: provider_key,
          subject_hash: hash_input,
          consecutive_failures: 0,
          inserted_at: stamp,
          updated_at: stamp
        },
        on_conflict: :nothing,
        conflict_target:
          {:unsafe_fragment,
           "(authenticator, provider_key, subject_hash) WHERE subject_hash IS NOT NULL"}
      )

      counter =
        Repo.one!(
          from c in directory_query(provider_key, hash_input),
            lock: "FOR UPDATE"
        )

      cond do
        counter.disabled_at != nil ->
          {:error, :counter_disabled}

        counter.locked_until != nil and DateTime.after?(counter.locked_until, now) ->
          {:error, :locked}

        true ->
          reserve(counter, limit, period, stamp)
      end
    end)
  end

  defp reserve(counter, limit, period, stamp) do
    n = counter.consecutive_failures + 1

    locked_until =
      if n >= limit, do: DateTime.add(stamp, period, :minute), else: counter.locked_until

    counter
    |> Ecto.Changeset.change(
      consecutive_failures: n,
      locked_until: locked_until,
      updated_at: stamp
    )
    |> Repo.update!()

    {:ok,
     %{
       id: counter.id,
       count: n,
       limit: limit,
       previous_locked_until: counter.locked_until,
       locked_until: locked_until
     }}
  end

  @doc "Deletes the row of a reservation after a successful bind."
  def directory_succeeded(%{id: id}) do
    Repo.delete_all(from c in FailureCounter, where: c.id == ^id)
    :ok
  end

  @doc """
  Keeps the reserved count after a wrong password. Returns `:disabled` and
  sets `disabled_at` from the fiftieth failure, `:limit_reached` when the
  count equals the limit, and `:counted` otherwise.
  """
  def directory_failed(%{id: id, count: count, limit: limit}, now \\ DateTime.utc_now()) do
    cond do
      count >= @disable_at ->
        Repo.update_all(
          from(c in FailureCounter, where: c.id == ^id and is_nil(c.disabled_at)),
          set: [
            disabled_at: DateTime.truncate(now, :second),
            updated_at: DateTime.utc_now(:second)
          ]
        )

        :disabled

      count == limit ->
        :limit_reached

      true ->
        :counted
    end
  end

  @doc """
  Gives back a reservation whose attempt failed for another reason than a
  wrong password: lowers the count by one, not below 0, and restores the
  lock from before the reservation when the row still holds the lock of
  this reservation, or when the count falls below the limit, because a
  later concurrent reservation may have set the lock. A missing row means
  that a concurrent success deleted it.
  """
  def release_directory(%{id: id} = reservation) do
    {:ok, _result} =
      Repo.transact(fn ->
        case Repo.one(from c in FailureCounter, where: c.id == ^id, lock: "FOR UPDATE") do
          nil -> {:ok, :gone}
          counter -> {:ok, give_back(counter, reservation)}
        end
      end)

    :ok
  end

  defp give_back(counter, reservation) do
    count = max(counter.consecutive_failures - 1, 0)
    changes = [consecutive_failures: count]

    changes =
      if count < reservation.limit or counter.locked_until == reservation.locked_until,
        do: Keyword.put(changes, :locked_until, reservation.previous_locked_until),
        else: changes

    counter |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  @doc """
  Deletes the directory counter of `subject` at `provider_key`. Requires the
  role `admin` (`Scope.system/0` holds it) and returns `:ok`,
  `{:error, :not_found}` or `{:error, :forbidden}`. Writes the audit event
  `failure_counter.reset` and logs `user_updated`.
  """
  def reset_directory(%Scope{} = scope, provider_key, subject)
      when is_binary(provider_key) and is_binary(subject) do
    if Scope.admin?(scope) do
      case delete_directory_row(
             scope,
             provider_key,
             directory_hash_input(provider_key, subject),
             nil
           ) do
        0 -> {:error, :not_found}
        _deleted -> :ok
      end
    else
      {:error, :forbidden}
    end
  end

  @doc """
  Deletes the directory counters of every directory identity of `user`.
  Requires the role `admin` and returns `{:ok, deleted}` or
  `{:error, :forbidden}`. The admin action "reset failure counters" of task
  0015 calls it; the hash input comes from each identity's issuer, tenant
  and decrypted subject.
  """
  def reset_directory_for_user(%Scope{} = scope, user) do
    if Scope.admin?(scope) do
      identities =
        Repo.all(from i in ExternalIdentity, where: i.user_id == ^user.id)

      deleted =
        for %ExternalIdentity{issuer: "ldap:" <> key} = identity <- identities,
            key == identity.provider_key,
            reduce: 0 do
          acc ->
            hash_input =
              ExternalIdentity.hash_input(identity.issuer, identity.tenant_id, identity.subject)

            acc + delete_directory_row(scope, identity.provider_key, hash_input, user)
        end

      {:ok, deleted}
    else
      {:error, :forbidden}
    end
  end

  # The audit event names the user when the caller knows the account.
  defp delete_directory_row(scope, provider_key, hash_input, user) do
    case Repo.delete_all(directory_query(provider_key, hash_input)) do
      {0, _} ->
        0

      {count, _} ->
        {:ok, _event} =
          Audit.record(scope, "failure_counter.reset", user, %{provider_key: provider_key})

        SecurityLog.event(:user_updated, %{
          user_id: user && user.id,
          provider: provider_key,
          reason: "directory_counter_reset"
        })

        count
    end
  end

  defp directory_query(provider_key, hash_input) do
    from c in FailureCounter,
      where:
        c.authenticator == :ldap and c.provider_key == ^provider_key and
          c.subject_hash == ^hash_input
  end

  defp directory_hash_input(provider_key, subject),
    do: ExternalIdentity.hash_input("ldap:" <> provider_key, nil, subject)
end
