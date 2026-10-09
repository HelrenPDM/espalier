defmodule Espalier.Accounts.RecoveryCodes do
  @moduledoc """
  Recovery codes (README section 6.6): ten single-use codes of 128 bits from
  `:crypto.strong_rand_bytes/1`, shown once as 26 base32 characters in groups
  of four.

  The table stores HMAC-SHA256 of each code under `key/0`, a key derived from
  `CLOAK_HMAC_SECRET` with the label `espalier/recovery-codes/v1`. At 128
  bits a keyed hash suffices (ASVS 6.5.2). A change of `CLOAK_HMAC_SECRET`
  invalidates every stored code. Plain codes are never stored, logged or
  mailed.
  """

  # The function use/2 has the name of README section 6.12.
  import Kernel, except: [use: 2]
  import Ecto.Query

  alias Espalier.Accounts.{RecoveryCode, Scope, User}
  alias Espalier.Repo

  @count 10
  @bytes 16
  @label "espalier/recovery-codes/v1"

  @doc """
  Replaces the user's codes by ten new ones in one transaction and returns
  their display forms, such as `ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ`.
  """
  def generate(%Scope{user: %User{} = user}) do
    codes =
      for _ <- 1..@count, do: Base.encode32(:crypto.strong_rand_bytes(@bytes), padding: false)

    now = DateTime.utc_now(:second)

    {:ok, _} =
      Repo.transact(fn ->
        Repo.delete_all(from r in RecoveryCode, where: r.user_id == ^user.id)

        rows =
          for code <- codes do
            %{
              id: Ecto.UUID.generate(),
              user_id: user.id,
              code_hmac: hmac(code),
              inserted_at: now,
              updated_at: now
            }
          end

        {count, _} = Repo.insert_all(RecoveryCode, rows)
        {:ok, count}
      end)

    Enum.map(codes, &display/1)
  end

  @doc """
  The HMAC key of recovery codes: HMAC-SHA256 of the label under the decoded
  `CLOAK_HMAC_SECRET` (configuration key of `Espalier.Hashed.HMAC`). The
  label separates it from the lookup hashes of task 0003.
  """
  def key do
    secret =
      :espalier
      |> Application.fetch_env!(Espalier.Hashed.HMAC)
      |> Keyword.fetch!(:secret)
      |> Base.decode64!()

    :crypto.mac(:hmac, :sha256, secret, @label)
  end

  @doc """
  Upcases the input and removes whitespace and hyphens. Returns
  `{:ok, code}` for 26 base32 characters, or `:error`.
  """
  def normalize(input) when is_binary(input) do
    code = input |> String.upcase() |> String.replace(~r/[\s-]/u, "")
    if code =~ ~r/\A[A-Z2-7]{26}\z/, do: {:ok, code}, else: :error
  end

  def normalize(_input), do: :error

  @doc """
  Uses one unused code of the user. Returns `{:ok, remaining}` with the
  number of unused codes left, or `{:error, :invalid_code}`. A concurrent
  use of the same code succeeds once.
  """
  def use(scope_or_user, input) do
    user = user_of(scope_or_user)

    with {:ok, code} <- normalize(input),
         mac = hmac(code),
         %RecoveryCode{id: id} <- find_unused(user, mac),
         {1, _} <-
           Repo.update_all(
             from(r in RecoveryCode, where: r.id == ^id and is_nil(r.used_at)),
             set: [used_at: DateTime.utc_now(:second)]
           ) do
      {:ok, remaining(user)}
    else
      _ -> {:error, :invalid_code}
    end
  end

  defp find_unused(user, mac) do
    from(r in RecoveryCode, where: r.user_id == ^user.id and is_nil(r.used_at))
    |> Repo.all()
    |> Enum.find(&Plug.Crypto.secure_compare(&1.code_hmac, mac))
  end

  @doc "Counts the unused codes of the user."
  def remaining(scope_or_user) do
    user = user_of(scope_or_user)

    Repo.aggregate(
      from(r in RecoveryCode, where: r.user_id == ^user.id and is_nil(r.used_at)),
      :count
    )
  end

  @doc "True when the user holds any recovery code row, used or not."
  def any?(scope_or_user) do
    user = user_of(scope_or_user)
    Repo.exists?(from r in RecoveryCode, where: r.user_id == ^user.id)
  end

  @doc "Returns the `inserted_at` of the current set, or `nil`."
  def generated_at(scope_or_user) do
    user = user_of(scope_or_user)
    Repo.one(from r in RecoveryCode, where: r.user_id == ^user.id, select: max(r.inserted_at))
  end

  defp hmac(code), do: :crypto.mac(:hmac, :sha256, key(), code)

  defp display(code) do
    code
    |> String.codepoints()
    |> Enum.chunk_every(4)
    |> Enum.map_join("-", &Enum.join/1)
  end

  defp user_of(%Scope{user: %User{} = user}), do: user
  defp user_of(%User{} = user), do: user
end
