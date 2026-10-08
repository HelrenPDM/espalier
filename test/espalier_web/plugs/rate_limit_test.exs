defmodule EspalierWeb.Plugs.RateLimitTest do
  # Restores real limits on the node-wide ETS table.
  use EspalierWeb.ConnCase, async: false

  alias Espalier.RateLimit
  alias EspalierWeb.Plugs.TrustedProxy

  defp sign_in(ip, email) do
    api_conn()
    |> with_csrf_token()
    |> Map.put(:remote_ip, ip)
    |> post("/api/auth/password", %{email: email, password: "wrong but long password"})
  end

  test "the 31st password sign-in from one IP within a minute answers 429 with retry-after" do
    put_rate_limit(:auth_ip, {:timer.minutes(1), 30})
    ip = unique_ip()
    ref = attach_security_events()

    for _ <- 1..30 do
      assert json_response(sign_in(ip, unique_user_email()), 401)
    end

    conn = sign_in(ip, unique_user_email())
    assert json_response(conn, 429) == %{"error" => "rate_limited"}
    assert [seconds] = get_resp_header(conn, "retry-after")
    assert String.to_integer(seconds) in 1..60
    assert_received {^ref, %{name: :excess_rate_limit_exceeded, reason: "auth_ip"}}
  end

  test "the eleventh attempt for one address from eleven IPs answers 429" do
    put_rate_limit(:password_account, {:timer.minutes(15), 10})
    user = user_fixture()

    for _ <- 1..10 do
      assert json_response(sign_in(unique_ip(), user.email), 401)
    end

    assert json_response(sign_in(unique_ip(), String.upcase(user.email)), 429)
  end

  test "known and unknown addresses share the buckets and a 429 is the same for both" do
    put_rate_limit(:password_account, {:timer.minutes(15), 1})
    known = user_fixture().email
    unknown = unique_user_email()

    for email <- [known, unknown], do: sign_in(unique_ip(), email)
    assert sign_in(unique_ip(), known).resp_body == sign_in(unique_ip(), unknown).resp_body
  end

  test "IPv6 addresses share a bucket per /64 prefix" do
    put_rate_limit(:demo_ip, {:timer.minutes(1), 1})
    assert {:allow, 1} = RateLimit.check_ip(:demo_ip, {0x2001, 0xDB8, 1, 2, 0, 0, 0, 1})
    assert {:deny, _ms} = RateLimit.check_ip(:demo_ip, {0x2001, 0xDB8, 1, 2, 0xFFFF, 0, 0, 9})
  end

  test "account_hash/1 is eight hex characters of the keyed hash of the normalized identifier" do
    hash = RateLimit.account_hash("Someone@Example.org ")
    assert hash =~ ~r/\A[0-9a-f]{8}\z/
    assert hash == RateLimit.account_hash("someone@example.org")
    refute hash == RateLimit.account_hash("other@example.org")
  end

  describe "TrustedProxy" do
    setup do
      put_setting(:trusted_proxies, [Espalier.RuntimeConfig.proxy!("10.0.0.0/8")])
      :ok
    end

    defp forwarded(peer, value) do
      Phoenix.ConnTest.build_conn()
      |> Map.put(:remote_ip, peer)
      |> put_req_header("x-forwarded-for", value)
      |> TrustedProxy.call([])
    end

    test "takes the rightmost entry from a trusted peer" do
      assert forwarded({10, 1, 2, 3}, "198.51.100.7, 203.0.113.9").remote_ip == {203, 0, 113, 9}

      assert forwarded({10, 1, 2, 3}, "2001:db8::1").remote_ip ==
               {0x2001, 0xDB8, 0, 0, 0, 0, 0, 1}
    end

    test "ignores the header from another peer and when it is malformed" do
      assert forwarded({192, 0, 2, 1}, "203.0.113.9").remote_ip == {192, 0, 2, 1}
      assert forwarded({10, 1, 2, 3}, "203.0.113.9, not-an-ip").remote_ip == {10, 1, 2, 3}
    end

    test "parses addresses and CIDR ranges and rejects invalid entries" do
      assert Espalier.RuntimeConfig.proxy!("192.0.2.1") == {{192, 0, 2, 1}, 32}

      assert Espalier.RuntimeConfig.proxy!("2001:db8::/32") ==
               {{0x2001, 0xDB8, 0, 0, 0, 0, 0, 0}, 32}

      for invalid <- ["10.0.0.0/33", "example.org", "10.0.0/8"] do
        assert_raise ArgumentError, ~r/TRUSTED_PROXIES/, fn ->
          Espalier.RuntimeConfig.proxy!(invalid)
        end
      end
    end
  end
end
