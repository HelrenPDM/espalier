defmodule Espalier.Accounts.Passkeys.ClientData do
  @moduledoc """
  Checks `clientDataJSON` before any `wax_` call (README section 6.6,
  `wax_` issue #60): `wax_` 0.7.0 drops `crossOrigin` and `topOrigin` and
  raises on some malformed input.

  The JSON must be a map with the expected `type`, a `challenge` that decodes
  as base64url, an `origin` from the list, `crossOrigin` absent or `false`,
  and no `topOrigin` member. A rejection logs `input_validation_fail` with
  the reason.
  """

  alias Espalier.SecurityLog

  @types %{create: "webauthn.create", get: "webauthn.get"}

  @doc "Returns `:ok` or `{:error, reason}`."
  @spec check(binary(), :create | :get, [String.t()]) :: :ok | {:error, atom()}
  def check(client_data_json, type, origins) when type in [:create, :get] do
    case validate(client_data_json, Map.fetch!(@types, type), origins) do
      :ok ->
        :ok

      {:error, reason} = error ->
        SecurityLog.event(:input_validation_fail, %{reason: reason})
        error
    end
  end

  defp validate(json, type, origins) do
    with {:ok, data} <- decode(json),
         :ok <- expect(data["type"] == type, :wrong_type),
         :ok <- expect(challenge?(data["challenge"]), :invalid_challenge),
         :ok <- expect(is_binary(data["origin"]) and data["origin"] in origins, :origin_mismatch),
         :ok <- expect(data["crossOrigin"] in [nil, false], :cross_origin) do
      expect(not Map.has_key?(data, "topOrigin"), :top_origin)
    end
  end

  defp decode(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = data} -> {:ok, data}
      _ -> {:error, :malformed_client_data}
    end
  end

  defp decode(_json), do: {:error, :malformed_client_data}

  defp challenge?(value) when is_binary(value) do
    match?({:ok, _}, Base.url_decode64(value, padding: false))
  end

  defp challenge?(_value), do: false

  defp expect(true, _reason), do: :ok
  defp expect(false, reason), do: {:error, reason}
end
