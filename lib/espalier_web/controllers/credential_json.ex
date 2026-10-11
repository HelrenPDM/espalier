defmodule EspalierWeb.CredentialJSON do
  @moduledoc """
  Views of the Credentials context (task 0013). Every view names its
  members explicitly; a credential carries no score, percentage or rank
  (README principle 2), and the integration view carries qualification
  code, status, unlocked tasks and validity only (ASVS 15.3.1).
  """

  alias Espalier.Credentials.Credential

  @doc "Renders the credentials of the signed-in user."
  def index(%{credentials: credentials, holder: holder}) do
    %{credentials: Enum.map(credentials, &credential(&1, holder))}
  end

  @doc "Renders one credential of the signed-in user."
  def show(%{credential: credential, holder: holder}), do: credential(credential, holder)

  defp credential(%Credential{qualification: qualification} = credential, holder) do
    %{
      id: credential.id,
      qualification_code: qualification.code,
      qualification_title: qualification.title,
      locale: qualification.program.locale,
      holder_display_name: holder.display_name,
      status: credential.status,
      issued_at: credential.issued_at,
      valid_until: credential.valid_until,
      unlocks_snapshot: credential.unlocks_snapshot
    }
  end

  @doc "Renders the requirements per qualification."
  def requirements(%{entries: entries}) do
    %{
      qualifications:
        Enum.map(entries, fn entry ->
          qualification = entry.qualification

          %{
            code: qualification.code,
            title: qualification.title,
            add_on: qualification.add_on,
            unlocks: qualification.unlocks,
            credential: credential_state(entry.credential),
            met: entry.met,
            open: entry.open
          }
        end)
    }
  end

  defp credential_state(nil), do: nil

  defp credential_state(%Credential{} = credential) do
    %{
      id: credential.id,
      status: credential.status,
      issued_at: credential.issued_at,
      valid_until: credential.valid_until
    }
  end

  @doc "Renders the results of an attendance request."
  def attendance(%{results: results}), do: %{results: results}

  @doc "Renders a user of the facilitator lookup."
  def user(%{user: user}) do
    %{id: user.id, display_name: user.display_name, org_unit: user.org_unit}
  end

  @doc "Renders the registrar list."
  def registrar(%{rows: rows}), do: %{credentials: rows}

  @doc "Renders the credentials in force for the integration API."
  def lookup(%{credentials: credentials}), do: %{credentials: credentials}
end
