defmodule Espalier.Identity.Ldap do
  @moduledoc """
  Sign-in against Active Directory or a generic LDAP server, a thin wrapper
  around `:eldap` (README section 6.8, task 0007,
  `docs/architecture/auth-ldap.puml`).

  `authenticate/4` checks its input, then runs the sign-in in a task under
  `Espalier.Identity.LdapTaskSupervisor` with a deadline of three times the
  provider timeout:

  1. Connection 1 (`lookup/2`): the read-only service account binds,
     searches exactly one person below the base DN with filters built by the
     `:eldap` constructors, and checks each mapped group with a base search
     on the person's DN.
  2. `before_bind` runs with the entry; the sign-in service reserves the
     directory failure counter there.
  3. Connection 2 (`verify_password/3`): a new connection binds with the DN
     that the server returned and the password unchanged.

  Each connection closes in an `after` block, and no request reaches a handle
  after an error or timeout, because `:eldap` does not match search
  responses by message id. Only the bare atom `:ok` of `simple_bind/3` and
  `start_tls/3` counts as success. No `{log, fun}` option reaches `:eldap`,
  because it would log the bind request with the password, and an exception
  inside the task is logged by its module only.

  Failure reasons: `:invalid_input`, `:connect_failed`, `:tls_failed`,
  `:service_bind_failed`, `:referral`, `:unavailable`, `:not_found`,
  `:ambiguous`, `:disabled`, `:no_identity_attribute`,
  `:group_lookup_failed`, `:bind_failed`, `:bind_rejected` and `:internal`,
  plus the errors of `before_bind`.
  """

  require Logger

  import Espalier.Identity.Ldap.Records

  alias Espalier.Identity.Ldap.{Config, Entry}

  @task_supervisor Espalier.Identity.LdapTaskSupervisor
  @max_username_bytes 256
  @max_password_bytes 1024
  @max_display_name 200

  # Microsoft's LDAP_MATCHING_RULE_IN_CHAIN (nested group membership).
  @in_chain ~c"1.2.840.113556.1.4.1941"
  @account_disabled 0x2

  @attributes %{
    ad: [
      ~c"objectGUID",
      ~c"userPrincipalName",
      ~c"sAMAccountName",
      ~c"mail",
      ~c"displayName",
      ~c"userAccountControl"
    ],
    generic: [~c"entryUUID", ~c"uid", ~c"mail", ~c"displayName", ~c"cn"]
  }

  @type reason :: atom()

  ## Providers

  @doc "Returns `{:ok, config}` for a configured LDAP provider key, and `:error` otherwise."
  @spec provider(term()) :: {:ok, Config.t()} | :error
  def provider(key) when is_binary(key) do
    case Enum.find(providers(), &(&1.key == key)) do
      nil -> :error
      config -> {:ok, config}
    end
  end

  def provider(_key), do: :error

  @doc "Returns the configured LDAP providers in the order of `AUTH_PROVIDERS`."
  @spec providers() :: [Config.t()]
  def providers do
    for %Config{} = config <- Application.get_env(:espalier, :identity_providers, []),
        do: config
  end

  @doc """
  Logs one info line per configured LDAP provider with key, host, port, TLS
  mode, directory profile and the number of mapped groups. Runs at boot.
  """
  @spec log_providers() :: :ok
  def log_providers do
    for config <- providers() do
      Logger.info(
        "LDAP provider #{config.key}: host #{config.host}, port #{config.port}, " <>
          "TLS #{config.tls}, directory #{config.directory}, " <>
          "#{config.role_map |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> length()} mapped groups"
      )
    end

    :ok
  end

  ## Sign-in

  @doc """
  Authenticates `username` with `password` at the directory of `config`.

  Returns `{:ok, entry, ticket}` or `{:error, reason, entry_or_nil,
  ticket_or_nil}`. `opts[:before_bind]` receives the entry before the user
  bind and returns `{:ok, ticket}` or `{:error, reason}`; an error skips the
  user bind. The default returns `{:ok, nil}`. A killed or crashed task
  returns `{:error, reason, nil, nil}`.
  """
  @spec authenticate(Config.t(), term(), term(), keyword()) ::
          {:ok, Entry.t(), term()} | {:error, reason(), Entry.t() | nil, term()}
  def authenticate(%Config{} = config, username, password, opts \\ []) do
    if valid_username?(username) and valid_password?(password) do
      before_bind = Keyword.get(opts, :before_bind, fn _entry -> {:ok, nil} end)

      task =
        Task.Supervisor.async_nolink(@task_supervisor, fn ->
          run(config, username, password, before_bind)
        end)

      case Task.yield(task, 3 * config.timeout_ms) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        nil -> {:error, :unavailable, nil, nil}
        {:exit, _reason} -> {:error, :internal, nil, nil}
      end
    else
      {:error, :invalid_input, nil, nil}
    end
  end

  defp run(config, username, password, before_bind) do
    case guarded(fn -> lookup(config, username) end) do
      {:ok, entry} -> reserve_and_bind(config, entry, password, before_bind)
      {:error, reason} -> {:error, reason, nil, nil}
    end
  end

  defp reserve_and_bind(config, entry, password, before_bind) do
    case guarded(fn -> before_bind.(entry) end) do
      {:ok, ticket} -> bind(config, entry, password, ticket)
      {:error, reason} -> {:error, reason, entry, nil}
    end
  end

  defp bind(config, entry, password, ticket) do
    case guarded(fn -> verify_password(config, entry, password) end) do
      :ok -> {:ok, entry, ticket}
      {:error, reason} -> {:error, reason, entry, ticket}
    end
  end

  # A FunctionClauseError carries the call arguments, which can include the
  # password, so only the exception module reaches the log.
  defp guarded(fun) do
    fun.()
  rescue
    exception ->
      Logger.error("LDAP sign-in step raised #{inspect(exception.__struct__)}")
      {:error, :internal}
  catch
    kind, _value ->
      Logger.error("LDAP sign-in step ended with #{inspect(kind)}")
      {:error, :internal}
  end

  ## Input guards (step 8)

  # :eldap blocks only the empty charlist: an empty binary password goes out
  # as an unauthenticated bind, and an empty binary DN with an empty password
  # as an anonymous bind.
  defp valid_username?(username),
    do: present?(username) and byte_size(username) <= @max_username_bytes

  defp valid_password?(password),
    do: present?(password) and byte_size(password) <= @max_password_bytes

  defp present?(value) when is_binary(value),
    do: String.valid?(value) and String.trim(value) != ""

  defp present?(_value), do: false

  ## Connection 1: service account (step 9)

  @doc """
  Looks up `username` through the service account on connection 1 and
  returns `{:ok, entry}` or `{:error, reason}`. The release function
  `Espalier.Release.reset_directory_lock/2` calls it directly.
  """
  @spec lookup(Config.t(), String.t()) :: {:ok, Entry.t()} | {:error, reason()}
  def lookup(%Config{} = config, username) do
    if valid_username?(username) do
      with_connection(config, &lookup_on(config, &1, String.trim(username)))
    else
      {:error, :invalid_input}
    end
  end

  defp lookup_on(config, handle, username) do
    with :ok <- service_bind(config, handle),
         {:ok, entries} <- search_person(config, handle, username),
         {:ok, raw} <- single(entries),
         {:ok, entry} <- to_entry(config, raw),
         {:ok, groups} <- groups(config, handle, entry.dn) do
      {:ok, %{entry | groups: groups}}
    end
  end

  # A result code or a referral is a failed service bind; a transport error
  # such as {:gen_tcp_error, :timeout} means the directory is unavailable.
  defp service_bind(config, handle) do
    case config.client.simple_bind(handle, config.bind_dn, config.bind_password) do
      :ok -> :ok
      {:ok, {:referral, _referrals}} -> {:error, :service_bind_failed}
      {:error, code} when is_atom(code) -> {:error, :service_bind_failed}
      _transport_error -> {:error, :unavailable}
    end
  end

  defp search_person(config, handle, username) do
    # The org unit attribute is a charlist, so List.wrap/1 would not wrap it.
    attributes =
      Map.fetch!(@attributes, config.directory) ++
        if(config.org_unit_attr, do: [config.org_unit_attr], else: [])

    config.client.search(handle,
      base: config.base_dn,
      scope: :eldap.wholeSubtree(),
      filter: person_filter(config, username),
      attributes: attributes,
      size_limit: 2,
      timeout: search_timeout(config)
    )
    |> search_entries()
  end

  @doc """
  Returns the search filter of the directory profile for `username`. The
  username goes out verbatim as an assertion value of the `:eldap`
  constructors, so it never becomes filter syntax.
  """
  @spec person_filter(Config.t(), String.t()) :: term()
  def person_filter(%Config{} = config, username) when is_binary(username) do
    user_filter =
      :eldap.or(for attr <- config.user_attrs, do: :eldap.equalityMatch(attr, username))

    case config.directory do
      :ad ->
        :eldap.and([
          :eldap.equalityMatch(~c"objectCategory", ~c"person"),
          :eldap.equalityMatch(~c"objectClass", ~c"user"),
          user_filter
        ])

      :generic ->
        :eldap.and([:eldap.equalityMatch(~c"objectClass", ~c"person"), user_filter])
    end
  end

  # The wrapper chases no referrals, so the referrals field is ignored.
  defp search_entries({:ok, eldap_search_result(entries: entries)}), do: {:ok, entries}
  defp search_entries({:ok, {:referral, _referrals}}), do: {:error, :referral}
  defp search_entries(_error), do: {:error, :unavailable}

  # The count is the control: size_limit is only a request to the server.
  defp single([]), do: {:error, :not_found}
  defp single([entry]), do: {:ok, entry}
  defp single([_ | _]), do: {:error, :ambiguous}

  # The search timeout is the server-side time limit in seconds.
  defp search_timeout(config), do: max(div(config.timeout_ms, 1000), 1)

  defp to_entry(config, eldap_entry(object_name: object_name, attributes: attributes)) do
    dn = :erlang.list_to_binary(object_name)

    attrs =
      Map.new(attributes, fn {name, values} ->
        {name |> :erlang.list_to_binary() |> String.downcase(),
         Enum.map(values, &:erlang.list_to_binary/1)}
      end)

    with :ok <- check_dn(dn),
         :ok <- check_enabled(config.directory, attrs),
         {:ok, subject} <- subject(config.directory, attrs) do
      {:ok,
       %Entry{
         dn: dn,
         subject: subject,
         login: first(attrs, login_attr(config.directory)),
         upn: if(config.directory == :ad, do: first(attrs, "userprincipalname")),
         email: first(attrs, "mail"),
         display_name: display_name(config.directory, attrs),
         org_unit: org_unit(config, attrs)
       }}
    end
  end

  defp check_dn(dn), do: if(present?(dn), do: :ok, else: {:error, :invalid_input})

  defp check_enabled(:generic, _attrs), do: :ok

  defp check_enabled(:ad, attrs) do
    with value when is_binary(value) <- first(attrs, "useraccountcontrol"),
         {flags, ""} <- Integer.parse(String.trim(value)),
         0 <- Bitwise.band(flags, @account_disabled) do
      :ok
    else
      _ -> {:error, :disabled}
    end
  end

  defp subject(:ad, attrs) do
    with [guid] <- Map.get(attrs, "objectguid"),
         {:ok, uuid} <- object_guid_to_uuid(guid) do
      {:ok, uuid}
    else
      _ -> {:error, :no_identity_attribute}
    end
  end

  defp subject(:generic, attrs) do
    with [value] <- Map.get(attrs, "entryuuid"),
         {:ok, uuid} <- Ecto.UUID.cast(String.trim(value)) do
      {:ok, uuid}
    else
      _ -> {:error, :no_identity_attribute}
    end
  end

  defp login_attr(:ad), do: "samaccountname"
  defp login_attr(:generic), do: "uid"

  defp display_name(:ad, attrs), do: clean_name(first(attrs, "displayname"))

  defp display_name(:generic, attrs),
    do: clean_name(first(attrs, "displayname")) || clean_name(first(attrs, "cn"))

  defp clean_name(nil), do: nil

  defp clean_name(name) do
    case name |> String.trim() |> String.slice(0, @max_display_name) do
      "" -> nil
      name -> name
    end
  end

  defp org_unit(%Config{org_unit_attr: nil}, _attrs), do: nil

  defp org_unit(config, attrs) do
    name = config.org_unit_attr |> :erlang.list_to_binary() |> String.downcase()

    case first(attrs, name) do
      nil -> nil
      value -> if String.trim(value) == "", do: nil, else: String.trim(value)
    end
  end

  defp first(attrs, name) do
    case Map.get(attrs, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  # One base search on the person's DN per mapped group; the matched group
  # DNs come back without duplicates in the order of the role map.
  defp groups(config, handle, dn) do
    config.role_map
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq()
    |> Enum.reduce_while({:ok, []}, fn group_dn, {:ok, matched} ->
      case member?(config, handle, dn, group_dn) do
        {:ok, true} -> {:cont, {:ok, [group_dn | matched]}}
        {:ok, false} -> {:cont, {:ok, matched}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, matched} -> {:ok, Enum.reverse(matched)}
      error -> error
    end
  end

  defp member?(config, handle, dn, group_dn) do
    result =
      config.client.search(handle,
        base: dn,
        scope: :eldap.baseObject(),
        filter: group_filter(config.directory, group_dn),
        attributes: [~c"1.1"],
        size_limit: 1,
        timeout: search_timeout(config)
      )

    case result do
      {:ok, eldap_search_result(entries: [_entry])} -> {:ok, true}
      {:ok, eldap_search_result(entries: [])} -> {:ok, false}
      # lldap answers a non-member this way.
      {:error, :noSuchObject} -> {:ok, false}
      _other -> {:error, :group_lookup_failed}
    end
  end

  @doc "Returns the membership filter of the directory profile for `group_dn`."
  @spec group_filter(:ad | :generic, String.t()) :: term()
  def group_filter(:ad, group_dn),
    do: :eldap.extensibleMatch(group_dn, type: ~c"memberOf", matchingRule: @in_chain)

  def group_filter(:generic, group_dn), do: :eldap.equalityMatch(~c"memberOf", group_dn)

  ## Connection 2: user bind (step 11)

  @doc """
  Binds as the person of `entry` with `password` on a new connection.
  Returns `:ok` or `{:error, reason}`. The user bind never runs on the
  service connection, because a failed bind leaves that connection
  anonymous.
  """
  @spec verify_password(Config.t(), Entry.t(), term()) :: :ok | {:error, reason()}
  def verify_password(%Config{} = config, %Entry{dn: dn}, password) do
    if present?(dn) and valid_password?(password) do
      with_connection(config, &user_bind(config, &1, dn, password))
    else
      {:error, :invalid_input}
    end
  end

  defp user_bind(config, handle, dn, password) do
    case config.client.simple_bind(handle, dn, password) do
      :ok -> :ok
      {:error, :invalidCredentials} -> {:error, :bind_failed}
      {:ok, {:referral, _referrals}} -> {:error, :referral}
      {:error, code} when is_atom(code) -> {:error, :bind_rejected}
      _other -> {:error, :unavailable}
    end
  end

  ## Connections (step 6)

  defp with_connection(config, fun) do
    case open(config) do
      {:ok, handle} ->
        try do
          with :ok <- start_tls(config, handle), do: fun.(handle)
        after
          config.client.close(handle)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp open(config) do
    opts =
      case config.tls do
        :ldaps ->
          [port: config.port, ssl: true, sslopts: tls_options(config), timeout: config.timeout_ms]

        # sslopts alone would switch :eldap to LDAPS.
        _starttls_or_none ->
          [port: config.port, timeout: config.timeout_ms]
      end

    case config.client.open([config.host], opts) do
      {:ok, handle} -> {:ok, handle}
      _error -> {:error, :connect_failed}
    end
  end

  # {:ok, {:referral, _}} leaves the connection in plain text.
  defp start_tls(%Config{tls: :starttls} = config, handle) do
    case config.client.start_tls(handle, tls_options(config), config.timeout_ms) do
      :ok -> :ok
      _other -> {:error, :tls_failed}
    end
  end

  defp start_tls(_config, _handle), do: :ok

  @doc """
  Returns the TLS options of the directory connections: peer verification
  against the configured CA certificates only, the host name through
  `server_name_indication`, which StartTLS otherwise checks against the
  peer IP address, and TLS 1.3 and 1.2.
  """
  @spec tls_options(Config.t()) :: keyword()
  def tls_options(%Config{} = config) do
    [
      verify: :verify_peer,
      cacerts: config.cacerts,
      server_name_indication: config.host,
      versions: [:"tlsv1.3", :"tlsv1.2"]
    ] ++
      if config.tls_wildcard,
        do: [
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ],
        else: []
  end

  ## Identity key (step 10)

  @doc """
  Converts the 16 bytes of an `objectGUID` to a UUID string. The first three
  fields are little-endian, and the last eight bytes keep their order
  (MS-DTYP 2.3.4.2).
  """
  @spec object_guid_to_uuid(term()) :: {:ok, String.t()} | :error
  def object_guid_to_uuid(<<a::little-32, b::little-16, c::little-16, rest::binary-size(8)>>),
    do: Ecto.UUID.load(<<a::32, b::16, c::16, rest::binary>>)

  def object_guid_to_uuid(_guid), do: :error

  ## Diagnostics (step 30)

  @doc """
  Opens a TLS connection with the options of `tls_options/1`, closes it,
  and returns `:ok` or `{:error, reason}`. It sends no bind and no
  credential.
  """
  @spec tls_probe(Config.t()) :: :ok | {:error, term()}
  def tls_probe(%Config{} = config) do
    case :ssl.connect(config.host, config.port, tls_options(config), config.timeout_ms) do
      {:ok, socket} ->
        :ssl.close(socket)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reduces an error of `tls_probe/1` to the atom that the security log
  carries. It returns the alert name of a TLS alert, the atom of an atom
  result, and `:other` otherwise.
  """
  @spec reason_tag(term()) :: atom()
  def reason_tag({:tls_alert, {name, _description}}) when is_atom(name), do: name
  def reason_tag(reason) when is_atom(reason) and not is_nil(reason), do: reason
  def reason_tag(_reason), do: :other

  @doc """
  Runs the service bind and a base-scope search on the base DN and returns
  one `{step, result}` pair per step, with `:ok` or `{:error, reason}`.
  `Espalier.Release.check_ldap/1` prints them. The result holds no
  directory data.
  """
  @spec check_service(Config.t()) :: [{atom(), :ok | {:error, atom()}}]
  def check_service(%Config{} = config) do
    case open(config) do
      {:ok, handle} ->
        try do
          [connect: :ok] ++ service_steps(config, handle)
        after
          config.client.close(handle)
        end

      error ->
        [connect: error]
    end
  end

  defp service_steps(%Config{tls: :starttls} = config, handle) do
    case start_tls(config, handle) do
      :ok -> [start_tls: :ok] ++ service_steps(%{config | tls: :started}, handle)
      error -> [start_tls: error]
    end
  end

  defp service_steps(config, handle) do
    case service_bind(config, handle) do
      :ok -> [service_bind: :ok, base_search: base_search(config, handle)]
      error -> [service_bind: error]
    end
  end

  # The step shows that the service account may search the base DN; the
  # entries do not matter, because lldap 0.6.3 answers a base-scope search
  # on the base DN with the whole subtree. A result code is printed as is.
  defp base_search(config, handle) do
    result =
      config.client.search(handle,
        base: config.base_dn,
        scope: :eldap.baseObject(),
        filter: :eldap.present(~c"objectClass"),
        attributes: [~c"1.1"],
        size_limit: 1,
        timeout: search_timeout(config)
      )

    case result do
      {:ok, eldap_search_result()} -> :ok
      {:ok, {:referral, _referrals}} -> {:error, :referral}
      {:error, code} when is_atom(code) -> {:error, code}
      _other -> {:error, :unavailable}
    end
  end
end
