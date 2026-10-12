defmodule Espalier.Insights.SelfAssessmentResponse do
  @moduledoc """
  An anonymous answer of the self-assessment station (README section 7,
  domain rule 1, and section 10). The row carries no user key, a random
  primary key and only `recorded_on` with day precision. `org_unit` is
  filled only with `INSIGHTS_ORG_UNIT=true`. The enrollment stores the path
  and never the segment, so this row is the only place of the segment.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "self_assessment_responses" do
    field :segment_key, :string
    field :org_unit, :string
    field :recorded_on, :date
    field :program_id, :binary_id
  end

  @doc """
  Checks a row whose values `Espalier.Insights` has set on the struct. The
  changeset casts nothing, so no member can come from a request.
  """
  def changeset(%__MODULE__{} = self_assessment_response) do
    self_assessment_response
    |> change()
    |> validate_required([:program_id, :segment_key, :recorded_on])
  end
end
