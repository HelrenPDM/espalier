defmodule Espalier.Crypto.CipherAllowlistTest do
  # Reads the state of the running vault.
  use ExUnit.Case, async: false

  alias Espalier.Crypto.StrictAESGCM

  @tag_format ~r/\AAES\.GCM\.V[1-9][0-9]*\z/

  test "init/1 configures only the strict GCM wrapper, highest version first" do
    configured = Application.fetch_env!(:espalier, Espalier.Vault)[:keys]
    assert {:ok, config} = Espalier.Vault.init(keys: configured)
    assert_strict_ciphers(config[:ciphers], [1])

    k1 = Base.encode64(:crypto.strong_rand_bytes(32))
    k2 = Base.encode64(:crypto.strong_rand_bytes(32))

    for keys <- [[{2, k2}, {1, k1}], [{1, k1}, {2, k2}]] do
      assert {:ok, config} = Espalier.Vault.init(keys: keys)
      assert_strict_ciphers(config[:ciphers], [2, 1])
      assert [{:current, _}, {:retired, _}] = config[:ciphers]
      refute Keyword.has_key?(config, :keys)
    end
  end

  test "the running vault holds only the strict GCM wrapper" do
    assert_strict_ciphers(:sys.get_state(Espalier.Vault)[:ciphers], [1])
  end

  test "the status of the vault process shows no key" do
    [{_label, {_module, opts}}] = :sys.get_state(Espalier.Vault)[:ciphers]
    status = inspect(:sys.get_status(Espalier.Vault), limit: :infinity)
    refute status =~ inspect(opts[:key])
    assert status =~ ":redacted"
  end

  test "only the allowed modules name Cloak, and no unused Cloak module appears" do
    sources =
      for path <- Path.wildcard("{lib,config}/**/*.{ex,exs}"), into: %{} do
        {path, File.read!(path)}
      end

    assert files_containing(sources, "Cloak.Ciphers.") == [
             "lib/espalier/crypto/strict_aes_gcm.ex"
           ]

    for path <- files_containing(sources, "use Cloak.") do
      assert path == "lib/espalier/vault.ex" or
               String.starts_with?(path, ["lib/espalier/encrypted/", "lib/espalier/hashed/"]),
             "#{path} uses a Cloak module"
    end

    for forbidden <- [
          "AES.CTR",
          "Cloak.Ciphers.Deprecated",
          "Cloak.Ecto.PBKDF2",
          "Cloak.Ecto.SHA256"
        ] do
      assert files_containing(sources, forbidden) == [], "#{forbidden} appears"
    end
  end

  test "no Repo call sets its own log: option" do
    for path <- Path.wildcard("{lib,config}/**/*.{ex,exs}"),
        {line, number} <- path |> File.read!() |> String.split("\n") |> Enum.with_index(1) do
      refute line =~ ~r/Repo\.\w+\(.*\blog:/, "#{path}:#{number} sets log:"
    end
  end

  defp assert_strict_ciphers(ciphers, versions) do
    assert Enum.map(ciphers, fn {_label, {_module, opts}} -> opts[:tag] end) ==
             Enum.map(versions, &"AES.GCM.V#{&1}")

    for {label, {module, opts}} <- ciphers do
      assert label in [:current, :retired]
      assert module == StrictAESGCM
      assert opts[:iv_length] == 12
      assert byte_size(opts[:key]) == 32
      assert opts[:tag] =~ @tag_format
    end
  end

  defp files_containing(sources, text) do
    for {path, source} <- sources, String.contains?(source, text), do: path
  end
end
