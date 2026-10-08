defmodule Espalier.Crypto.StrictAESGCMTest do
  use ExUnit.Case, async: true

  import Espalier.CryptoCase, only: [flip_bit: 2]

  alias Cloak.Ciphers.AES.GCM
  alias Espalier.Crypto.StrictAESGCM

  @opts [tag: "AES.GCM.V1", key: :crypto.strong_rand_bytes(32), iv_length: 12]
  @plaintext "seventeen bytes!!"

  # Layout: <<1, 10, "AES.GCM.V1">> (12 bytes), IV (12), GCM tag (16), ciphertext.
  @iv_offset 12
  @gcm_tag_offset 24

  test "a value round-trips" do
    assert {:ok, ciphertext} = StrictAESGCM.encrypt(@plaintext, @opts)
    assert StrictAESGCM.can_decrypt?(ciphertext, @opts)
    assert StrictAESGCM.decrypt(ciphertext, @opts) == {:ok, @plaintext}
  end

  test "the ciphertext carries the tag, a 12-byte IV and a 16-byte GCM tag" do
    assert byte_size(@plaintext) == 17
    {:ok, ciphertext} = StrictAESGCM.encrypt(@plaintext, @opts)
    assert byte_size(ciphertext) == 57
    assert <<1, 10, "AES.GCM.V1", _rest::binary>> = ciphertext
  end

  test "a changed IV, GCM tag or ciphertext byte returns :error" do
    {:ok, ciphertext} = StrictAESGCM.encrypt(@plaintext, @opts)

    for index <- [@iv_offset, @gcm_tag_offset, byte_size(ciphertext) - 1] do
      assert StrictAESGCM.decrypt(flip_bit(ciphertext, index), @opts) == :error
    end
  end

  test "another key under the same tag returns :error" do
    {:ok, ciphertext} = StrictAESGCM.encrypt(@plaintext, @opts)
    other = Keyword.put(@opts, :key, :crypto.strong_rand_bytes(32))
    assert StrictAESGCM.decrypt(ciphertext, other) == :error
  end

  # Records the upstream behavior that the wrapper exists for. When this
  # assertion fails after an upgrade, upstream has changed the cipher, and
  # the wrapper needs a review.
  test "the wrapped cipher returns {:ok, :error} for the same tampered input" do
    {:ok, ciphertext} = StrictAESGCM.encrypt(@plaintext, @opts)
    tampered = flip_bit(ciphertext, byte_size(ciphertext) - 1)
    assert GCM.decrypt(tampered, @opts) == {:ok, :error}
  end
end
