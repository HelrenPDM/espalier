defmodule Espalier.Catalog.AssessmentItem do
  @moduledoc "Join schema of `assessment_items`: an item of an assessment at its position."
  use Ecto.Schema

  alias Espalier.Catalog.{Assessment, Item}

  @primary_key false
  @foreign_key_type :binary_id
  schema "assessment_items" do
    belongs_to :assessment, Assessment
    belongs_to :item, Item
    field :position, :integer
  end
end
