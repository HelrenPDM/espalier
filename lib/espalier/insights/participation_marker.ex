defmodule Espalier.Insights.ParticipationMarker do
  @moduledoc """
  Records with the user id that a person has answered a self-assessment
  (`subject_id`: the program id), a format vote (the companion format id)
  or the feedback (the program id), without a timestamp (README section
  10). It answers "has this person answered" for
  `Espalier.Insights.record_once/3` and for the person's own
  `GET /api/me/participation`: no query joins it with the anonymous
  tables, no report reads it, and no role of the application reads the
  markers of another person.

  A self-assessment marker and a feedback marker hold no answer. A format
  vote has the single choice `would_use`, so a format-vote marker
  (`user_id`, `format_vote`, format id) states with the person's id what
  the anonymous `interest_votes` row states without it: that this person
  would use this format. A reader of `participation_markers` in the
  database, the write-ahead log or a backup learns the vote, and a
  data-subject export that includes the markers includes the vote as the
  person's data. The GDPR workstream documents this limit (README section
  10).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @subject_types [:self_assessment, :format_vote, :feedback]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "participation_markers" do
    field :subject_type, Ecto.Enum, values: @subject_types
    field :subject_id, Ecto.UUID
    field :user_id, :binary_id
  end

  @doc "The subject types of a marker."
  def subject_types, do: @subject_types

  @doc false
  def changeset(participation_marker, attrs, user_scope) do
    participation_marker
    |> cast(attrs, [:subject_type, :subject_id])
    |> validate_required([:subject_type, :subject_id])
    |> put_change(:user_id, user_scope.user.id)
    |> unique_constraint([:user_id, :subject_type, :subject_id])
  end
end
