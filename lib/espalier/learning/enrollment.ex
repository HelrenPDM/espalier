defmodule Espalier.Learning.Enrollment do
  @moduledoc """
  The enrollment of a user in a program with the chosen path (README
  section 7, domain rule 1). It stores the path and whether the learner
  chose it by hand, and never the self-assessment segment.

  The changeset casts `path` only. `program_id`, `started_at` and
  `path_chosen_manually` come from `Espalier.Learning` through
  `put_change/3`, and `user_id` from the scope.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.Program

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "enrollments" do
    field :path, Ecto.Enum, values: [:short, :full]
    field :path_chosen_manually, :boolean, default: false
    field :started_at, :utc_datetime
    belongs_to :program, Program
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(enrollment, attrs, user_scope) do
    enrollment
    |> cast(attrs, [:path])
    |> validate_required([:path])
    |> put_change(:user_id, user_scope.user.id)
    |> unique_constraint([:user_id, :program_id])
  end
end
