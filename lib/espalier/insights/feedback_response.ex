defmodule Espalier.Insights.FeedbackResponse do
  @moduledoc """
  The anonymous answers of the feedback station (README section 7, domain
  rule 12, and section 10). `answers` maps a question key of the station to
  an option key, a scale value from 1 to 5 or a free text. The row carries
  no user key, a random primary key and only `recorded_on` with day
  precision.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "feedback_responses" do
    field :answers, :map
    field :recorded_on, :date
    field :program_id, :binary_id
  end

  @doc """
  Checks a row whose values `Espalier.Insights` has set on the struct. The
  changeset casts nothing, so no member can come from a request.
  """
  def changeset(%__MODULE__{} = feedback_response) do
    feedback_response
    |> change()
    |> validate_required([:program_id, :answers, :recorded_on])
  end
end
