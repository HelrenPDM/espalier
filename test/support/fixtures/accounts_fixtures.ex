# Derived from phx.gen.auth (Phoenix 1.8.15).
defmodule Espalier.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Espalier.Accounts` context.
  """

  import Ecto.Query

  alias Espalier.Accounts
  alias Espalier.Accounts.{ExternalIdentity, Scope, User, UserToken}
  alias Espalier.Repo

  def unique_user_email, do: "user#{System.unique_integer([:positive])}@example.com"
  def valid_user_password, do: "plum orbit lantern 4719"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email()
    })
  end

  @doc "An invited local user that has not accepted the invitation."
  def unconfirmed_user_fixture(attrs \\ %{}) do
    %User{}
    |> User.invite_changeset(valid_user_attributes(attrs))
    |> Repo.insert!()
  end

  @doc """
  An active, confirmed local user with the password `valid_user_password/0`,
  or with `attrs[:password]` (`nil` for none).
  """
  def user_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)
    {password, attrs} = Map.pop(attrs, :password, valid_user_password())

    user =
      attrs
      |> unconfirmed_user_fixture()
      |> User.confirm_changeset()
      |> Repo.update!()

    if password, do: set_password(user, password), else: user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user, password \\ valid_user_password()) do
    user
    |> User.password_changeset(%{password: password})
    |> Repo.update!()
  end

  @doc "Gives the user an external identity of `provider_key`."
  def external_identity_fixture(user, attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        provider_key: "test",
        issuer: "https://issuer.example.org",
        subject: "subject-#{System.unique_integer([:positive])}"
      })

    %ExternalIdentity{}
    |> ExternalIdentity.changeset(attrs, Scope.for_user(user))
    |> Repo.insert!()
  end

  @doc """
  Creates a session row with `strength: :mfa`, `auth_methods: [:password,
  :totp]` and `mfa_at` now, overridable through `attrs`, and returns
  `{token, session}`.
  """
  def session_fixture(user, attrs \\ %{}) do
    now = DateTime.utc_now(:second)

    Accounts.create_session(
      user,
      Map.merge(%{strength: :mfa, auth_methods: [:password, :totp], mfa_at: now}, Map.new(attrs))
    )
  end

  @doc "Inserts an e-mail token row for `user` and returns `{token, row}`."
  def email_token_fixture(user, context, sent_to \\ nil, opts \\ []) do
    {token, row} = UserToken.build_email_token(user, context, sent_to || user.email, opts)
    {token, Repo.insert!(row)}
  end

  @doc "Returns the token of the link in a captured mail body."
  def extract_link_token(%Swoosh.Email{text_body: body}) do
    [_, token] = Regex.run(~r/#token=([A-Za-z0-9_-]+)/, body)
    token
  end

  @doc """
  Sets `mfa_at`, `last_seen_at`, `expires_at` or `authenticated_at` of the
  session row of `token`, for timeout tests.
  """
  def override_session(token, attrs) when is_binary(token) do
    Repo.update_all(
      from(t in UserToken, where: t.token_hash == ^UserToken.hash(token)),
      set: Enum.to_list(attrs)
    )
  end

  @doc "Returns the session rows of `provider_key` whose `idp_sid_hash` holds `sid_hash`."
  def sessions_with_idp_sid(provider_key, sid_hash) do
    Repo.all(
      from t in UserToken,
        where: t.provider_key == ^provider_key and t.idp_sid_hash == ^sid_hash
    )
  end

  @doc "Returns the session row of a raw token."
  def session_row(token) do
    Repo.one(from t in UserToken, where: t.token_hash == ^UserToken.hash(token))
  end
end
