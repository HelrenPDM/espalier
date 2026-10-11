defmodule Espalier.Credentials.AttendanceCertificate do
  @moduledoc """
  The certificate that a user attended a session of a companion format held
  outside the platform (README section 7, domain rule 11). A facilitator
  issues it, and the row belongs to the learner in `user_id`. `issued_by_id`
  becomes `nil` when the facilitator's account is deleted.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Catalog.CompanionFormat

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "attendance_certificates" do
    field :held_on, :date
    belongs_to :companion_format, CompanionFormat
    field :issued_by_id, :binary_id
    field :user_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc """
  Checks a row whose values `Espalier.Credentials` has set on the struct.
  The changeset casts nothing; it puts `user_id` from the scope of the
  learner, which `Espalier.Accounts.Scope.for_user/1` builds, and declares
  the unique constraint.
  """
  def changeset(%__MODULE__{} = attendance_certificate, user_scope) do
    attendance_certificate
    |> change(user_id: user_scope.user.id)
    |> validate_required([:companion_format_id, :held_on])
    |> unique_constraint([:user_id, :companion_format_id, :held_on],
      name: :attendance_certificates_user_format_day_index
    )
  end
end
