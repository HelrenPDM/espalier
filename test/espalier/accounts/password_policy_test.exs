defmodule Espalier.Accounts.PasswordPolicyTest do
  # Sets PASSWORD_BREACH_CHECK=hibp for one test.
  use Espalier.DataCase, async: false

  import Espalier.AccountsFixtures

  alias Espalier.Accounts
  alias Espalier.Accounts.{BreachedPasswords, PasswordPolicy, User}

  @nfc "Crème brûlée au café du matin"

  defp policy(user \\ %User{}, password) do
    User.password_changeset(user, %{password: password}, hash_password: false)
  end

  defp codes(changeset),
    do: Enum.map(changeset.errors, fn {:password, {_, o}} -> o[:validation] end)

  describe "NFC normalization (decision D12)" do
    setup do
      nfd = String.normalize(@nfc, :nfd)
      assert @nfc != nfd
      assert length(String.codepoints(@nfc)) == 29
      assert length(String.codepoints(nfd)) == 33
      %{nfd: nfd}
    end

    test "prepare/1 returns the NFC form", %{nfd: nfd} do
      assert PasswordPolicy.prepare(nfd) == @nfc
    end

    test "the stored hash covers the NFC form and both spellings verify", %{nfd: nfd} do
      user = user_fixture(%{password: nil})

      assert {:ok, {user, nil}} =
               Accounts.update_user_password(user, %{password: nfd}, require_current: false)

      assert Argon2.verify_pass(@nfc, user.hashed_password)
      assert User.valid_password?(user, @nfc)
      assert User.valid_password?(user, nfd)
    end

    test "a password set in NFC signs in with its NFD spelling", %{nfd: nfd} do
      user = user_fixture(%{password: @nfc})
      assert {:ok, signed_in} = Accounts.authenticate_password(user.email, nfd, %{})
      assert signed_in.id == user.id
    end

    test "the breached-password range request carries the prefix of the NFC form", %{nfd: nfd} do
      Application.put_env(:espalier, :password_breach_check, :hibp)
      on_exit(fn -> Application.put_env(:espalier, :password_breach_check, :off) end)

      <<prefix::binary-size(5), _::binary>> = :crypto.hash(:sha, @nfc) |> Base.encode16()
      test_pid = self()

      Req.Test.stub(BreachedPasswords, fn conn ->
        send(test_pid, {:range, conn.request_path, Plug.Conn.get_req_header(conn, "add-padding")})
        Req.Test.text(conn, "0000000000000000000000000000000000A:0\r\n")
      end)

      assert policy(nfd).valid?
      assert_received {:range, path, ["true"]}
      assert path == "/range/" <> prefix
    end
  end

  describe "length in code points after NFC" do
    test "15 code points as received but 14 after NFC is too short" do
      value = "Lernpfad Café!"
      assert length(String.codepoints(value)) == 15
      assert codes(policy(value)) == [:too_short]
    end

    test "16 code points as received and 15 after NFC is accepted" do
      value = "Lernpfad Café!!"
      assert length(String.codepoints(value)) == 16
      assert policy(value).valid?
    end

    test "129 code points as received and 128 after NFC is accepted and signs in" do
      value = String.duplicate("x", 127) <> "é"
      assert length(String.codepoints(value)) == 129
      assert policy(value).valid?

      user = user_fixture(%{password: value})
      assert {:ok, _user} = Accounts.authenticate_password(user.email, value, %{})
    end

    test "129 code points after NFC is too long" do
      assert codes(policy(String.duplicate("x", 129))) == [:too_long]
    end
  end

  describe "lists" do
    test "a password of the common-password list is rejected, whatever its case" do
      [entry | _] = File.read!("priv/security/common-passwords.txt") |> String.split("\n")
      assert length(String.codepoints(entry)) >= 15
      assert codes(policy(String.upcase(entry))) == [:common]
    end

    test "the bundled list holds at least 3000 entries of 15 or more code points" do
      entries = File.read!("priv/security/common-passwords.txt") |> String.split("\n", trim: true)
      assert length(entries) >= 3000
      assert Enum.all?(entries, &(length(String.codepoints(&1)) >= 15))
      assert Enum.all?(entries, &(String.normalize(&1, :nfc) == &1 and String.downcase(&1) == &1))
    end

    test "letters that equal a context word are rejected" do
      assert codes(policy("Espalier 2026 !!! 2026")) == [:context]
      assert codes(policy("L-E-A-R-N-I-N-G 1234567")) == [:context]
    end

    test "PASSWORD_CONTEXT_WORDS adds words of the organization" do
      Application.put_env(:espalier, :password_context_words, ["Northwind"])
      PasswordPolicy.load_lists()

      on_exit(fn ->
        Application.put_env(:espalier, :password_context_words, [])
        PasswordPolicy.load_lists()
      end)

      assert codes(policy("northwind 2026 2026 !!")) == [:context]
    end

    test "the local part of the address and the display name are rejected" do
      user = user_fixture(%{email: "marlene@example.org", display_name: "Chloë"})
      assert codes(policy(user, "my name is marlene, ok?")) == [:context]

      nfd_name = "Chloë"
      assert nfd_name != "Chloë"
      assert codes(policy(user, "hello #{nfd_name} and friends")) == [:context]
    end

    test "no composition rule applies" do
      assert policy("only lower case letters here").valid?
    end
  end
end
