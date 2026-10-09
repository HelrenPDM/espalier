defmodule Espalier.Accounts.FactorMailsTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures

  alias Espalier.Accounts.{Factors, FailureCounters, Recovery}

  # Runs the mail jobs and returns the mails they sent.
  defp deliver do
    Oban.drain_queue(queue: :mail)
    collect([])
  end

  defp collect(mails) do
    receive do
      {:email, email} -> collect([email | mails])
    after
      0 -> Enum.reverse(mails)
    end
  end

  test "each factor event sends one mail without a code, a secret or a credential id" do
    user = user_fixture()
    {_authenticator, credential} = passkey_fixture(user)
    {_factor, secret} = totp_fixture(user)
    codes = recovery_codes_fixture(user)
    now = DateTime.utc_now()

    Factors.notify_change(user, :factor_added, :passkey)
    Factors.notify_change(user, :factor_added, :totp)
    Factors.notify_change(user, :factor_removed, :passkey)
    Factors.notify_change(user, :factor_removed, :totp)
    Factors.notify_change(user, :recovery_codes_regenerated, :recovery_code)
    {_token, recovery_link} = email_token_fixture(user, :recovery_email)
    assert {:ok, 9} = Recovery.verify(user, recovery_link, hd(codes), %{})

    for _ <- 1..5, do: FailureCounters.record_failure(user, :totp, now)
    Repo.update_all(Espalier.Accounts.FailureCounter, set: [locked_until: nil])
    assert {:ok, nil} = Factors.verify(user, :totp, fn -> :ok end)

    for _ <- 1..49, do: FailureCounters.record_failure(user, :passkey, now)
    Repo.update_all(Espalier.Accounts.FailureCounter, set: [locked_until: nil])

    assert {:error, :invalid_signature} =
             Factors.verify(user, :passkey, fn -> {:error, :invalid_signature} end)

    mails = deliver()

    assert Enum.map(mails, & &1.subject) == [
             "A sign-in method was added",
             "A sign-in method was added",
             "A sign-in method was removed",
             "A sign-in method was removed",
             "New recovery codes",
             "A recovery code was used",
             "Sign-in after failed attempts",
             "A sign-in method was disabled"
           ]

    bodies = Enum.map(mails, & &1.text_body)
    assert Enum.at(bodies, 0) =~ "A passkey was added"
    assert Enum.at(bodies, 1) =~ "An authenticator app (TOTP) was added"
    assert Enum.at(bodies, 2) =~ "A passkey was removed"
    assert Enum.at(bodies, 3) =~ "An authenticator app (TOTP) was removed"
    assert Enum.at(bodies, 5) =~ "9 unused recovery codes are left"
    assert Enum.at(bodies, 6) =~ "an authenticator app (TOTP) after\n5 failed attempts"
    assert Enum.at(bodies, 7) =~ "A passkey of your Espalier account was disabled"

    secrets =
      codes ++
        Enum.map(codes, &String.replace(&1, "-", "")) ++
        [
          Base.encode32(secret, padding: false),
          Base.url_encode64(credential.credential_id, padding: false),
          Base.encode64(credential.credential_id),
          Base.encode16(credential.credential_id, case: :lower)
        ]

    for body <- bodies, value <- secrets, do: refute(body =~ value)
    for mail <- mails, do: assert(mail.to == [{"", user.email}])
  end

  test "a user without an address receives no mail" do
    user = user_fixture()

    Repo.update_all(from(u in Espalier.Accounts.User, where: u.id == ^user.id),
      set: [email: nil, email_hash: nil]
    )

    Factors.notify_change(user, :factor_added, :passkey)
    assert deliver() == []
  end
end
