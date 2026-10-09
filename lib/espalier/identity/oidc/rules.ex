defmodule Espalier.Identity.Oidc.Rules do
  @moduledoc """
  Provider rules and claim normalization after oidcc has validated the ID
  token (task 0006, step 8; README sections 6.2 and 6.7).

  - Every provider: the `alg` of the protected header is RS256, PS256 or
    ES256 (ASVS 9.1.1), whatever the discovery document lists.
  - `entra`: `tid` equals the configured tenant, `oid` is present and keys
    the identity, and a groups overage indicator fails the sign-in.
  - `google`: `hd` equals the configured hosted domain.
  - `oidc`: roles come from `AUTH_<KEY>_ROLE_CLAIM`, which must not be a
    distributed claim.
  - A step-up needs an `auth_time` from the step-up request on
    (`max_age=0`, OpenID Connect Core 1.0, section 2).

  `preferred_username` and `upn` are never read (ASVS 10.5.2).
  """

  alias Espalier.Identity.{Assertion, OidcProvider}

  @allowed_algs ["RS256", "PS256", "ES256"]
  @display_name_length 200
  @clock_skew_seconds 60

  @doc """
  Checks the claims of a validated ID token against the provider's rules and
  returns `{:ok, %Assertion{}}` or `{:error, reason}`. `tx` is the
  transaction map of the authorize step (`"purpose"`, `"requested_at"`).
  """
  @spec check(OidcProvider.t(), String.t(), map(), map()) ::
          {:ok, Assertion.t()} | {:error, atom()}
  def check(%OidcProvider{} = provider, id_token, claims, tx) when is_map(claims) do
    with :ok <- check_alg(id_token),
         {:ok, assertion} <- by_type(provider, claims),
         :ok <- check_auth_time(assertion, tx) do
      {:ok, assertion}
    end
  end

  defp check_alg(id_token) do
    case id_token |> JOSE.JWS.peek_protected() |> JSON.decode!() do
      %{"alg" => alg} when alg in @allowed_algs -> :ok
      _header -> {:error, :alg_not_allowed}
    end
  rescue
    _ -> {:error, :alg_not_allowed}
  end

  defp by_type(%OidcProvider{type: "entra"} = provider, claims) do
    tid = string(claims["tid"])
    oid = string(claims["oid"])

    cond do
      is_nil(tid) or String.downcase(tid) != provider.tenant_id ->
        {:error, :tenant_mismatch}

      is_nil(oid) ->
        {:error, :missing_claim}

      overage?(claims) ->
        {:error, :groups_overage}

      true ->
        {:ok,
         assertion(provider, claims, oid, String.downcase(tid), string_list(claims["roles"]))}
    end
  end

  defp by_type(%OidcProvider{type: "google"} = provider, claims) do
    hd = string(claims["hd"])
    sub = string(claims["sub"])

    cond do
      is_nil(hd) or String.downcase(hd) != provider.hosted_domain -> {:error, :domain_mismatch}
      is_nil(sub) -> {:error, :missing_claim}
      true -> {:ok, assertion(provider, claims, sub, nil, [])}
    end
  end

  defp by_type(%OidcProvider{type: "oidc"} = provider, claims) do
    sub = string(claims["sub"])

    cond do
      is_nil(sub) ->
        {:error, :missing_claim}

      distributed?(claims, provider.role_claim) ->
        {:error, :distributed_role_claim}

      true ->
        {:ok, assertion(provider, claims, sub, nil, string_list(claims[provider.role_claim]))}
    end
  end

  defp overage?(claims) do
    distributed?(claims, "groups") or claims["hasgroups"] == true
  end

  defp distributed?(claims, name) do
    case claims["_claim_names"] do
      %{} = names -> Map.has_key?(names, name)
      _ -> false
    end
  end

  defp assertion(provider, claims, subject, tenant_id, roles) do
    %Assertion{
      provider_key: provider.key,
      issuer: provider.issuer,
      tenant_id: tenant_id,
      subject: subject,
      display_name: display_name(claims["name"]),
      email: email(provider, claims),
      roles: roles,
      amr: if(string_list?(claims["amr"]), do: claims["amr"]),
      auth_time: if(is_integer(claims["auth_time"]), do: claims["auth_time"]),
      sid: string(claims["sid"])
    }
  end

  # Only a verified address is kept; for Entra ID the optional claim
  # xms_edov marks a verified e-mail domain.
  defp email(provider, claims) do
    verified? =
      claims["email_verified"] == true or
        (provider.type == "entra" and claims["xms_edov"] == true)

    if verified?, do: string(claims["email"])
  end

  defp display_name(name) when is_binary(name) do
    case name |> String.trim() |> String.slice(0, @display_name_length) do
      "" -> nil
      name -> name
    end
  end

  defp display_name(_name), do: nil

  defp check_auth_time(%Assertion{auth_time: auth_time}, %{"purpose" => "step_up"} = tx) do
    requested_at = Map.get(tx, "requested_at", 0)

    if is_integer(auth_time) and auth_time >= requested_at - @clock_skew_seconds,
      do: :ok,
      else: {:error, :stale_auth_time}
  end

  defp check_auth_time(_assertion, _tx), do: :ok

  @doc """
  True when the provider runs in `idp_trusted` mode and the ID token either
  carries no `amr` (the operator's statement of README section 6.2, rule 4)
  or an `amr` with a value of `AUTH_<KEY>_MFA_AMR`. An `amr` such as
  `["pwd"]` makes it false; in `local` mode it is always false.
  """
  @spec idp_mfa?(OidcProvider.t(), Assertion.t()) :: boolean()
  def idp_mfa?(%OidcProvider{mfa: :idp_trusted, mfa_amr: mfa_amr}, %Assertion{amr: amr}) do
    is_nil(amr) or Enum.any?(amr, &(&1 in mfa_amr))
  end

  def idp_mfa?(%OidcProvider{}, %Assertion{}), do: false

  defp string(value) when is_binary(value) and value != "", do: value
  defp string(_value), do: nil

  defp string_list(values), do: if(string_list?(values), do: values, else: [])

  defp string_list?(values), do: is_list(values) and Enum.all?(values, &is_binary/1)
end
