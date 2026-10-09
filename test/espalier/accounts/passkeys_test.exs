defmodule Espalier.Accounts.PasskeysTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures
  import ExUnit.CaptureLog

  alias Espalier.Accounts
  alias Espalier.Accounts.{AuthChallenge, Challenges, CoseKey, Factors, Passkeys, Scope}
  alias Espalier.Accounts.Passkeys.{Checks, ClientData, Config, Options, WaxCall}
  alias Espalier.SoftAuthenticator

  setup do
    user = Accounts.ensure_webauthn_user_handle(user_fixture())
    %{user: user, authenticator: SoftAuthenticator.new(user_handle: user.webauthn_user_handle)}
  end

  defp registration(user, credentials \\ []) do
    challenge = Passkeys.new_registration_challenge()
    row = Challenges.issue(:registration, user.id, challenge)
    {row, Options.creation(user, challenge, credentials)}
  end

  defp authentication(purpose, user_id, allow \\ []) do
    challenge = Passkeys.new_authentication_challenge()
    row = Challenges.issue(purpose, user_id, challenge)
    {row, Options.request(challenge, allow)}
  end

  defp register(user, authenticator, opts \\ []) do
    {row, options} = registration(user)
    response = SoftAuthenticator.attest(authenticator, options, opts)
    Passkeys.register(Scope.for_user(user), row, response)
  end

  defp sign_in(authenticator, opts, expected_user \\ nil) do
    {row, options} = authentication(:sign_in, expected_user && expected_user.id)
    response = SoftAuthenticator.assert(authenticator, options, opts)
    Passkeys.authenticate(row, response, expected_user)
  end

  defp decode(value), do: Base.url_decode64!(value, padding: false)

  describe "challenge storage" do
    test "a challenge works once", %{user: user} do
      row = Challenges.issue(:reauth, user.id, Passkeys.new_authentication_challenge())
      assert {:ok, %AuthChallenge{id: id}} = Challenges.consume(row.id, :reauth, user.id)
      assert id == row.id
      assert Challenges.consume(row.id, :reauth, user.id) == {:error, :challenge_invalid}
    end

    test "an expired challenge fails and is deleted", %{user: user} do
      row = Challenges.issue(:reauth, user.id, Passkeys.new_authentication_challenge())

      Repo.update_all(from(c in AuthChallenge, where: c.id == ^row.id),
        set: [expires_at: DateTime.add(DateTime.utc_now(:second), -1)]
      )

      assert Challenges.consume(row.id, :reauth, user.id) == {:error, :challenge_invalid}
      assert Repo.get(AuthChallenge, row.id) == nil
    end

    test "a challenge of another purpose or another user fails", %{user: user} do
      other = user_fixture()

      for {purpose, user_id} <- [{:second_factor, user.id}, {:reauth, other.id}, {:reauth, nil}] do
        row = Challenges.issue(:reauth, user.id, Passkeys.new_authentication_challenge())
        assert Challenges.consume(row.id, purpose, user_id) == {:error, :challenge_invalid}
        assert Repo.get(AuthChallenge, row.id) == nil
      end
    end

    test "a failed verification deletes the challenge", %{
      user: user,
      authenticator: authenticator
    } do
      {:ok, _credential} = register(user, authenticator)
      {row, options} = authentication(:sign_in, nil)
      response = SoftAuthenticator.assert(authenticator, options, bad_signature: true)

      assert {:ok, consumed} = Challenges.consume(row.id, :sign_in, nil)
      assert Passkeys.authenticate(consumed, response, nil) == {:error, :invalid_signature}
      assert Repo.get(AuthChallenge, row.id) == nil
    end
  end

  describe "COSE algorithm allowlist" do
    test "rejects COSE algorithm -65535 after register", %{
      user: user,
      authenticator: authenticator
    } do
      # wax_ 0.7.0 accepts the key (issue #59); the application check rejects it.
      {row, options} = registration(user)
      response = SoftAuthenticator.attest(authenticator, options, alg: -65_535)

      challenge = %{
        Wax.new_registration_challenge(Passkeys.registration_options() ++ [bytes: row.challenge])
        | issued_at: Challenges.issued_at(row)
      }

      assert {:ok, {auth_data, _}} =
               Wax.register(
                 decode(response["response"]["attestationObject"]),
                 decode(response["response"]["clientDataJSON"]),
                 challenge
               )

      assert auth_data.attested_credential_data.credential_public_key[3] == -65_535

      assert Passkeys.register(Scope.for_user(user), row, response) ==
               {:error, :algorithm_not_allowed}

      assert Passkeys.list_credentials(user) == []
    end

    test "accepts COSE algorithms -7, -8 and -257", %{user: user, authenticator: authenticator} do
      for alg <- [-7, -8, -257], do: assert(Checks.algorithm_allowed?(%{3 => alg}) == :ok)
      assert Checks.algorithm_allowed?(%{3 => -65_535}) == {:error, :algorithm_not_allowed}
      assert {:ok, credential} = register(user, authenticator)
      assert credential.cose_key[3] == -7
    end
  end

  describe "clientDataJSON" do
    test "rejects clientDataJSON with crossOrigin true", %{
      user: user,
      authenticator: authenticator
    } do
      ref = attach_security_events()
      assert register(user, authenticator, cross_origin: true) == {:error, :cross_origin}
      assert_received {^ref, %{name: :input_validation_fail, reason: "cross_origin"}}
    end

    test "rejects clientDataJSON with a topOrigin member", %{
      user: user,
      authenticator: authenticator
    } do
      assert register(user, authenticator, top_origin: "https://other.example") ==
               {:error, :top_origin}

      assert register(user, authenticator,
               cross_origin: false,
               top_origin: "http://localhost:5173"
             ) ==
               {:error, :top_origin}
    end

    test "accepts clientDataJSON with crossOrigin false", %{
      user: user,
      authenticator: authenticator
    } do
      assert {:ok, _credential} = register(user, authenticator, cross_origin: false)
      assert {:ok, _result} = sign_in(authenticator, cross_origin: false)
    end

    test "rejects clientDataJSON of the wrong type", %{user: user, authenticator: authenticator} do
      origins = Config.get().origins
      json = ~s({"type":"webauthn.get","challenge":"AA","origin":"http://localhost:5173"})
      assert ClientData.check(json, :create, origins) == {:error, :wrong_type}
      assert ClientData.check(json, :get, origins) == :ok
      assert ClientData.check("[]", :get, origins) == {:error, :malformed_client_data}
      assert register(user, authenticator, type: "webauthn.get") == {:error, :wrong_type}
    end
  end

  describe "backup flags" do
    test "rejects backup state without backup eligibility at registration",
         %{user: user, authenticator: authenticator} do
      assert register(user, authenticator, be: false, bs: true) == {:error, :backup_state_invalid}
    end

    test "rejects backup state without backup eligibility at authentication",
         %{user: user, authenticator: authenticator} do
      {:ok, _credential} = register(user, authenticator)
      assert sign_in(authenticator, be: false, bs: true) == {:error, :backup_state_invalid}
    end

    test "accepts a synced passkey", %{user: user, authenticator: authenticator} do
      assert {:ok, credential} = register(user, authenticator, be: true, bs: true)
      assert credential.backup_eligible and credential.backed_up
      assert {:ok, %{user: signed_in}} = sign_in(authenticator, be: true, bs: true)
      assert signed_in.id == user.id
    end
  end

  describe "user handle" do
    test "rejects an assertion whose userHandle belongs to another account",
         %{user: user, authenticator: authenticator} do
      other = Accounts.ensure_webauthn_user_handle(user_fixture())
      {:ok, _credential} = register(user, authenticator)

      assert sign_in(authenticator, user_handle: other.webauthn_user_handle) ==
               {:error, :user_handle_mismatch}

      assert sign_in(authenticator, [user_handle: other.webauthn_user_handle], user) ==
               {:error, :user_handle_mismatch}
    end

    test "rejects a discoverable assertion without userHandle",
         %{user: user, authenticator: authenticator} do
      {:ok, _credential} = register(user, authenticator)
      assert sign_in(authenticator, user_handle: nil) == {:error, :user_handle_missing}
      # A second factor names the user, so the handle may be missing.
      assert {:ok, _result} = sign_in(authenticator, [user_handle: nil], user)
    end
  end

  describe "sign count" do
    test "logs a risk signal when the sign count does not increase", %{user: user} do
      {authenticator, credential} = passkey_fixture(user, sign_count: 5)
      ref = attach_security_events()

      log =
        capture_log([level: :warning], fn ->
          assert {:ok, result} = sign_in(authenticator, sign_count: 3)
          assert result.risk_signal == "sign_count"
          Factors.record_success(user, :passkey, result, %{user_id: user.id, factor: :passkey})
        end)

      assert_received {^ref,
                       %{name: :authn_login_success, risk_signal: "sign_count", factor: "passkey"} =
                         event}

      assert event.credential_ref ==
               :sha256
               |> :crypto.hash(credential.credential_id)
               |> Base.encode16(case: :lower)
               |> binary_part(0, 8)

      assert log =~ "[warning] authn_login_success"
      # The stored count never decreases.
      assert Repo.reload!(credential).sign_count == 5
      assert {:ok, %{risk_signal: nil}} = sign_in(authenticator, sign_count: 6)
      assert Repo.reload!(credential).sign_count == 6
    end

    test "accepts counters that stay at zero without a signal", %{user: user} do
      {authenticator, credential} = passkey_fixture(user)
      assert {:ok, %{risk_signal: nil}} = sign_in(authenticator, sign_count: 0)
      assert {:ok, %{risk_signal: nil}} = sign_in(authenticator, sign_count: 0)
      assert Repo.reload!(credential).sign_count == 0
      assert Repo.reload!(credential).last_used_at
    end
  end

  test "rescues exceptions raised inside Wax", %{user: user} do
    ref = attach_security_events()
    {row, _options} = registration(user)

    challenge = %{
      Wax.new_registration_challenge(Passkeys.registration_options() ++ [bytes: row.challenge])
      | issued_at: Challenges.issued_at(row)
    }

    log =
      capture_log([level: :warning], fn ->
        assert WaxCall.run(fn ->
                 Wax.register(<<>>, ~s({"type":"other","challenge":"AA"}), challenge)
               end) == {:error, :wax_exception}
      end)

    assert_received {^ref, %{name: :input_validation_fail, exception: "CaseClauseError"} = event}
    refute Map.has_key?(event, :message)
    assert log =~ "[warning] input_validation_fail"
  end

  describe "user verification" do
    test "an assertion without UV returns :user_not_verified",
         %{user: user, authenticator: authenticator} do
      {:ok, credential} = register(user, authenticator)
      {row, options} = authentication(:sign_in, nil)
      response = SoftAuthenticator.assert(authenticator, options, uv: false)

      challenge = %{
        Wax.new_authentication_challenge(
          Passkeys.authentication_options() ++ [bytes: row.challenge]
        )
        | issued_at: Challenges.issued_at(row)
      }

      assert WaxCall.run(fn ->
               Wax.authenticate(
                 credential.credential_id,
                 decode(response["response"]["authenticatorData"]),
                 decode(response["response"]["signature"]),
                 decode(response["response"]["clientDataJSON"]),
                 challenge,
                 [{credential.credential_id, credential.cose_key}]
               )
             end) == {:error, %Wax.InvalidClientDataError{reason: :user_not_verified}}

      assert Passkeys.authenticate(row, response, nil) == {:error, :user_not_verified}
    end

    test "a registration without UV returns :user_not_verified",
         %{user: user, authenticator: authenticator} do
      {row, options} = registration(user)
      response = SoftAuthenticator.attest(authenticator, options, uv: false)

      challenge = %{
        Wax.new_registration_challenge(Passkeys.registration_options() ++ [bytes: row.challenge])
        | issued_at: Challenges.issued_at(row)
      }

      assert WaxCall.run(fn ->
               Wax.register(
                 decode(response["response"]["attestationObject"]),
                 decode(response["response"]["clientDataJSON"]),
                 challenge
               )
             end) == {:error, %Wax.InvalidClientDataError{reason: :user_not_verified}}
    end

    test "challenges carry user_verification \"required\" and timeout 300" do
      for challenge <- [
            Passkeys.new_registration_challenge(),
            Passkeys.new_authentication_challenge()
          ] do
        assert challenge.user_verification == "required"
        assert challenge.timeout == 300
        assert challenge.allow_credentials == []
        assert byte_size(challenge.bytes) == 32
      end

      assert Passkeys.new_registration_challenge().attestation == "none"
    end
  end

  test "verifies the recorded Chromium CDP registration and assertion" do
    fixture =
      "test/fixtures/webauthn/chromium_cdp_es256.json"
      |> File.read!()
      |> Jason.decode!()

    config = %{rp_id: fixture["rp_id"], rp_name: "Espalier", origins: [fixture["origin"]]}
    handle = decode(fixture["user_handle"])
    user = user_fixture()

    Repo.update_all(from(u in Accounts.User, where: u.id == ^user.id),
      set: [webauthn_user_handle: handle]
    )

    user = Repo.reload!(user)
    expires_at = DateTime.add(DateTime.utc_now(:second), 300)

    registration_row = %AuthChallenge{
      purpose: :registration,
      user_id: user.id,
      challenge: decode(fixture["registration"]["challenge"]),
      expires_at: expires_at
    }

    assert {:ok, credential} =
             Passkeys.register(
               Scope.for_user(user),
               registration_row,
               fixture["registration"]["response"],
               config
             )

    assert credential.cose_key[3] == -7

    authentication_row = %AuthChallenge{
      purpose: :sign_in,
      challenge: decode(fixture["authentication"]["challenge"]),
      expires_at: expires_at
    }

    assert {:ok, %{user: signed_in, risk_signal: nil}} =
             Passkeys.authenticate(
               authentication_row,
               fixture["authentication"]["response"],
               nil,
               config
             )

    assert signed_in.id == user.id
  end

  test "creation options carry the RP, the user handle, algorithms -8, -7 and -257, a required resident key, required UV, attestation none, excludeCredentials and timeout 300000",
       %{user: user} do
    {_authenticator, credential} = passkey_fixture(user)
    challenge = Passkeys.new_registration_challenge()
    options = Options.creation(user, challenge, [credential])

    assert options["rp"] == %{"id" => "localhost", "name" => "Espalier"}
    assert decode(options["user"]["id"]) == user.webauthn_user_handle
    assert byte_size(user.webauthn_user_handle) == 64
    assert options["user"]["name"] == user.email
    assert decode(options["challenge"]) == challenge.bytes
    assert Enum.map(options["pubKeyCredParams"], & &1["alg"]) == [-8, -7, -257]
    assert Enum.all?(options["pubKeyCredParams"], &(&1["type"] == "public-key"))

    assert options["authenticatorSelection"] == %{
             "residentKey" => "required",
             "userVerification" => "required"
           }

    assert options["attestation"] == "none"
    assert options["timeout"] == 300_000

    assert options["excludeCredentials"] == [
             %{
               "type" => "public-key",
               "id" => Base.url_encode64(credential.credential_id, padding: false),
               "transports" => ["internal"]
             }
           ]
  end

  test "sign-in request options carry no allowCredentials", %{user: user} do
    {_authenticator, credential} = passkey_fixture(user)
    challenge = Passkeys.new_authentication_challenge()
    options = Options.request(challenge, [])

    assert options == %{
             "challenge" => Base.url_encode64(challenge.bytes, padding: false),
             "timeout" => 300_000,
             "rpId" => "localhost",
             "userVerification" => "required"
           }

    assert [%{"id" => id}] = Options.request(challenge, [credential])["allowCredentials"]
    assert decode(id) == credential.credential_id
  end

  test "a credential id held by another account is rejected",
       %{user: user, authenticator: authenticator} do
    assert {:ok, _credential} = register(user, authenticator)
    other = Accounts.ensure_webauthn_user_handle(user_fixture())
    assert register(other, authenticator) == {:error, :credential_exists}
    assert Passkeys.list_credentials(other) == []
  end

  test "the COSE key type refuses a term that contains a function" do
    key = %{1 => 2, 3 => -7, -1 => 1, -2 => <<1>>, -3 => <<2>>}
    assert {:ok, binary} = CoseKey.dump(key)
    assert CoseKey.load(binary) == {:ok, key}
    assert CoseKey.load(:erlang.term_to_binary(%{1 => fn -> :ok end})) == :error
    assert CoseKey.load(:erlang.term_to_binary(%{"kty" => 2})) == :error
    assert CoseKey.load(:erlang.term_to_binary([1, 2])) == :error
    assert CoseKey.load("not a term") == :error
    assert CoseKey.cast(%{"kty" => 2}) == :error
  end
end
