defmodule Espalier.Accounts.Challenges do
  @moduledoc """
  Server-side storage of WebAuthn challenges (README section 6.6).

  A challenge is bound to its purpose and to its user, or to no user for a
  discoverable sign-in. It lives 300 seconds and works once: `consume/3`
  deletes the row before it checks anything, so the row is gone after every
  outcome. The id of the row is the ceremony id, which the session cookie
  carries under `"webauthn_ceremony"`; the bytes leave the server only in
  the options JSON.
  """

  import Ecto.Query

  alias Espalier.Accounts.AuthChallenge
  alias Espalier.Repo

  @ttl_seconds 300

  @doc "Lifetime of a challenge in seconds."
  def ttl_seconds, do: @ttl_seconds

  @doc """
  Stores the bytes of `challenge` for `purpose` and `user_id_or_nil` and
  returns the row, which expires 300 seconds from now.
  """
  def issue(purpose, user_id_or_nil, %Wax.Challenge{bytes: bytes}) do
    now = DateTime.utc_now(:second)

    %AuthChallenge{}
    |> AuthChallenge.changeset(%{
      purpose: purpose,
      user_id: user_id_or_nil,
      challenge: bytes,
      expires_at: DateTime.add(now, @ttl_seconds, :second)
    })
    |> Repo.insert!()
  end

  @doc """
  Deletes the row of `id` and returns `{:ok, row}` when its purpose and user
  match and it has not expired, or `{:error, :challenge_invalid}`.
  """
  def consume(id, purpose, user_id_or_nil) do
    now = DateTime.utc_now()

    with {:ok, uuid} <- cast_id(id),
         {1, [row]} <-
           Repo.delete_all(from(c in AuthChallenge, where: c.id == ^uuid, select: c)),
         true <- row.purpose == purpose,
         true <- row.user_id == user_id_or_nil,
         true <- DateTime.after?(row.expires_at, now) do
      {:ok, row}
    else
      _ -> {:error, :challenge_invalid}
    end
  end

  @doc "Deletes the row of `id`, when there is one."
  def delete(id) do
    case cast_id(id) do
      {:ok, uuid} -> Repo.delete_all(from c in AuthChallenge, where: c.id == ^uuid)
      :error -> :ok
    end

    :ok
  end

  @doc """
  Returns the Unix time that `wax_` must take as the issue time of a
  challenge rebuilt from `row`, so that its expiry check matches the row.
  """
  def issued_at(%AuthChallenge{expires_at: expires_at}) do
    DateTime.to_unix(expires_at) - @ttl_seconds
  end

  defp cast_id(id) when is_binary(id), do: Ecto.UUID.cast(id)
  defp cast_id(_id), do: :error
end
