defmodule Espalier.Accounts.DeviceSummary do
  @moduledoc """
  Turns a `User-Agent` value into the browser and system family of a session
  row, such as `"Firefox on Linux"` (README section 6.5). The full value is
  never stored or logged.

  The tokens are checked in a fixed order, because an Edge value also
  contains `Chrome/`, a Chrome value also contains `Safari/`, an iPhone value
  also contains `Mac OS X`, and an Android value also contains `Linux`.
  """

  @browsers [
    {"Edg/", "Edge"},
    {"Firefox/", "Firefox"},
    {"Chrome/", "Chrome"},
    {"Safari/", "Safari"}
  ]
  @systems [
    {"iPhone", "iOS"},
    {"iPad", "iOS"},
    {"Android", "Android"},
    {"Windows", "Windows"},
    {"Mac OS X", "macOS"},
    {"Linux", "Linux"}
  ]

  @doc "Returns `\"<browser> on <system>\"`, the one family that matched, or `nil`."
  @spec from_user_agent(String.t() | nil) :: String.t() | nil
  def from_user_agent(nil), do: nil

  def from_user_agent(user_agent) when is_binary(user_agent) do
    case {match(user_agent, @browsers), match(user_agent, @systems)} do
      {nil, nil} -> nil
      {browser, nil} -> browser
      {nil, system} -> system
      {browser, system} -> "#{browser} on #{system}"
    end
  end

  defp match(user_agent, tokens) do
    Enum.find_value(tokens, fn {token, name} ->
      if String.contains?(user_agent, token), do: name
    end)
  end
end
