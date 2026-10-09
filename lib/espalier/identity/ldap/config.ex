defmodule Espalier.Identity.Ldap.Config do
  @moduledoc """
  An LDAP or Active Directory provider, parsed from the environment by
  `parse!/3` (task 0007, steps 4 and 5).

  `Espalier.Identity.Config.parse!/2` calls `parse!/3` for every key of
  `AUTH_PROVIDERS` whose `AUTH_<KEY>_TYPE` is `ldap`. Every value passes
  the value reader of `Espalier.Identity.Config`, and an invalid value
  raises `Espalier.Identity.ConfigError` with a message that names the
  variable. `bind_password` is the only secret; `Inspect` leaves it out.

  | Variable | Default and rule |
  |---|---|
  | `AUTH_<KEY>_LABEL` | required |
  | `AUTH_<KEY>_HOST` | required; one DNS name that the server certificate covers; an IP literal only with `AUTH_<KEY>_TLS=none` |
  | `AUTH_<KEY>_PORT` | `636` for `ldaps`, `389` otherwise |
  | `AUTH_<KEY>_TLS` | `ldaps`, `starttls` or `none` (dev and test only) |
  | `AUTH_<KEY>_CA_CERT_FILE` | required unless the mode is `none`; the only trust anchors |
  | `AUTH_<KEY>_TLS_WILDCARD` | `false`; `true` adds RFC 6125 wildcard matching |
  | `AUTH_<KEY>_BIND_DN`, `AUTH_<KEY>_BIND_PASSWORD` | required |
  | `AUTH_<KEY>_BASE_DN` | required |
  | `AUTH_<KEY>_DIRECTORY` | `ad` or `generic` |
  | `AUTH_<KEY>_USER_ATTR` | `sAMAccountName,userPrincipalName` (`ad`), `uid` (`generic`) |
  | `AUTH_<KEY>_ORG_UNIT_ATTR` | optional |
  | `AUTH_<KEY>_ROLE_MAP` | `role=group DN;role=group DN` |
  | `AUTH_<KEY>_MFA` | `local`, the only mode |
  | `AUTH_<KEY>_TIMEOUT_MS` | `5000` |
  | `AUTH_<KEY>_FAILURE_LIMIT` | required, 1 to 49, below the directory's lockout threshold |
  | `AUTH_<KEY>_LOCK_MINUTES` | `30` |
  """

  alias Espalier.Identity.Config, as: IdentityConfig
  alias Espalier.Identity.ConfigError

  @attribute ~r/\A[A-Za-z][A-Za-z0-9-]*\z/
  @host_name ~r/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]*[a-z0-9])?)*\z/

  @tls_modes %{"ldaps" => :ldaps, "starttls" => :starttls, "none" => :none}
  @directories %{"ad" => :ad, "generic" => :generic}
  @default_user_attrs %{ad: "sAMAccountName,userPrincipalName", generic: "uid"}

  @derive {Inspect, except: [:bind_password]}
  defstruct [
    :key,
    :label,
    :start_url,
    :host,
    :port,
    :bind_dn,
    :bind_password,
    :base_dn,
    :org_unit_attr,
    :failure_limit,
    type: "ldap",
    kind: "credentials",
    client: Espalier.Identity.Ldap.Eldap,
    tls: :ldaps,
    cacerts: [],
    tls_wildcard: false,
    directory: :ad,
    user_attrs: [],
    role_map: [],
    mfa: :local,
    timeout_ms: 5000,
    lock_minutes: 30,
    provision: true
  ]

  @type t :: %__MODULE__{
          key: String.t(),
          type: String.t(),
          kind: String.t(),
          label: String.t(),
          start_url: String.t(),
          client: module(),
          host: charlist(),
          port: 1..65_535,
          tls: :ldaps | :starttls | :none,
          cacerts: [binary()],
          tls_wildcard: boolean(),
          bind_dn: String.t(),
          bind_password: String.t(),
          base_dn: String.t(),
          directory: :ad | :generic,
          user_attrs: [charlist()],
          org_unit_attr: charlist() | nil,
          role_map: [{atom(), String.t()}],
          mfa: :local,
          timeout_ms: pos_integer(),
          failure_limit: 1..49,
          lock_minutes: pos_integer(),
          provision: true
        }

  @doc """
  Returns the provider `key` from `env` (the map of `System.get_env/0`), or
  raises `ConfigError`. `config_env` is the Mix environment; the TLS mode
  `none` is refused outside `:dev` and `:test`.
  """
  @spec parse!(String.t(), %{optional(String.t()) => String.t()}, atom()) :: t()
  def parse!(key, env, config_env) when is_binary(key) and is_map(env) do
    ctx = %{key: key, env: env, prefix: "AUTH_#{String.upcase(key)}_"}

    if get(ctx, "TYPE") != "ldap" do
      raise ConfigError, "#{var(ctx, "TYPE")} must be ldap"
    end

    tls = tls!(ctx, config_env)
    directory = enum!(ctx, "DIRECTORY", @directories, :ad)

    %__MODULE__{
      key: key,
      label: required!(ctx, "LABEL"),
      start_url: "/api/auth/ldap/" <> key,
      host: host!(ctx, tls),
      port: port!(ctx, tls),
      tls: tls,
      cacerts: cacerts!(ctx, tls),
      tls_wildcard: boolean!(ctx, "TLS_WILDCARD", false),
      bind_dn: required!(ctx, "BIND_DN"),
      bind_password: required!(ctx, "BIND_PASSWORD"),
      base_dn: required!(ctx, "BASE_DN"),
      directory: directory,
      user_attrs: user_attrs!(ctx, directory),
      org_unit_attr: org_unit_attr!(ctx),
      role_map: IdentityConfig.role_map!(var(ctx, "ROLE_MAP"), get(ctx, "ROLE_MAP")),
      mfa: mfa!(ctx),
      timeout_ms: integer!(ctx, "TIMEOUT_MS", 5000, 1..86_400_000),
      failure_limit: failure_limit!(ctx),
      lock_minutes: integer!(ctx, "LOCK_MINUTES", 30, 1..525_600)
    }
  end

  defp tls!(ctx, config_env) do
    tls = enum!(ctx, "TLS", @tls_modes, :ldaps)

    if tls == :none and config_env not in [:dev, :test] do
      raise ConfigError, "#{var(ctx, "TLS")}=none is allowed only in dev and test"
    end

    tls
  end

  defp host!(ctx, tls) do
    host = ctx |> required!("HOST") |> String.downcase()
    charlist = String.to_charlist(host)

    case :inet.parse_address(charlist) do
      {:ok, _address} when tls == :none ->
        charlist

      {:ok, _address} ->
        raise ConfigError,
              "#{var(ctx, "HOST")} must be a DNS name that the server certificate covers, " <>
                "not an IP address"

      {:error, :einval} ->
        if not Regex.match?(@host_name, host) do
          raise ConfigError, "#{var(ctx, "HOST")} must be one DNS name"
        end

        charlist
    end
  end

  defp port!(ctx, tls) do
    integer!(ctx, "PORT", if(tls == :ldaps, do: 636, else: 389), 1..65_535)
  end

  defp cacerts!(_ctx, :none), do: []

  # The path comes from AUTH_<KEY>_CA_CERT_FILE of the operator's
  # environment at boot; no request reaches it.
  # sobelow_skip ["Traversal.FileModule"]
  defp cacerts!(ctx, _tls) do
    path = required!(ctx, "CA_CERT_FILE")

    pem =
      case File.read(path) do
        {:ok, pem} -> pem
        {:error, _reason} -> raise ConfigError, "#{var(ctx, "CA_CERT_FILE")} cannot be read"
      end

    certificates =
      for {:Certificate, der, :not_encrypted} <- :public_key.pem_decode(pem), do: der

    if certificates == [] do
      raise ConfigError, "#{var(ctx, "CA_CERT_FILE")} holds no certificate"
    end

    certificates
  end

  defp user_attrs!(ctx, directory) do
    value = get(ctx, "USER_ATTR") || Map.fetch!(@default_user_attrs, directory)

    case value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) do
      [] ->
        raise ConfigError, "#{var(ctx, "USER_ATTR")} must name at least one attribute"

      attrs ->
        Enum.map(attrs, &attribute!(ctx, "USER_ATTR", &1))
    end
  end

  defp org_unit_attr!(ctx) do
    case get(ctx, "ORG_UNIT_ATTR") do
      nil -> nil
      value -> attribute!(ctx, "ORG_UNIT_ATTR", value)
    end
  end

  defp attribute!(ctx, name, attr) do
    if not Regex.match?(@attribute, attr) do
      raise ConfigError,
            "#{var(ctx, name)} must hold attribute names of the form [A-Za-z][A-Za-z0-9-]*"
    end

    String.to_charlist(attr)
  end

  # A directory bind carries no second factor (README section 6.2).
  defp mfa!(ctx) do
    case get(ctx, "MFA") do
      nil -> :local
      "local" -> :local
      _other -> raise ConfigError, "#{var(ctx, "MFA")} must be local"
    end
  end

  defp failure_limit!(ctx) do
    if get(ctx, "FAILURE_LIMIT") == nil do
      raise ConfigError,
            "#{var(ctx, "FAILURE_LIMIT")} is required; set it below the directory's lockout threshold"
    end

    integer!(ctx, "FAILURE_LIMIT", nil, 1..49)
  end

  ## Value reader

  defp var(ctx, name), do: ctx.prefix <> name

  defp get(ctx, name), do: IdentityConfig.value(ctx.env, var(ctx, name))

  defp required!(ctx, name) do
    get(ctx, name) ||
      raise ConfigError, "#{var(ctx, name)} is required when #{var(ctx, "TYPE")}=ldap"
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

  defp integer!(ctx, name, default, first..last//_) do
    case get(ctx, name) do
      nil ->
        default

      value ->
        case Integer.parse(value) do
          {n, ""} when n >= first and n <= last -> n
          _ -> raise ConfigError, "#{var(ctx, name)} must be an integer from #{first} to #{last}"
        end
    end
  end
end
