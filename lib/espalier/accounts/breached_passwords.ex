defmodule Espalier.Accounts.BreachedPasswords do
  @moduledoc """
  Checks a password against the Pwned Passwords range API (k-anonymity with
  padding), used only with `PASSWORD_BREACH_CHECK=hibp` (decision D10).

  Only the first five hex characters of the SHA-1 of the NFC-normalized
  password leave the server. When the API is unreachable, the password change
  proceeds with the bundled lists, and the module logs the operational event
  `breach_check_unavailable`.
  """

  alias Espalier.SecurityLog

  @range_url "https://api.pwnedpasswords.com/range/"

  @doc """
  Returns `{:ok, :breached}`, `{:ok, :unlisted}` or `{:error, :unavailable}`
  for the normalized password.
  """
  @spec check(String.t()) :: {:ok, :breached | :unlisted} | {:error, :unavailable}
  def check(password) when is_binary(password) do
    <<prefix::binary-size(5), suffix::binary>> = :crypto.hash(:sha, password) |> Base.encode16()

    options =
      Keyword.merge(
        [
          headers: [{"add-padding", "true"}, {"user-agent", "Espalier"}],
          receive_timeout: 3_000,
          max_retries: 2,
          redirect: false
        ],
        Application.get_env(:espalier, __MODULE__, [])[:req_options] || []
      )

    case Req.get(@range_url <> prefix, options) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, if(listed?(body, suffix), do: :breached, else: :unlisted)}

      _other ->
        SecurityLog.event(:breach_check_unavailable, %{})
        {:error, :unavailable}
    end
  end

  # Lines are SUFFIX:COUNT; padding entries carry the count 0.
  defp listed?(body, suffix) do
    body
    |> String.split(["\r\n", "\n"], trim: true)
    |> Enum.any?(fn line ->
      case String.split(line, ":", parts: 2) do
        [^suffix, count] -> String.trim(count) not in ["", "0"]
        _ -> false
      end
    end)
  end
end
