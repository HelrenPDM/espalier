defmodule Espalier.Logger.JSONFormatterTest do
  use ExUnit.Case, async: true

  alias Espalier.Logger.JSONFormatter

  @config %{metadata: [:event, :user_id, :ip, :count]}

  defp format(msg, meta) do
    time = :os.system_time(:microsecond)
    event = %{level: :warning, msg: msg, meta: Map.merge(%{time: time}, meta)}
    event |> JSONFormatter.format(@config) |> IO.iodata_to_binary()
  end

  test "a message with a newline becomes one JSON line with a UTC time" do
    line = format({:string, "first line\nforged: line"}, %{event: :authz_fail, user_id: "u1"})

    assert [json, ""] = String.split(line, "\n")
    entry = JSON.decode!(json)
    assert entry["message"] == "first line\nforged: line"
    assert entry["level"] == "warning"
    assert entry["event"] == "authz_fail"
    assert entry["user_id"] == "u1"
    assert {:ok, _time, 0} = DateTime.from_iso8601(entry["time"])
    assert String.ends_with?(entry["time"], "Z")
  end

  test "only allowlisted metadata keys appear, other values are inspected" do
    line = format({"~s failed", ["sign-in"]}, %{password: "secret", ip: {127, 0, 0, 1}, count: 3})
    entry = JSON.decode!(line)
    assert entry["message"] == "sign-in failed"
    refute Map.has_key?(entry, "password")
    assert entry["ip"] == "{127, 0, 0, 1}"
    assert entry["count"] == 3
  end

  test "reports render as text" do
    entry = JSON.decode!(format({:report, %{a: 1}}, %{}))
    assert entry["message"] =~ "a: 1"
  end
end
