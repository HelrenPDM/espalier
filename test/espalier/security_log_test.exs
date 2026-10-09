defmodule Espalier.SecurityLogTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Espalier.Test.SecurityEvents

  alias Espalier.SecurityLog

  test "unknown event names and attribute keys raise" do
    # The name passes through a variable, because the type checker already
    # rejects the literal call SecurityLog.event(:made_up, %{}).
    name = Enum.at([:made_up], 0)
    assert_raise ArgumentError, fn -> SecurityLog.event(name, %{}) end

    assert_raise ArgumentError, fn ->
      SecurityLog.event(:authn_login_fail, %{password: "secret"})
    end
  end

  test "emits telemetry and one log line with the attributes as metadata" do
    ref = attach_security_events()

    log =
      capture_log([level: :warning, metadata: [:event, :user_id, :ip]], fn ->
        SecurityLog.event(:authz_fail, %{user_id: "u1", ip: {192, 0, 2, 1}, reason: :forbidden})
      end)

    assert_received {^ref,
                     %{name: :authz_fail, user_id: "u1", ip: "192.0.2.1", reason: "forbidden"}}

    assert log =~ "authz_fail"
    assert log =~ "event=authz_fail"
    assert log =~ "[warning]"
  end

  test "the option level overrides the level" do
    log =
      capture_log([level: :error], fn ->
        SecurityLog.event(:session_created, %{}, level: :error)
      end)

    assert log =~ "[error] session_created"
  end

  test "the vocabulary holds only OWASP names and the operational event" do
    assert :breach_check_unavailable in SecurityLog.events()

    for name <- SecurityLog.events() -- [:breach_check_unavailable] do
      assert Atom.to_string(name) =~
               ~r/\A(authn|authz|input|privilege|excess|malicious|session|user)_[a-z_]+\z/
    end
  end
end
