defmodule Espalier.Identity.Ldap.Entry do
  @moduledoc """
  The directory entry of a person after the search on connection 1
  (task 0007, step 9). `subject` is the `objectGUID` (Active Directory) or
  `entryUUID` (generic LDAP) as a lower-case UUID, and `groups` lists the
  mapped group DNs that the person belongs to. `Inspect` shows only the
  groups, because the other fields are personal data.
  """

  @derive {Inspect, only: [:groups]}
  defstruct [:dn, :subject, :login, :upn, :email, :display_name, :org_unit, groups: []]

  @type t :: %__MODULE__{
          dn: String.t(),
          subject: String.t(),
          login: String.t() | nil,
          upn: String.t() | nil,
          email: String.t() | nil,
          display_name: String.t() | nil,
          org_unit: String.t() | nil,
          groups: [String.t()]
        }
end
