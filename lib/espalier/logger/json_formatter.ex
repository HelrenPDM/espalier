defmodule Espalier.Logger.JSONFormatter do
  @moduledoc """
  `:logger` formatter that writes one JSON object per line
  (`docs/security/logging.md`, ASVS 16.2.4 and 16.4.1).

  Each line holds `time` (ISO 8601 in UTC with microseconds), `level`,
  `message` and the metadata keys allowlisted in `config.metadata`. Values
  that are no string, number, boolean or atom are rendered with `inspect/1`.
  JSON encoding escapes control characters, so a newline in a message or a
  value cannot start a new log line. `config/prod.exs` sets it as the
  formatter of the default handler.
  """

  @default_metadata [
    :request_id,
    :event,
    :user_id,
    :session_id,
    :ip,
    :factor,
    :provider,
    :reason,
    :count,
    :account_hash,
    :risk_signal,
    :credential_ref,
    :change,
    :exception
  ]

  @doc "The `:logger` formatter callback."
  @spec format(:logger.log_event(), map()) :: iodata()
  def format(%{level: level, msg: msg, meta: meta}, config) do
    keys = Map.get(config, :metadata, @default_metadata)

    entry =
      for key <- keys, Map.has_key?(meta, key), into: %{} do
        {key, value(Map.fetch!(meta, key))}
      end

    entry =
      Map.merge(entry, %{
        time: time(meta),
        level: Atom.to_string(level),
        message: message(msg, meta)
      })

    [JSON.encode!(entry), ?\n]
  end

  @doc false
  def check_config(config) when is_map(config), do: :ok
  def check_config(_config), do: {:error, :invalid_formatter_config}

  defp time(%{time: time}) when is_integer(time) do
    time |> DateTime.from_unix!(:microsecond) |> DateTime.to_iso8601()
  end

  defp time(_meta), do: DateTime.utc_now() |> DateTime.to_iso8601()

  defp message({:string, chardata}, _meta), do: chardata_to_string(chardata)

  defp message({:report, report}, %{report_cb: report_cb}) when is_function(report_cb, 1) do
    {format, args} = report_cb.(report)
    message({format, args}, %{})
  end

  defp message({:report, report}, _meta), do: inspect(report)

  defp message({format, args}, _meta) do
    format |> :io_lib.format(args) |> chardata_to_string()
  rescue
    _error -> inspect({format, args})
  end

  defp chardata_to_string(chardata) do
    IO.chardata_to_string(chardata)
  rescue
    _error -> inspect(chardata)
  end

  defp value(value) when is_binary(value) do
    if String.valid?(value), do: value, else: inspect(value)
  end

  defp value(value) when is_number(value) or is_boolean(value) or is_nil(value), do: value
  defp value(value) when is_atom(value), do: Atom.to_string(value)
  defp value(value), do: inspect(value)
end
