defmodule Espalier.Accounts.Totp do
  @moduledoc """
  TOTP factors with `nimble_totp` 1.0.0 (README section 6.6): a 20-byte
  secret, HMAC-SHA-1, six digits, 30-second steps (decision D14).

  A factor counts once a valid code has confirmed it (`enabled_at`).
  Verification accepts the current and the previous step (decision D15) and
  stores the matched step in `last_used_step` with a conditional update, so
  each code works once, also under concurrent requests (ASVS 6.5.1).
  """

  import Ecto.Query

  alias Espalier.Accounts
  alias Espalier.Accounts.{Factors, Scope, TotpFactor, User}
  alias Espalier.Repo

  @period 30

  @doc "True when the user holds a confirmed TOTP factor."
  def enabled?(%User{id: user_id}) do
    Repo.exists?(from f in TotpFactor, where: f.user_id == ^user_id and not is_nil(f.enabled_at))
  end

  @doc "Returns the confirmed TOTP factor of the user, or `nil`."
  def get_enabled(%User{id: user_id}) do
    Repo.one(from f in TotpFactor, where: f.user_id == ^user_id and not is_nil(f.enabled_at))
  end

  @doc "Puts the plain 20-byte secret; the closure type encrypts it on dump."
  def put_secret(%Ecto.Changeset{} = changeset, secret) when is_binary(secret) do
    Ecto.Changeset.put_change(changeset, :secret, secret)
  end

  @doc """
  Returns the plain secret. A loaded factor holds `fn -> secret end`; the
  struct that `Repo.insert/1` returns holds the cast value, the plain binary.
  """
  def secret!(%TotpFactor{secret: secret}) when is_function(secret, 0), do: secret.()
  def secret!(%TotpFactor{secret: secret}) when is_binary(secret), do: secret

  @doc """
  Starts the enrollment of a TOTP factor for the scope's user.

  An enabled factor answers `{:error, :totp_already_enabled}` in an `mfa`
  session; in a `recovery` session it is deleted in the same transaction
  and the user receives the mail "factor removed". An unconfirmed factor is
  replaced. The transaction locks the user row first, so concurrent starts
  run one after the other and the last one leaves the only row. Returns
  `{:ok, %{qr_svg_data_url:, secret_base32:, otpauth_uri:}}`.
  """
  def start_enrollment(%Scope{user: user, session: session} = scope) do
    strength = session && session.strength

    Repo.transact(fn ->
      Accounts.lock_user!(user)
      existing = Repo.one(from f in TotpFactor, where: f.user_id == ^user.id)

      if existing && existing.enabled_at && strength != :recovery,
        do: {:error, :totp_already_enabled},
        else: replace_factor(scope, existing, strength)
    end)
  end

  defp replace_factor(scope, existing, strength) do
    if existing do
      Repo.delete!(existing)

      if existing.enabled_at && strength == :recovery do
        Factors.notify_change(scope.user, :factor_removed, :totp)
      end
    end

    secret = NimbleTOTP.secret()

    %TotpFactor{}
    |> TotpFactor.changeset(%{}, scope)
    |> put_secret(secret)
    |> Repo.insert!()

    {:ok, enrollment_payload(scope.user, secret)}
  end

  defp enrollment_payload(user, secret) do
    issuer = Application.get_env(:espalier, :totp_issuer, "Espalier")
    label = user.email || user.display_name
    uri = NimbleTOTP.otpauth_uri("#{issuer}:#{label}", secret, issuer: issuer)
    svg = uri |> EQRCode.encode() |> EQRCode.svg()

    %{
      qr_svg_data_url: "data:image/svg+xml;base64," <> Base.encode64(svg),
      secret_base32: Base.encode32(secret, padding: false),
      otpauth_uri: uri
    }
  end

  @doc """
  Verifies a six-digit code against the current and the previous step at
  `now` (Unix seconds). Each candidate step must lie after
  `last_used_step`; a match stores the step only when no concurrent request
  stored it first. Returns `:ok` or `{:error, :invalid_code}`.
  """
  def verify(%TotpFactor{} = factor, code, now \\ System.os_time(:second)) do
    if is_binary(code) and code =~ ~r/\A\d{6}\z/ do
      secret = secret!(factor)
      step = div(now, @period)

      [step, step - 1]
      |> Enum.filter(&after_last_used?(factor, &1))
      |> Enum.find(&Plug.Crypto.secure_compare(code_at(secret, &1), code))
      |> claim_step(factor)
    else
      {:error, :invalid_code}
    end
  end

  defp after_last_used?(%TotpFactor{last_used_step: nil}, _step), do: true
  defp after_last_used?(%TotpFactor{last_used_step: last}, step), do: step > last

  defp code_at(secret, step), do: NimbleTOTP.verification_code(secret, time: step * @period)

  defp claim_step(nil, _factor), do: {:error, :invalid_code}

  defp claim_step(step, factor) do
    query =
      from f in TotpFactor,
        where: f.id == ^factor.id and (is_nil(f.last_used_step) or f.last_used_step < ^step)

    case Repo.update_all(query, set: [last_used_step: step]) do
      {1, _} -> :ok
      _ -> {:error, :invalid_code}
    end
  end

  @doc """
  Confirms the unconfirmed factor of the scope's user with a code and sets
  `enabled_at`. The confirmation code is then used. Returns `{:ok, factor}`,
  `{:error, :invalid_code}` or `{:error, :no_pending_factor}`.
  """
  def confirm(%Scope{user: user}, code, now \\ System.os_time(:second)) do
    case Repo.one(from f in TotpFactor, where: f.user_id == ^user.id and is_nil(f.enabled_at)) do
      nil ->
        {:error, :no_pending_factor}

      factor ->
        with :ok <- verify(factor, code, now) do
          enabled_at = DateTime.from_unix!(now) |> DateTime.truncate(:second)

          {1, [confirmed]} =
            Repo.update_all(
              from(f in TotpFactor, where: f.id == ^factor.id, select: f),
              set: [enabled_at: enabled_at]
            )

          {:ok, confirmed}
        end
    end
  end

  @doc """
  Deletes the TOTP factor of the scope's user. The caller checks the factor
  rules first (`Espalier.Accounts.Factors.removable?/2`). Returns `:ok` or
  `{:error, :not_found}`.
  """
  def disable(%Scope{user: user}) do
    case Repo.delete_all(from f in TotpFactor, where: f.user_id == ^user.id) do
      {0, _} -> {:error, :not_found}
      {_count, _} -> :ok
    end
  end
end
