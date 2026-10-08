defmodule Espalier.Crypto.InvalidKeyError do
  @moduledoc """
  Raised when an encryption key or the HMAC secret is missing or malformed.

  The message names the environment variable and never contains its value.
  """
  defexception [:message]
end

defmodule Espalier.Crypto.DecryptError do
  @moduledoc """
  Raised when a ciphertext fails GCM authentication, because it was changed or
  was written under another key.
  """
  defexception message: "decryption failed"
end
