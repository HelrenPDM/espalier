defmodule Espalier.Accounts.BreachedPasswordsTest do
  use Espalier.DataCase, async: true

  import ExUnit.CaptureLog

  alias Espalier.Accounts.BreachedPasswords

  @password "a breached password 2026"

  defp suffix do
    <<_prefix::binary-size(5), suffix::binary>> = :crypto.hash(:sha, @password) |> Base.encode16()
    suffix
  end

  test "a listed suffix with a count is breached" do
    Req.Test.stub(BreachedPasswords, &Req.Test.text(&1, "#{suffix()}:42\r\nABC:1\r\n"))
    assert BreachedPasswords.check(@password) == {:ok, :breached}
  end

  test "padding entries with count 0 and other suffixes are unlisted" do
    Req.Test.stub(BreachedPasswords, &Req.Test.text(&1, "#{suffix()}:0\r\nABC:3\r\n"))
    assert BreachedPasswords.check(@password) == {:ok, :unlisted}
  end

  test "a transport error is unavailable and logged" do
    Req.Test.stub(BreachedPasswords, &Req.Test.transport_error(&1, :econnrefused))

    log =
      capture_log(fn -> assert BreachedPasswords.check(@password) == {:error, :unavailable} end)

    assert log =~ "breach_check_unavailable"
    refute log =~ @password
  end
end
