defmodule Espalier.Insights.InterestVote do
  @moduledoc """
  An anonymous "would use" vote for a companion format (README section 7,
  domain rule 11, and section 10). The row carries no user key, a random
  primary key and only `recorded_on` with day precision.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "interest_votes" do
    field :choice, Ecto.Enum, values: [:would_use]
    field :recorded_on, :date
    field :companion_format_id, :binary_id
  end

  @doc """
  Checks a row whose values `Espalier.Insights` has set on the struct. The
  changeset casts nothing, so no member can come from a request.
  """
  def changeset(%__MODULE__{} = interest_vote) do
    interest_vote
    |> change()
    |> validate_required([:companion_format_id, :choice, :recorded_on])
  end
end
