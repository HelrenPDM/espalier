# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule Espalier.Accounts.UserToken do
  @moduledoc """
  One table for session tokens and e-mail tokens (README section 6.5).

  Every token is 32 bytes from `:crypto.strong_rand_bytes/1`, and the table
  stores only its SHA-256 hash in `token_hash`. A session row records the
  methods and the strength of its sign-in and expires after inactivity and at
  an absolute limit, both checked on the server.

  `idp_sid_hash` is a plain `:binary` field: its value comes once from
  `hash_idp_sid/1` and is copied unchanged from row to row. The type
  `Espalier.Hashed.HMAC` would hash every copy a second time.

  Sign-in tickets (`login_ticket`) and OIDC intents (`oidc_intent`) of task
  0006 carry `purpose`, the keyed hash `binding_hash` (the ticket's binding
  or the id of the session that created an intent) and, for a link ticket,
  the encrypted `link_identity`. These three stay `nil` on session rows, so
  a session copy never meets a value in a keyed-hash field. `idp_amr` holds
  the provider's `amr` values of a federated sign-in.
  """
  use Ecto.Schema
  import Ecto.Query

  alias Espalier.Accounts.{User, UserToken}
  alias Espalier.Hashed.HMAC

  @hash_algorithm :sha256
  @rand_size 32

  # E-mail links live 10 minutes (ASVS 6.4.1, 6.5.5).
  @email_validity_in_minutes 10
  # Enrollment and recovery sessions live 30 minutes (README section 6.5).
  @limited_session_minutes 30

  @contexts [:session, :invite, :change_email, :recovery_email, :login_ticket, :oidc_intent]
  @methods [
    :passkey,
    :password,
    :totp,
    :recovery_code,
    :email_code,
    :oidc,
    :ldap,
    :idp_mfa,
    :demo
  ]
  @strengths [:mfa, :recovery, :enrollment, :demo]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "users_tokens" do
    field :token_hash, :binary, redact: true
    field :context, Ecto.Enum, values: @contexts
    field :sent_to_hash, Espalier.Hashed.HMAC, redact: true
    field :new_email, Espalier.Encrypted.Binary, redact: true
    field :authenticated_at, :utc_datetime
    field :auth_methods, {:array, Ecto.Enum}, values: @methods, default: []
    field :strength, Ecto.Enum, values: @strengths
    field :mfa_at, :utc_datetime
    field :provider_key, :string
    field :idp_sid_hash, :binary, redact: true
    field :idp_amr, {:array, :string}
    field :purpose, :string
    field :binding_hash, Espalier.Hashed.HMAC, redact: true
    field :link_identity, Espalier.Encrypted.Binary, redact: true
    field :device_summary, :string
    field :last_seen_at, :utc_datetime
    field :expires_at, :utc_datetime
    belongs_to :user, User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc "Returns the 32 random bytes of a new token."
  @spec generate() :: binary()
  def generate, do: :crypto.strong_rand_bytes(@rand_size)

  @doc "Returns the SHA-256 hash that `token_hash` stores for a raw token."
  @spec hash(binary()) :: binary()
  def hash(token) when is_binary(token), do: :crypto.hash(@hash_algorithm, token)

  @doc "Returns the method atom of its name; raises for an unknown name."
  @spec method!(String.t()) :: atom()
  def method!(name) when is_binary(name) do
    Enum.find(@methods, &(Atom.to_string(&1) == name)) ||
      raise ArgumentError, "unknown authentication method"
  end

  @doc "Lifetime of enrollment and recovery sessions in minutes."
  def limited_session_minutes, do: @limited_session_minutes

  @doc """
  Returns the keyed hash of an identity provider's `sid`, or `nil`.

  The value is HMAC-SHA256 under `CLOAK_HMAC_SECRET`, computed once from the
  raw `sid`. Every later step carries the stored bytes unchanged.
  """
  @spec hash_idp_sid(String.t() | nil) :: binary() | nil
  def hash_idp_sid(nil), do: nil
  def hash_idp_sid(sid) when is_binary(sid), do: HMAC.hash(sid)

  @doc """
  True when `strength` fits the methods of a sign-in (README section 6.2).

  `mfa` needs a passkey, the provider's MFA, or TOTP or a recovery code
  together with a password, OIDC or LDAP. The completion of an enrollment
  (`[:email_code, :totp]`) or of a recovery (`[:recovery_code, :email_code,
  :totp]`) reaches `mfa` only with the attribute `completes:` of
  `Espalier.Accounts.Factors.complete_enrollment/3`, which no column
  stores. Enrollment sessions start from an invitation link or from a
  federated sign-in without a local factor (tasks 0006 and 0007).
  """
  @spec strength_valid?(atom(), [atom()], map() | keyword()) :: boolean()
  def strength_valid?(strength, methods, attrs \\ %{})

  def strength_valid?(:mfa, [:email_code, :totp], attrs),
    do: completes(attrs) == :enrollment

  def strength_valid?(:mfa, [:recovery_code, :email_code, :totp], attrs),
    do: completes(attrs) == :recovery

  def strength_valid?(:mfa, methods, _attrs) when is_list(methods) do
    :passkey in methods or :idp_mfa in methods or
      ((:totp in methods or :recovery_code in methods) and
         Enum.any?([:password, :oidc, :ldap], &(&1 in methods)))
  end

  def strength_valid?(:enrollment, [first], _attrs) when first in [:email_code, :oidc, :ldap],
    do: true

  def strength_valid?(:demo, [:demo], _attrs), do: true

  def strength_valid?(:recovery, methods, _attrs) when is_list(methods) do
    :recovery_code in methods and :email_code in methods
  end

  def strength_valid?(_strength, _methods, _attrs), do: false

  defp completes(attrs), do: attrs |> Map.new() |> Map.get(:completes)

  @doc """
  Builds a session row for `user` and returns `{token, row}`.

  `expires_at` is now plus `SESSION_MAX_HOURS`, or plus 30 minutes for
  enrollment and recovery sessions.
  """
  def build_session_token(user, attrs, now) do
    token = generate()
    strength = Map.fetch!(attrs, :strength)

    expires_at =
      if strength in [:enrollment, :recovery] do
        DateTime.add(now, @limited_session_minutes, :minute)
      else
        DateTime.add(now, session_max_hours(), :hour)
      end

    {token,
     %UserToken{
       token_hash: hash(token),
       context: :session,
       user_id: user.id,
       authenticated_at: now,
       last_seen_at: now,
       expires_at: expires_at,
       auth_methods: Map.fetch!(attrs, :auth_methods),
       strength: strength,
       mfa_at: Map.get(attrs, :mfa_at),
       provider_key: Map.get(attrs, :provider_key),
       idp_sid_hash: Map.get(attrs, :idp_sid_hash),
       idp_amr: Map.get(attrs, :idp_amr),
       device_summary: Map.get(attrs, :device_summary)
     }}
  end

  @doc """
  Builds an e-mail token for `user` and returns `{encoded_token, row}`.

  `sent_to` is the normalized address the link goes to; the row stores its
  keyed hash. `new_email` is stored encrypted for an e-mail change.
  """
  def build_email_token(user, context, sent_to, opts \\ [])
      when context in [:invite, :change_email, :recovery_email] do
    token = generate()
    now = Keyword.get(opts, :now, DateTime.utc_now(:second))

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token_hash: hash(token),
       context: context,
       sent_to_hash: sent_to,
       new_email: Keyword.get(opts, :new_email),
       user_id: user.id,
       expires_at: DateTime.add(now, @email_validity_in_minutes, :minute)
     }}
  end

  @doc """
  Decodes an e-mail token and returns the query for its live row with the
  user, or `:error`.
  """
  def verify_email_token_query(token, context, now \\ DateTime.utc_now()) do
    with true <- is_binary(token),
         {:ok, decoded} <- Base.url_decode64(token, padding: false) do
      query =
        from t in by_hash_and_context_query(hash(decoded), context),
          join: user in assoc(t, :user),
          where: t.expires_at > ^now,
          select: {user, t}

      {:ok, query}
    else
      _ -> :error
    end
  end

  @doc "Query of the rows with `token_hash` and `context`."
  def by_hash_and_context_query(token_hash, context) do
    from UserToken, where: [token_hash: ^token_hash, context: ^context]
  end

  @doc "Query of the session rows of a user."
  def user_sessions_query(user_id) do
    from t in UserToken, where: t.user_id == ^user_id and t.context == :session
  end

  defp session_max_hours, do: Application.get_env(:espalier, :session_max_hours, 24)
end
