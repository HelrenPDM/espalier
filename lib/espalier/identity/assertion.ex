defmodule Espalier.Identity.Assertion do
  @moduledoc """
  The normalized claims of a validated ID token (task 0006, step 8).

  `issuer`, `tenant_id` and `subject` key the external identity
  (`Espalier.Accounts.ExternalIdentity.hash_input/3`); `subject` is `oid`
  for Entra ID and `sub` otherwise. `email` holds only a verified address,
  and it never finds or links an account (README section 6.2, rule 3).
  """

  defstruct [
    :provider_key,
    :issuer,
    :tenant_id,
    :subject,
    :display_name,
    :email,
    :amr,
    :auth_time,
    :sid,
    roles: []
  ]

  @type t :: %__MODULE__{
          provider_key: String.t(),
          issuer: String.t(),
          tenant_id: String.t() | nil,
          subject: String.t(),
          display_name: String.t() | nil,
          email: String.t() | nil,
          roles: [String.t()],
          amr: [String.t()] | nil,
          auth_time: integer() | nil,
          sid: String.t() | nil
        }
end
