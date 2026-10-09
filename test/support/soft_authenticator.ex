defmodule Espalier.SoftAuthenticator do
  @moduledoc """
  A software WebAuthn authenticator for tests: an ES256 key pair from
  `:crypto.generate_key(:ecdh, :secp256r1)`, attestation format `"none"`.

  `attest/3` and `assert/3` return the JSON maps a browser posts
  (`credential.toJSON()`), with base64url fields. Options of both:

    * `:uv` (default `true`), `:be`, `:bs` - the flags UV, BE and BS;
    * `:sign_count` - the counter (default: the authenticator's);
    * `:alg` - the COSE algorithm in the key (default -7), for -65535;
    * `:origin`, `:type`, `:cross_origin`, `:top_origin` - members of
      `clientDataJSON` (`:cross_origin` and `:top_origin` only when given);
    * `:user_handle` - bytes or `nil` for the assertion (default: the
      authenticator's);
    * `:bad_signature` - signs other bytes.
  """

  defstruct [:private_key, :x, :y, :credential_id, :user_handle, sign_count: 0]

  @default_origin "http://localhost:5173"

  @doc "A new authenticator with a random 32-byte credential id."
  def new(opts \\ []) do
    {public, private} = :crypto.generate_key(:ecdh, :secp256r1)
    <<4, x::binary-size(32), y::binary-size(32)>> = public

    %__MODULE__{
      private_key: private,
      x: x,
      y: y,
      credential_id: Keyword.get(opts, :credential_id, :crypto.strong_rand_bytes(32)),
      user_handle: Keyword.get(opts, :user_handle),
      sign_count: Keyword.get(opts, :sign_count, 0)
    }
  end

  @doc "Takes the user handle from creation options."
  def put_user_handle(%__MODULE__{} = authenticator, %{"user" => %{"id" => id}}) do
    %{authenticator | user_handle: Base.url_decode64!(id, padding: false)}
  end

  @doc "The COSE key of the public key, with algorithm `alg`."
  def cose_key(%__MODULE__{x: x, y: y}, alg \\ -7) do
    %{1 => 2, 3 => alg, -1 => 1, -2 => x, -3 => y}
  end

  @doc "A RegistrationResponseJSON for `creation_options`."
  def attest(%__MODULE__{} = authenticator, creation_options, opts \\ []) do
    client_data_json = client_data("webauthn.create", creation_options["challenge"], opts)
    id = authenticator.credential_id

    cose =
      authenticator
      |> cose_key(Keyword.get(opts, :alg, -7))
      |> Map.new(fn
        {key, value} when is_binary(value) -> {key, %CBOR.Tag{tag: :bytes, value: value}}
        pair -> pair
      end)

    auth_data =
      authenticator_data(authenticator, creation_options["rp"]["id"], opts, 0x40) <>
        <<0::128, byte_size(id)::16>> <> id <> CBOR.encode(cose)

    attestation_object =
      CBOR.encode(%{
        "fmt" => "none",
        "attStmt" => %{},
        "authData" => %CBOR.Tag{tag: :bytes, value: auth_data}
      })

    %{
      "id" => encode(id),
      "rawId" => encode(id),
      "type" => "public-key",
      "authenticatorAttachment" => "platform",
      "clientExtensionResults" => %{},
      "response" => %{
        "clientDataJSON" => encode(client_data_json),
        "attestationObject" => encode(attestation_object),
        "transports" => ["internal"]
      }
    }
  end

  @doc "An AuthenticationResponseJSON for `request_options`."
  def assert(%__MODULE__{} = authenticator, request_options, opts \\ []) do
    client_data_json = client_data("webauthn.get", request_options["challenge"], opts)
    auth_data = authenticator_data(authenticator, request_options["rpId"], opts, 0)
    message = auth_data <> :crypto.hash(:sha256, client_data_json)
    message = if opts[:bad_signature], do: message <> "x", else: message
    signature = :crypto.sign(:ecdsa, :sha256, message, [authenticator.private_key, :secp256r1])

    user_handle =
      case Keyword.fetch(opts, :user_handle) do
        {:ok, handle} -> handle
        :error -> authenticator.user_handle
      end

    response = %{
      "clientDataJSON" => encode(client_data_json),
      "authenticatorData" => encode(auth_data),
      "signature" => encode(signature)
    }

    response =
      if user_handle, do: Map.put(response, "userHandle", encode(user_handle)), else: response

    %{
      "id" => encode(authenticator.credential_id),
      "rawId" => encode(authenticator.credential_id),
      "type" => "public-key",
      "authenticatorAttachment" => "platform",
      "clientExtensionResults" => %{},
      "response" => response
    }
  end

  defp authenticator_data(authenticator, rp_id, opts, extra_flags) do
    flags =
      0x01
      |> flag(Keyword.get(opts, :uv, true), 0x04)
      |> flag(Keyword.get(opts, :be, false), 0x08)
      |> flag(Keyword.get(opts, :bs, false), 0x10)
      |> Bitwise.bor(extra_flags)

    count = Keyword.get(opts, :sign_count, authenticator.sign_count)
    :crypto.hash(:sha256, rp_id) <> <<flags, count::32>>
  end

  defp flag(flags, true, bit), do: Bitwise.bor(flags, bit)
  defp flag(flags, false, _bit), do: flags

  defp client_data(type, challenge, opts) do
    data = %{
      "type" => Keyword.get(opts, :type, type),
      "challenge" => challenge,
      "origin" => Keyword.get(opts, :origin, @default_origin)
    }

    data =
      case Keyword.fetch(opts, :cross_origin) do
        {:ok, value} -> Map.put(data, "crossOrigin", value)
        :error -> data
      end

    data =
      case Keyword.fetch(opts, :top_origin) do
        {:ok, value} -> Map.put(data, "topOrigin", value)
        :error -> data
      end

    Jason.encode!(data)
  end

  defp encode(bytes), do: Base.url_encode64(bytes, padding: false)
end
