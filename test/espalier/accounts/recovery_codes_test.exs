defmodule Espalier.Accounts.RecoveryCodesTest do
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures

  alias Espalier.Accounts.{RecoveryCode, RecoveryCodes, Scope}

  setup do
    user = user_fixture()
    %{user: user, codes: RecoveryCodes.generate(Scope.for_user(user))}
  end

  test "ten codes in groups of four", %{codes: codes} do
    assert length(codes) == 10
    assert length(Enum.uniq(codes)) == 10
    for code <- codes, do: assert(code =~ ~r/\A([A-Z2-7]{4}-){6}[A-Z2-7]{2}\z/)
  end

  test "each code carries 128 bits", %{codes: codes} do
    for code <- codes do
      plain = String.replace(code, "-", "")
      assert String.length(plain) == 26
      assert {:ok, bytes} = Base.decode32(plain, padding: false)
      assert byte_size(bytes) == 16
    end
  end

  test "the table holds only HMACs", %{user: user, codes: codes} do
    rows = Repo.all(from r in RecoveryCode, where: r.user_id == ^user.id)
    assert length(rows) == 10

    plains = Enum.map(codes, &String.replace(&1, "-", ""))

    for row <- rows do
      assert byte_size(row.code_hmac) == 32
      refute row.code_hmac in plains
      refute Enum.any?(plains, &(:binary.match(row.code_hmac, &1) != :nomatch))
    end

    macs = MapSet.new(rows, & &1.code_hmac)

    for plain <- plains,
        do: assert(MapSet.member?(macs, :crypto.mac(:hmac, :sha256, RecoveryCodes.key(), plain)))
  end

  test "the key is derived from CLOAK_HMAC_SECRET with its own label" do
    secret = Base.decode64!(Application.fetch_env!(:espalier, Espalier.Hashed.HMAC)[:secret])

    assert RecoveryCodes.key() ==
             :crypto.mac(:hmac, :sha256, secret, "espalier/recovery-codes/v1")

    refute RecoveryCodes.key() == secret
  end

  test "each code works once", %{user: user, codes: [code | _]} do
    assert RecoveryCodes.use(user, code) == {:ok, 9}
    assert RecoveryCodes.use(user, code) == {:error, :invalid_code}
    assert RecoveryCodes.remaining(user) == 9
  end

  test "lowercase input with spaces and without hyphens is accepted",
       %{user: user, codes: [code | _]} do
    input =
      code |> String.replace("-", "") |> String.downcase() |> String.graphemes() |> Enum.join(" ")

    assert RecoveryCodes.use(user, " " <> input <> " ") == {:ok, 9}
  end

  test "malformed input and codes of another user fail", %{user: user, codes: [code | _]} do
    assert RecoveryCodes.use(user, "ABCD") == {:error, :invalid_code}
    assert RecoveryCodes.use(user, nil) == {:error, :invalid_code}
    other = user_fixture()
    RecoveryCodes.generate(Scope.for_user(other))
    assert RecoveryCodes.use(other, code) == {:error, :invalid_code}
  end

  test "concurrent regenerations leave one set of ten", %{user: user} do
    [user, user]
    |> Enum.map(fn user -> Task.async(fn -> RecoveryCodes.generate(Scope.for_user(user)) end) end)
    |> Enum.map(&Task.await/1)

    assert RecoveryCodes.remaining(user) == 10
  end

  test "regeneration makes every earlier code fail", %{user: user, codes: codes} do
    new_codes = RecoveryCodes.generate(Scope.for_user(user))
    for code <- codes, do: assert(RecoveryCodes.use(user, code) == {:error, :invalid_code})
    assert RecoveryCodes.use(user, hd(new_codes)) == {:ok, 9}
    assert RecoveryCodes.generated_at(user)
  end
end
