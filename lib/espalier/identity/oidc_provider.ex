defmodule Espalier.Identity.OidcProvider do
  @moduledoc """
  An OIDC provider of the types `entra`, `google` and `oidc`, parsed from the
  environment by `Espalier.Identity.Config.parse!/2` (task 0006, step 3).

  `kind` is `"redirect"`, `start_url` is `"/auth/oidc/" <> key`, and
  `worker` names the `Oidcc.ProviderConfiguration.Worker` of the provider.
  `client_secret` is the only secret; `Inspect` leaves it out.
  """

  @derive {Inspect, except: [:client_secret]}
  defstruct [
    :key,
    :type,
    :label,
    :issuer,
    :tenant_id,
    :client_id,
    :client_secret,
    :cert_file,
    :key_file,
    :kid_format,
    :client_auth,
    :hosted_domain,
    :role_claim,
    :redirect_uri,
    :start_url,
    :worker,
    kind: "redirect",
    role_map: [],
    mfa: :local,
    mfa_amr: ["mfa"],
    provision: false,
    allowed_hosts: []
  ]

  @type t :: %__MODULE__{
          key: String.t(),
          type: String.t(),
          kind: String.t(),
          label: String.t(),
          start_url: String.t(),
          issuer: String.t(),
          tenant_id: String.t() | nil,
          client_id: String.t(),
          client_secret: String.t() | nil,
          cert_file: String.t() | nil,
          key_file: String.t() | nil,
          kid_format: :x5t_s256 | :x5t | :sha1_hex | nil,
          client_auth: :client_secret_basic | :client_secret_post | :private_key_jwt,
          hosted_domain: String.t() | nil,
          role_claim: String.t() | nil,
          role_map: [{atom(), String.t()}],
          mfa: :local | :idp_trusted,
          mfa_amr: [String.t()],
          provision: boolean(),
          allowed_hosts: [String.t()],
          redirect_uri: String.t(),
          worker: module()
        }
end
