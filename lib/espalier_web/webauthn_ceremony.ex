defmodule EspalierWeb.WebauthnCeremony do
  @moduledoc """
  The id of a running WebAuthn ceremony in the session cookie
  `__Host-espalier` under `"webauthn_ceremony"` (README section 6.5).

  An options endpoint deletes the challenge row that the session names,
  stores a new row and puts its id. A verifying endpoint takes the id,
  consumes the row and removes the key, whatever the outcome. The challenge
  bytes and the `Wax.Challenge` struct never enter the session.
  """

  import Plug.Conn

  alias Espalier.Accounts.Challenges

  @key "webauthn_ceremony"

  @doc """
  Replaces the ceremony of the session by a new challenge row for `purpose`
  and `user_id_or_nil`. Returns `{conn, row}`.
  """
  def start(conn, purpose, user_id_or_nil, %Wax.Challenge{} = challenge) do
    :ok = Challenges.delete(get_session(conn, @key))
    row = Challenges.issue(purpose, user_id_or_nil, challenge)
    {put_session(conn, @key, row.id), row}
  end

  @doc """
  Removes the ceremony id from the session and consumes its row. Returns
  `{conn, {:ok, row}}` or `{conn, {:error, :challenge_invalid}}`.
  """
  def finish(conn, purpose, user_id_or_nil) do
    id = get_session(conn, @key)
    {delete_session(conn, @key), Challenges.consume(id, purpose, user_id_or_nil)}
  end
end
