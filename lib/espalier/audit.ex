defmodule Espalier.Audit do
  @moduledoc """
  The trail of administrative actions in `audit_events`. Events are
  append-only: this context has no update or delete function apart from the
  retention job of task 0014.
  """

  import Ecto.Query

  alias Espalier.Accounts.Scope
  alias Espalier.Audit.AuditEvent
  alias Espalier.Repo

  @doc """
  Records `action` on `subject` by the actor of `scope` (`nil` for
  `Scope.system/0`). `details` holds role names, provider keys and counts.
  """
  def record(%Scope{} = scope, action, subject, details \\ %{}) when is_binary(action) do
    %AuditEvent{}
    |> AuditEvent.changeset(%{
      action: action,
      actor_id: actor_id(scope),
      subject_type: subject_type(subject),
      subject_id: subject_id(subject),
      details: details,
      at: DateTime.utc_now(:second)
    })
    |> Repo.insert()
  end

  @doc """
  Lists audit events, newest first. Requires the role `admin`.

  Filters: `:action`, `:subject_id`, `:limit` (default 100).
  """
  def list_events(%Scope{} = scope, filters \\ %{}) do
    if Scope.admin?(scope) do
      filters = Map.new(filters)

      events =
        AuditEvent
        |> filter(:action, filters[:action])
        |> filter(:subject_id, filters[:subject_id])
        |> order_by(desc: :at, desc: :inserted_at)
        |> limit(^Map.get(filters, :limit, 100))
        |> Repo.all()

      {:ok, events}
    else
      {:error, :forbidden}
    end
  end

  defp filter(query, _field, nil), do: query
  defp filter(query, field, value), do: where(query, [e], field(e, ^field) == ^value)

  defp actor_id(%Scope{system: true}), do: nil
  defp actor_id(%Scope{user: %{id: id}}), do: id
  defp actor_id(_scope), do: nil

  defp subject_type(nil), do: nil
  defp subject_type(%module{}), do: module |> Module.split() |> List.last()

  defp subject_id(%{id: id}), do: id
  defp subject_id(_subject), do: nil
end
