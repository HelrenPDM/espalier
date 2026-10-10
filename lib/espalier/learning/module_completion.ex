defmodule Espalier.Learning.ModuleCompletion do
  @moduledoc """
  The completion of a module by an enrollment. It exists only after every
  exam of the module that counts for a credential has a passed attempt.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Learning.Enrollment

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "module_completions" do
    field :completed_at, :utc_datetime
    belongs_to :enrollment, Enrollment
    belongs_to :module, CatalogModule
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Builds the row from values that `Espalier.Learning` computes; no member
  comes from a request.
  """
  def changeset(module_completion, attrs, user_scope) do
    module_completion
    |> cast(attrs, [:enrollment_id, :module_id, :completed_at])
    |> validate_required([:enrollment_id, :module_id, :completed_at])
    |> put_change(:user_id, user_scope.user.id)
    |> unique_constraint([:enrollment_id, :module_id])
  end
end
