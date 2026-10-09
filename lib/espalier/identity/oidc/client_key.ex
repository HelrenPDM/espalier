defmodule Espalier.Identity.Oidc.ClientKey do
  @moduledoc """
  Loads the certificate and the RSA key of a `private_key_jwt` client
  (task 0006, step 4). The key id follows `AUTH_<KEY>_CLIENT_KID_FORMAT`:
  the Base64url SHA-256 (`x5t_s256`) or SHA-1 (`x5t`) thumbprint of the
  certificate, or its SHA-1 in upper-case hex (`sha1_hex`).

  `oidcc_jwt_util:sign/4` copies only `kid` from the JWK fields into the
  header of the client assertion.
  """

  alias Espalier.Identity.ConfigError

  @doc """
  Returns `%{jwk: jwk, kid: kid}` for the PEM files, or raises
  `Espalier.Identity.ConfigError`. The message names the file role and
  never the key material.
  """
  @spec load!(String.t(), String.t(), :x5t_s256 | :x5t | :sha1_hex) :: %{
          jwk: JOSE.JWK.t(),
          kid: String.t()
        }
  def load!(cert_file, key_file, kid_format) do
    der = certificate!(cert_file)
    jwk = key!(key_file)

    if public_thumbprint(jwk) != certificate_thumbprint(der) do
      raise ConfigError, "the client key does not belong to the client certificate"
    end

    kid = kid(der, kid_format)
    %{jwk: JOSE.JWK.merge(jwk, %{"kid" => kid}), kid: kid}
  end

  @doc "Returns the key id of a DER certificate in `format`."
  @spec kid(binary(), :x5t_s256 | :x5t | :sha1_hex) :: String.t()
  def kid(der, :x5t_s256), do: Base.url_encode64(:crypto.hash(:sha256, der), padding: false)
  def kid(der, :x5t), do: Base.url_encode64(:crypto.hash(:sha, der), padding: false)
  def kid(der, :sha1_hex), do: Base.encode16(:crypto.hash(:sha, der))

  # The path comes from AUTH_<KEY>_CLIENT_CERT_FILE of the operator's
  # environment at boot; no request reaches it.
  # sobelow_skip ["Traversal.FileModule"]
  defp certificate!(cert_file) do
    with {:ok, pem} <- File.read(cert_file),
         [{:Certificate, der, :not_encrypted}] <- :public_key.pem_decode(pem) do
      der
    else
      _ -> raise ConfigError, "the client certificate file holds no single PEM certificate"
    end
  end

  # The path comes from AUTH_<KEY>_CLIENT_KEY_FILE of the operator's
  # environment at boot; no request reaches it.
  # sobelow_skip ["Traversal.FileModule"]
  defp key!(key_file) do
    jwk =
      with {:ok, pem} <- File.read(key_file),
           %JOSE.JWK{} = jwk <- safe_from_pem(pem) do
        jwk
      else
        _ -> raise ConfigError, "the client key file holds no readable PEM key"
      end

    case JOSE.JWK.to_map(jwk) do
      {_meta, %{"kty" => "RSA", "d" => _private}} -> jwk
      _ -> raise ConfigError, "the client key must be a private RSA key"
    end
  end

  defp safe_from_pem(pem) do
    JOSE.JWK.from_pem(pem)
  rescue
    _ -> nil
  end

  defp public_thumbprint(jwk), do: jwk |> JOSE.JWK.to_public() |> JOSE.JWK.thumbprint()

  defp certificate_thumbprint(der) do
    case safe_public_key(der) do
      nil -> raise ConfigError, "the client certificate cannot be read"
      public_key -> public_key |> JOSE.JWK.from_key() |> JOSE.JWK.thumbprint()
    end
  end

  defp safe_public_key(der) do
    der |> X509.Certificate.from_der!() |> X509.Certificate.public_key()
  rescue
    _ -> nil
  end
end
