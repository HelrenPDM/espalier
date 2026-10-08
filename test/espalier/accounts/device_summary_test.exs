defmodule Espalier.Accounts.DeviceSummaryTest do
  use ExUnit.Case, async: true

  alias Espalier.Accounts.DeviceSummary

  @cases [
    {"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) " <>
       "Chrome/129.0.0.0 Safari/537.36 Edg/129.0.0.0", "Edge on Windows"},
    {"Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) " <>
       "Chrome/129.0.0.0 Mobile Safari/537.36", "Chrome on Android"},
    {"Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " <>
       "(KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", "Safari on iOS"},
    {"Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0",
     "Firefox on Linux"},
    {"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) " <>
       "Chrome/129.0.0.0 Safari/537.36", "Chrome on macOS"},
    {nil, nil},
    {"curl/8.9.1", nil},
    {"SomeBot/1.0 (Windows)", "Windows"}
  ]

  for {user_agent, summary} <- @cases do
    test "#{inspect(user_agent)} becomes #{inspect(summary)}" do
      assert DeviceSummary.from_user_agent(unquote(user_agent)) == unquote(summary)
    end
  end
end
