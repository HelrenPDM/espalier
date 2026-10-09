defmodule Espalier.Accounts.TotpTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures

  alias Espalier.Accounts.{Scope, Totp, TotpFactor}

  # A fixed time in the middle of a 30-second step.
  @t 1_791_000_015
  @step div(@t, 30)

  setup do
    user = user_fixture()
    {factor, secret} = totp_fixture(user)
    %{user: user, factor: factor, secret: secret}
  end

  defp code_at(secret, t), do: NimbleTOTP.verification_code(secret, time: t)

  test "verification_code/2 takes time: as Unix seconds", %{secret: secret} do
    assert code_at(secret, @t) == code_at(secret, DateTime.from_unix!(@t))
    assert code_at(secret, @step * 30) == code_at(secret, @step * 30 + 29)
    refute code_at(secret, @step * 30) == code_at(secret, @step * 30 + 30)
  end

  test "the current step is accepted and stored", %{factor: factor, secret: secret} do
    assert Totp.verify(factor, code_at(secret, @t), @t) == :ok
    assert Repo.reload!(factor).last_used_step == @step
  end

  test "the previous step is accepted", %{factor: factor, secret: secret} do
    assert Totp.verify(factor, code_at(secret, @t - 30), @t) == :ok
    assert Repo.reload!(factor).last_used_step == @step - 1
  end

  test "the step before the previous one and the next step are rejected",
       %{factor: factor, secret: secret} do
    assert Totp.verify(factor, code_at(secret, @t - 60), @t) == {:error, :invalid_code}
    assert Totp.verify(factor, code_at(secret, @t + 30), @t) == {:error, :invalid_code}
    assert Totp.verify(factor, "12345", @t) == {:error, :invalid_code}
    assert Totp.verify(factor, "abcdef", @t) == {:error, :invalid_code}
    assert Repo.reload!(factor).last_used_step == nil
  end

  test "a code is rejected on its second use", %{factor: factor, secret: secret} do
    code = code_at(secret, @t)
    assert Totp.verify(factor, code, @t) == :ok
    assert Totp.verify(Repo.reload!(factor), code, @t) == {:error, :invalid_code}
    # A stale struct cannot reuse it either: the conditional update decides.
    assert Totp.verify(factor, code, @t) == {:error, :invalid_code}
    # The code of the previous step is older than the stored step.
    assert Totp.verify(Repo.reload!(factor), code_at(secret, @t - 30), @t) ==
             {:error, :invalid_code}

    # The next step works.
    assert Totp.verify(Repo.reload!(factor), code_at(secret, @t + 30), @t + 30) == :ok
  end

  test "of two concurrent verifications with one code exactly one succeeds",
       %{factor: factor, secret: secret} do
    code = code_at(secret, @t)

    results =
      [fn -> Totp.verify(factor, code, @t) end, fn -> Totp.verify(factor, code, @t) end]
      |> Enum.map(&Task.async/1)
      |> Enum.map(&Task.await/1)

    assert Enum.sort(results) == [:ok, {:error, :invalid_code}]
  end

  test "the column holds ciphertext that does not contain the secret",
       %{factor: factor, secret: secret} do
    assert byte_size(secret) == 20

    %{rows: [[stored]]} =
      Repo.query!("SELECT secret FROM totp_factors WHERE id = $1", [Ecto.UUID.dump!(factor.id)])

    assert stored != secret
    refute :binary.match(stored, secret) != :nomatch
  end

  test "codes are the HMAC-SHA-1 values of the RFC 6238 test vectors" do
    # RFC 6238 Appendix B, SHA1 rows: the secret is the ASCII string
    # "12345678901234567890"; six digits are the last six of the eight shown.
    secret = "12345678901234567890"

    for {t, eight_digits} <- [
          {59, "94287082"},
          {1_111_111_109, "07081804"},
          {1_111_111_111, "14050471"},
          {1_234_567_890, "89005924"},
          {2_000_000_000, "69279037"},
          {20_000_000_000, "65353130"}
        ] do
      expected = String.slice(eight_digits, 2, 6)
      assert code_at(secret, t) == expected

      user = user_fixture()
      {factor, _secret} = totp_fixture(user)
      factor = factor |> Ecto.Changeset.change() |> Totp.put_secret(secret) |> Repo.update!()
      assert Totp.verify(factor, expected, t) == :ok
    end
  end

  test "the secret round-trips through the closure type", %{factor: factor, secret: secret} do
    loaded = Repo.get!(TotpFactor, factor.id)
    assert is_function(loaded.secret, 0)
    assert Totp.secret!(loaded) == secret
    refute inspect(loaded) =~ Base.encode32(secret)
  end

  describe "enrollment" do
    test "start_enrollment/1 returns a QR code, the base32 secret and the URI" do
      user = user_fixture()
      scope = %Scope{user: user, session: %Espalier.Accounts.UserToken{strength: :mfa}}

      assert {:ok, payload} = Totp.start_enrollment(scope)
      assert "data:image/svg+xml;base64," <> svg = payload.qr_svg_data_url
      assert Base.decode64!(svg) =~ "<svg"
      assert payload.otpauth_uri =~ "otpauth://totp/Espalier:"
      assert payload.otpauth_uri =~ "issuer=Espalier"
      assert {:ok, secret} = Base.decode32(payload.secret_base32, padding: false)
      assert byte_size(secret) == 20
      refute Totp.enabled?(user)

      assert Totp.confirm(scope, "abcdef") == {:error, :invalid_code}
      refute Totp.enabled?(user)
    end

    test "confirm/3 enables the factor and uses the code" do
      user = user_fixture()
      scope = %Scope{user: user, session: %Espalier.Accounts.UserToken{strength: :mfa}}
      {:ok, payload} = Totp.start_enrollment(scope)
      secret = Base.decode32!(payload.secret_base32, padding: false)

      assert {:ok, factor} = Totp.confirm(scope, code_at(secret, @t), @t)
      assert factor.enabled_at
      assert Totp.enabled?(user)

      assert Totp.verify(Totp.get_enabled(user), code_at(secret, @t), @t) ==
               {:error, :invalid_code}

      assert Totp.start_enrollment(scope) == {:error, :totp_already_enabled}
    end
  end
end
