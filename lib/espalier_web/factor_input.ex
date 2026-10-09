defmodule EspalierWeb.FactorInput do
  @moduledoc """
  The second factor of a request body (`POST /api/auth/second-factor`,
  `POST /api/me/reauth`) and the function that verifies it for
  `Espalier.Accounts.Factors.verify/5`.

  A passkey assertion consumes the challenge of the ceremony in the session
  before the counter check, so the challenge is gone after every outcome.
  """

  alias Espalier.Accounts.{Passkeys, RecoveryCodes, Totp, User}
  alias EspalierWeb.WebauthnCeremony

  @doc """
  Returns `{:ok, factor, input}` when `params` carries exactly one of the
  keys of `factors` (`:totp`, `:passkey`, `:recovery_code`), and
  `{:error, :bad_request}` otherwise.
  """
  def parse(params, factors) when is_map(params) do
    present =
      for factor <- factors, Map.has_key?(params, Atom.to_string(factor)) do
        {factor, Map.fetch!(params, Atom.to_string(factor))}
      end

    case present do
      [{:passkey, %{} = response}] ->
        {:ok, :passkey, response}

      [{factor, code}] when factor in [:totp, :recovery_code] and is_binary(code) ->
        {:ok, factor, code}

      _ ->
        {:error, :bad_request}
    end
  end

  @doc """
  Returns `{conn, fun}`: `fun` verifies `input` for `user`. For a passkey,
  the challenge of `purpose` is consumed now and the ceremony id removed
  from the session of the returned conn.
  """
  def verifier(conn, %User{} = user, :passkey, response, purpose) do
    {conn, challenge} = WebauthnCeremony.finish(conn, purpose, user.id)

    {conn,
     fn ->
       with {:ok, row} <- challenge, do: Passkeys.authenticate(row, response, user)
     end}
  end

  def verifier(conn, %User{} = user, :totp, code, _purpose) do
    {conn,
     fn ->
       case Totp.get_enabled(user) do
         nil -> {:error, :no_factor}
         factor -> Totp.verify(factor, code)
       end
     end}
  end

  def verifier(conn, %User{} = user, :recovery_code, code, _purpose) do
    {conn, fn -> RecoveryCodes.use(user, code) end}
  end
end
