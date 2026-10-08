defmodule Espalier.Accounts.Demo do
  @moduledoc """
  Pseudonymous demo accounts for test sessions (`AUTH_DEMO=true`, README
  section 6.2). Slot `n` (1 to 20) is the user `Test person <n>` without an
  address, keyed by the external identity `demo`/`slot-<n>`, so a demo user
  keeps its id and its records across sign-ins and restarts. Demo users hold
  only `learner`.
  """

  alias Espalier.Accounts.{ExternalIdentity, Scope, User}
  alias Espalier.Repo

  @provider_key "demo"
  @slots 1..20

  @doc "The valid slots."
  def slots, do: @slots

  @doc "The provider key of demo identities."
  def provider_key, do: @provider_key

  @doc "Returns the user of `slot`, creating it at its first use."
  def get_or_create_user(slot) when is_integer(slot) and slot in @slots do
    case lookup(slot) do
      %User{} = user -> {:ok, user}
      nil -> create(slot)
    end
  end

  defp lookup(slot) do
    case Repo.get_by(ExternalIdentity,
           provider_key: @provider_key,
           subject_hash: hash_input(slot)
         ) do
      nil -> nil
      identity -> Repo.get(User, identity.user_id)
    end
  end

  # A concurrent request may create the identity first; the unique index on
  # (provider_key, subject_hash) then rolls this transaction back, and the
  # lookup runs once more.
  defp create(slot) do
    result =
      Repo.transact(fn ->
        with {:ok, user} <-
               %User{}
               |> User.profile_changeset(%{display_name: "Test person #{slot}", locale: "en"})
               |> Repo.insert(),
             {:ok, _identity} <-
               %ExternalIdentity{}
               |> ExternalIdentity.changeset(
                 %{provider_key: @provider_key, issuer: @provider_key, subject: subject(slot)},
                 Scope.for_user(user)
               )
               |> Repo.insert() do
          {:ok, user}
        end
      end)

    case result do
      {:ok, user} ->
        {:ok, user}

      {:error, _changeset} ->
        case lookup(slot) do
          %User{} = user -> {:ok, user}
          nil -> {:error, :demo_unavailable}
        end
    end
  end

  defp subject(slot), do: "slot-#{slot}"

  defp hash_input(slot), do: ExternalIdentity.hash_input(@provider_key, nil, subject(slot))
end
