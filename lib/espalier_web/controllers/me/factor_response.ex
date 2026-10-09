defmodule EspalierWeb.Me.FactorResponse do
  @moduledoc """
  The answer of a factor change: `other_sessions`, the number of the user's
  other live sessions, which the SPA offers to end (ASVS 7.4.3), and after
  a completed enrollment or recovery the new `recovery_codes` (shown once)
  and the `session` payload with the new CSRF token.
  """

  import Phoenix.Controller, only: [json: 2]

  alias Espalier.Accounts
  alias EspalierWeb.SessionController

  @doc """
  Renders `body` with `other_sessions`. `previous_strength` is the strength
  before the change; `codes` the codes of `Factors.complete_enrollment/3`.
  """
  def render(conn, body, previous_strength \\ :mfa, codes \\ nil) do
    %{user: user, session: session} = conn.assigns.current_scope

    body =
      body
      |> Map.put(:other_sessions, Accounts.count_other_sessions(user, session.id))
      |> maybe_put(:recovery_codes, codes)
      |> maybe_put(
        :session,
        if(previous_strength != session.strength, do: SessionController.session_payload(conn))
      )

    json(conn, body)
  end

  defp maybe_put(body, _key, nil), do: body
  defp maybe_put(body, key, value), do: Map.put(body, key, value)
end
