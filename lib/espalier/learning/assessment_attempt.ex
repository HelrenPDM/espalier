defmodule Espalier.Learning.AssessmentAttempt do
  @moduledoc """
  An exam attempt with its outcome under the pass rule (README section 7,
  domain rule 5). It holds no answers and no result per item.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Assessment
  alias Espalier.Learning.Enrollment

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "assessment_attempts" do
    field :number, :integer
    field :wrong_count, :integer
    field :core_failed, :boolean, default: false
    field :outcome, Ecto.Enum, values: [:passed, :failed_core, :failed_errors]
    field :submitted_at, :utc_datetime
    belongs_to :enrollment, Enrollment
    belongs_to :assessment, Assessment
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @fields [
    :enrollment_id,
    :assessment_id,
    :number,
    :wrong_count,
    :core_failed,
    :outcome,
    :submitted_at
  ]

  @doc """
  Builds the row from values that `Espalier.Learning` computes; no member
  comes from a request.
  """
  def changeset(assessment_attempt, attrs, user_scope) do
    assessment_attempt
    |> cast(attrs, @fields)
    |> validate_required(@fields)
    |> put_change(:user_id, user_scope.user.id)
    |> unique_constraint([:enrollment_id, :assessment_id, :number])
  end
end
