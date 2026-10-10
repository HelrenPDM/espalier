defmodule Espalier.Learning.ItemResponse do
  @moduledoc """
  The correctness of one practice answer, stored only with
  `TRACKING_DETAIL=standard` (README section 10). It holds no answer and no
  time beyond `answered_on`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Item
  alias Espalier.Learning.Enrollment

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "item_responses" do
    field :correct, :boolean, default: false
    field :attempt_no, :integer
    field :answered_on, :date
    belongs_to :enrollment, Enrollment
    belongs_to :item, Item
    field :user_id, :binary_id
  end

  @doc """
  Checks a row whose values `Espalier.Learning` has set on the struct. The
  changeset casts nothing, so no member can come from a request; it puts
  `user_id` from the scope and declares the unique constraint.
  """
  def changeset(%__MODULE__{} = item_response, user_scope) do
    item_response
    |> change(user_id: user_scope.user.id)
    |> validate_required([:enrollment_id, :item_id, :correct, :attempt_no, :answered_on])
    |> unique_constraint([:enrollment_id, :item_id, :attempt_no])
  end
end
