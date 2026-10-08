defmodule Espalier.Telemetry.QueryLog do
  @moduledoc """
  Logs Repo queries without their parameters and results.

  ecto_sql logs the cast parameters of a query, which hold the plaintext of
  encrypted and hashed fields before dump, and puts `params`, `cast_params`
  and `result` into the telemetry metadata. In production the Repo therefore
  runs with `log: false`, and this handler logs one line per query at
  `:debug` with the source, the first word of the statement and the total
  time.

  Every handler for Repo events calls `scrub/1` first. Repo calls take no
  `log:` option, because a call-level log level overrides `log: false` in
  ecto_sql.
  """

  require Logger

  @handler_id "espalier-query-log"
  @event [:espalier, :repo, :query]
  @unsafe_keys [:params, :cast_params, :result]

  @doc "Attaches the handler `#{@handler_id}` to `#{inspect(@event)}`."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach do
    :telemetry.attach(@handler_id, @event, &__MODULE__.handle_event/4, nil)
  end

  @doc "Drops the query parameters and the result from the metadata."
  @spec scrub(map()) :: map()
  def scrub(metadata), do: Map.drop(metadata, @unsafe_keys)

  @doc "Builds the log line from the measurements and the scrubbed metadata."
  @spec format(map(), map()) :: String.t()
  def format(measurements, metadata) do
    metadata = scrub(metadata)
    command = metadata |> Map.get(:query, "") |> to_string() |> first_word()

    total_ms =
      measurements
      |> Map.get(:total_time, 0)
      |> System.convert_time_unit(:native, :microsecond)
      |> Kernel./(1000)

    "QUERY #{command} source=#{metadata[:source] || "-"} " <>
      "total=#{:erlang.float_to_binary(total_ms, decimals: 1)}ms"
  end

  @doc false
  def handle_event(_event, measurements, metadata, _config) do
    Logger.debug(fn -> format(measurements, metadata) end)
  end

  defp first_word(query) do
    case String.split(query, ~r/\s/, parts: 2, trim: true) do
      [word | _] -> word
      [] -> "-"
    end
  end
end
