# Prints a new CLOAK_KEY_V1 and a new CLOAK_HMAC_SECRET for .env: 32 bytes
# each from a CSPRNG, Base64-encoded (docs/security/key-management.md).
for name <- ["CLOAK_KEY_V1", "CLOAK_HMAC_SECRET"] do
  IO.puts("#{name}=#{32 |> :crypto.strong_rand_bytes() |> Base.encode64()}")
end
