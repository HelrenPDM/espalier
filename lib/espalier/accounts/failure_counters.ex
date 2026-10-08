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
  """

  import Ecto.Query

  alias Espalier.Accounts.FailureCounter
  alias Espalier.Repo
  alias Espalier.SecurityLog

  @lock_from 5
  @disable_at 50
  @base_seconds 30
  @max_seconds 3600

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
end
