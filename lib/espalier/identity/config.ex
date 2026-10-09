defmodule Espalier.Identity.Config do
  @moduledoc """
  Parses the external identity providers from the environment
  (README section 6.11).

  `AUTH_PROVIDERS` lists the provider keys in the order of the sign-in page.
  For each key, `<KEY>` is its upper-case form, and `AUTH_<KEY>_TYPE` names
  the provider type: `entra`, `google` or `oidc` (task 0006), each of which
  yields an `%Espalier.Identity.OidcProvider{}`; task 0007 adds `ldap`. Every
  provider struct carries at least `key`, `type`, `kind`, `label` and
  `start_url`; `kind` is `redirect` (0006) or `credentials` (0007), and
  `start_url` is the path where the sign-in starts.

  Every value is trimmed, and one pair of surrounding double quotes is
  removed, because `docker run --env-file` keeps them. An invalid
  configuration raises `Espalier.Identity.ConfigError` with a message that
  names the variable and never contains a secret.

  `config/runtime.exs` stores the structs under `:identity_providers` and
  their `public_entry/1` under `:auth_providers`.

  ## OIDC variables (task 0006, step 3)

  | Variable | Types | Default and rule |
  |---|---|---|
  | `AUTH_<KEY>_LABEL`, `AUTH_<KEY>_CLIENT_ID` | all | required |
  | `AUTH_<KEY>_TENANT_ID` | `entra` | required, a GUID, stored lower-case |
  | `AUTH_<KEY>_ISSUER` | all | required for `oidc`; `entra`: `https://login.microsoftonline.com/<TENANT_ID>/v2.0`; `google`: `https://accounts.google.com` |
  | `AUTH_<KEY>_CLIENT_CERT_FILE`, `AUTH_<KEY>_CLIENT_KEY_FILE` | `entra`, `oidc` | both or neither; required for `entra` outside dev and test |
  | `AUTH_<KEY>_CLIENT_KID_FORMAT` | with a certificate | `x5t_s256`, `x5t` or `sha1_hex` |
  | `AUTH_<KEY>_CLIENT_SECRET` | all | required for `google` and for `oidc` without certificate; refused for `entra` outside dev and test |
  | `AUTH_<KEY>_CLIENT_AUTH` | `oidc` | `client_secret_basic`, `client_secret_post` or `private_key_jwt` |
  | `AUTH_<KEY>_HOSTED_DOMAIN` | `google` | required |
  | `AUTH_<KEY>_ROLE_CLAIM` | `oidc` | `roles` |
  | `AUTH_<KEY>_ROLE_MAP` | `entra`, `oidc` | `role=value;role=value` |
  | `AUTH_<KEY>_MFA`, `AUTH_<KEY>_MFA_AMR` | all | `local`; `mfa` |
  | `AUTH_<KEY>_PROVISION` | all | `true` for `entra` and `google`, `false` for `oidc` |
  | `AUTH_<KEY>_ALLOWED_HOSTS` | all | the issuer host; for `google` also Google's token and JWKS hosts |
  """

  alias Espalier.Identity.{ConfigError, OidcProvider}

  @key_format ~r/\A[a-z][a-z0-9_]{0,31}\z/
  @guid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/
  @host_name ~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\z/

  @oidc_types ["entra", "google", "oidc"]
  @roles %{
    "facilitator" => :facilitator,
    "author" => :author,
    "registrar" => :registrar,
    "analyst" => :analyst,
    "admin" => :admin
  }
  @kid_formats %{"x5t_s256" => :x5t_s256, "x5t" => :x5t, "sha1_hex" => :sha1_hex}
  @client_auths %{
    "client_secret_basic" => :client_secret_basic,
    "client_secret_post" => :client_secret_post,
    "private_key_jwt" => :private_key_jwt
  }

  # Hosts of token_endpoint and jwks_uri in Google's discovery document
  # (https://accounts.google.com/.well-known/openid-configuration, retrieved
  # 2026-10-09; docs/guides/identity-providers.md).
  @google_issuer "https://accounts.google.com"
  @google_hosts ["oauth2.googleapis.com", "www.googleapis.com"]

  # Variables that a type does not read; setting one stops the boot.
  @not_for %{
    "entra" => ["CLIENT_AUTH", "ROLE_CLAIM", "HOSTED_DOMAIN"],
    "google" => [
      "TENANT_ID",
      "CLIENT_CERT_FILE",
      "CLIENT_KEY_FILE",
      "CLIENT_KID_FORMAT",
      "CLIENT_AUTH",
      "ROLE_CLAIM",
      "ROLE_MAP"
    ],
    "oidc" => ["TENANT_ID", "HOSTED_DOMAIN"]
  }

  @doc """
  Returns the providers of `AUTH_PROVIDERS` in `env` (the map of
  `System.get_env/0`) in configured order, or raises `ConfigError`.
  """
  @spec parse!(%{optional(String.t()) => String.t()}, atom()) :: [map()]
  def parse!(env, config_env) when is_map(env) do
    case value(env, "AUTH_PROVIDERS") do
      nil ->
        []

      value ->
        keys = value |> String.split(",") |> Enum.map(&String.trim/1)
        Enum.each(keys, &check_key!/1)

        if Enum.uniq(keys) != keys do
          raise ConfigError, "AUTH_PROVIDERS lists a provider key twice"
        end

        Enum.map(keys, &provider!(&1, env, config_env))
    end
  end

  defp check_key!(key) do
    if not Regex.match?(@key_format, key) do
      raise ConfigError,
            "AUTH_PROVIDERS holds a key that does not match ^[a-z][a-z0-9_]{0,31}$"
    end
  end

  defp provider!(key, env, config_env) do
    variable = "AUTH_#{String.upcase(key)}_TYPE"

    case value(env, variable) do
      nil -> raise ConfigError, "#{variable} is required"
      type when type in @oidc_types -> oidc!(key, type, env, config_env)
      type -> raise ConfigError, "#{variable}=#{type} is not supported"
    end
  end

  ## OIDC providers

  defp oidc!(key, type, env, config_env) do
    ctx = %{key: key, type: type, env: env, prefix: "AUTH_#{String.upcase(key)}_"}
    production? = config_env not in [:dev, :test]

    for name <- Map.fetch!(@not_for, type), get(ctx, name) != nil do
      raise ConfigError, "#{var(ctx, name)} is not supported when #{var(ctx, "TYPE")}=#{type}"
    end

    tenant_id = if type == "entra", do: tenant_id!(ctx)
    issuer = issuer!(ctx, tenant_id, production?)
    {cert_file, key_file} = certificate!(ctx, production?)
    client_auth = client_auth!(ctx, cert_file)
    client_secret = client_secret!(ctx, client_auth, production?)

    %OidcProvider{
      key: key,
      type: type,
      kind: "redirect",
      start_url: "/auth/oidc/" <> key,
      label: required!(ctx, "LABEL"),
      issuer: issuer,
      tenant_id: tenant_id,
      client_id: required!(ctx, "CLIENT_ID"),
      client_secret: client_secret,
      cert_file: cert_file,
      key_file: key_file,
      kid_format: kid_format!(ctx, cert_file),
      client_auth: client_auth,
      hosted_domain: if(type == "google", do: String.downcase(required!(ctx, "HOSTED_DOMAIN"))),
      role_claim: role_claim(ctx),
      role_map: role_map!(ctx),
      mfa: enum!(ctx, "MFA", %{"local" => :local, "idp_trusted" => :idp_trusted}, :local),
      mfa_amr: mfa_amr!(ctx),
      provision: boolean!(ctx, "PROVISION", type in ["entra", "google"]),
      allowed_hosts: allowed_hosts!(ctx, issuer),
      redirect_uri: public_url(env) <> "/auth/oidc/" <> key <> "/callback",
      worker: Module.concat(Espalier.Identity.Oidc.Provider, Macro.camelize(key))
    }
  end

  defp tenant_id!(ctx) do
    tenant_id = ctx |> required!("TENANT_ID") |> String.downcase()

    if not Regex.match?(@guid, tenant_id) do
      raise ConfigError, "#{var(ctx, "TENANT_ID")} must be a GUID"
    end

    tenant_id
  end

  defp issuer!(ctx, tenant_id, production?) do
    issuer =
      case {ctx.type, get(ctx, "ISSUER")} do
        {"entra", nil} -> "https://login.microsoftonline.com/#{tenant_id}/v2.0"
        {"google", nil} -> @google_issuer
        {"oidc", nil} -> required!(ctx, "ISSUER")
        {_type, issuer} -> issuer
      end

    if ctx.type == "entra" and not String.ends_with?(issuer, "/#{tenant_id}/v2.0") do
      raise ConfigError,
            "#{var(ctx, "ISSUER")} must end in /<TENANT_ID>/v2.0 when #{var(ctx, "TYPE")}=entra"
    end

    check_issuer_url!(ctx, issuer, production?)
  end

  defp check_issuer_url!(ctx, issuer, production?) do
    case URI.new(issuer) do
      {:ok, %URI{scheme: scheme, host: host, query: nil, fragment: nil}}
      when scheme in ["http", "https"] and host not in [nil, ""] ->
        if production? and scheme != "https" do
          raise ConfigError, "#{var(ctx, "ISSUER")} must start with https://"
        end

        issuer

      _ ->
        raise ConfigError, "#{var(ctx, "ISSUER")} must be an http or https URL"
    end
  end

  defp certificate!(ctx, production?) do
    case {get(ctx, "CLIENT_CERT_FILE"), get(ctx, "CLIENT_KEY_FILE")} do
      {nil, nil} when ctx.type == "entra" and production? ->
        raise ConfigError,
              "#{var(ctx, "CLIENT_CERT_FILE")} and #{var(ctx, "CLIENT_KEY_FILE")} are required " <>
                "when #{var(ctx, "TYPE")}=entra"

      {nil, nil} ->
        {nil, nil}

      {cert_file, key_file} when is_binary(cert_file) and is_binary(key_file) ->
        {cert_file, key_file}

      _one ->
        raise ConfigError,
              "#{var(ctx, "CLIENT_CERT_FILE")} and #{var(ctx, "CLIENT_KEY_FILE")} must be set together"
    end
  end

  defp client_auth!(%{type: "google"}, _cert_file), do: :client_secret_basic
  defp client_auth!(%{type: "entra"}, nil), do: :client_secret_basic
  defp client_auth!(%{type: "entra"}, _cert_file), do: :private_key_jwt

  defp client_auth!(%{type: "oidc"} = ctx, cert_file) do
    default = if cert_file, do: "private_key_jwt", else: "client_secret_basic"
    method = enum!(ctx, "CLIENT_AUTH", @client_auths, Map.fetch!(@client_auths, default))

    cond do
      method == :private_key_jwt and is_nil(cert_file) ->
        raise ConfigError,
              "#{var(ctx, "CLIENT_AUTH")}=private_key_jwt requires #{var(ctx, "CLIENT_CERT_FILE")}"

      method != :private_key_jwt and is_binary(cert_file) ->
        raise ConfigError,
              "#{var(ctx, "CLIENT_CERT_FILE")} requires #{var(ctx, "CLIENT_AUTH")}=private_key_jwt"

      true ->
        method
    end
  end

  # README section 6.7 allows client secrets for Entra ID only in development.
  defp client_secret!(%{type: "entra"} = ctx, _client_auth, true = _production?) do
    if get(ctx, "CLIENT_SECRET") != nil do
      raise ConfigError,
            "#{var(ctx, "CLIENT_SECRET")} is refused when #{var(ctx, "TYPE")}=entra; " <>
              "use a certificate"
    end

    nil
  end

  defp client_secret!(_ctx, :private_key_jwt, _production?), do: nil

  defp client_secret!(ctx, _client_auth, _production?) do
    case get(ctx, "CLIENT_SECRET") do
      nil when ctx.type == "entra" ->
        raise ConfigError,
              "#{var(ctx, "CLIENT_CERT_FILE")} and #{var(ctx, "CLIENT_KEY_FILE")} are required " <>
                "when #{var(ctx, "TYPE")}=entra"

      nil ->
        raise ConfigError,
              "#{var(ctx, "CLIENT_SECRET")} is required when #{var(ctx, "TYPE")}=#{ctx.type}"

      secret ->
        secret
    end
  end

  defp kid_format!(ctx, nil) do
    if get(ctx, "CLIENT_KID_FORMAT") != nil do
      raise ConfigError,
            "#{var(ctx, "CLIENT_KID_FORMAT")} requires #{var(ctx, "CLIENT_CERT_FILE")}"
    end

    nil
  end

  # x5t_s256 stays the default until the Entra spike of task 0006 (step 18)
  # records the accepted format.
  defp kid_format!(ctx, _cert_file),
    do: enum!(ctx, "CLIENT_KID_FORMAT", @kid_formats, :x5t_s256)

  defp role_claim(%{type: "entra"}), do: "roles"
  defp role_claim(%{type: "google"}), do: nil
  defp role_claim(ctx), do: get(ctx, "ROLE_CLAIM") || "roles"

  defp role_map!(ctx) do
    case get(ctx, "ROLE_MAP") do
      nil ->
        []

      value ->
        value
        |> String.split(";")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.map(&role_entry!(ctx, &1))
    end
  end

  defp role_entry!(ctx, entry) do
    with [role, claim_value] <- String.split(entry, "=", parts: 2),
         role = String.trim(role),
         claim_value = String.trim(claim_value),
         true <- claim_value != "" do
      cond do
        role == "learner" ->
          raise ConfigError,
                "#{var(ctx, "ROLE_MAP")} maps learner, which every signed-in user holds"

        Map.has_key?(@roles, role) ->
          {Map.fetch!(@roles, role), claim_value}

        true ->
          raise ConfigError,
                "#{var(ctx, "ROLE_MAP")} names a role other than " <>
                  "facilitator, author, registrar, analyst and admin"
      end
    else
      _ -> raise ConfigError, "#{var(ctx, "ROLE_MAP")} must have the form role=value;role=value"
    end
  end

  defp mfa_amr!(ctx) do
    case get(ctx, "MFA_AMR") do
      nil ->
        ["mfa"]

      value ->
        case list(value) do
          [] -> raise ConfigError, "#{var(ctx, "MFA_AMR")} must list at least one value"
          values -> values
        end
    end
  end

  defp allowed_hosts!(ctx, issuer) do
    case get(ctx, "ALLOWED_HOSTS") do
      nil ->
        issuer_host = String.downcase(URI.parse(issuer).host)
        extra = if ctx.type == "google", do: @google_hosts, else: []
        Enum.uniq([issuer_host | extra])

      value ->
        value |> list() |> Enum.map(&allowed_host!(ctx, &1))
    end
  end

  defp allowed_host!(ctx, entry) do
    host = String.downcase(entry)

    if not Regex.match?(@host_name, host) do
      raise ConfigError,
            "#{var(ctx, "ALLOWED_HOSTS")} holds an entry that is no host name " <>
              "(no scheme, path or port)"
    end

    host
  end

  defp public_url(env) do
    (value(env, "PUBLIC_URL") || "http://localhost:5173") |> String.trim_trailing("/")
  end

  ## Value reader

  defp var(ctx, name), do: ctx.prefix <> name

  defp get(ctx, name), do: value(ctx.env, var(ctx, name))

  defp required!(ctx, name) do
    get(ctx, name) ||
      raise ConfigError, "#{var(ctx, name)} is required when #{var(ctx, "TYPE")}=#{ctx.type}"
  end

  defp enum!(ctx, name, allowed, default) do
    case get(ctx, name) do
      nil ->
        default

      value ->
        Map.get(allowed, value) ||
          raise ConfigError,
                "#{var(ctx, name)} must be one of #{allowed |> Map.keys() |> Enum.sort() |> Enum.join(", ")}"
    end
  end

  defp boolean!(ctx, name, default) do
    case get(ctx, name) do
      nil -> default
      "true" -> true
      "false" -> false
      _other -> raise ConfigError, "#{var(ctx, name)} must be true or false"
    end
  end

  defp list(value) do
    value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Reads one variable as `Espalier.RuntimeConfig` reads its values: trimmed,
  with one pair of surrounding double quotes removed, and `nil` when blank.
  Task 0007 reads its values through the same function.
  """
  @spec value(%{optional(String.t()) => String.t()}, String.t()) :: String.t() | nil
  def value(env, name) do
    value = env |> Map.get(name, "") |> String.trim()

    value =
      if String.length(value) >= 2 and String.starts_with?(value, "\"") and
           String.ends_with?(value, "\""),
         do: value |> String.slice(1..-2//1) |> String.trim(),
         else: value

    if value == "", do: nil, else: value
  end

  @doc """
  Returns the public fields of a provider, which the session payload and
  `GET /auth/providers` render. It holds no secret and no other
  configuration value.
  """
  @spec public_entry(map()) :: %{
          key: String.t(),
          type: String.t(),
          kind: String.t(),
          label: String.t(),
          start_url: String.t()
        }
  def public_entry(%{key: key, type: type, kind: kind, label: label, start_url: start_url}) do
    %{key: key, type: type, kind: kind, label: label, start_url: start_url}
  end
end
