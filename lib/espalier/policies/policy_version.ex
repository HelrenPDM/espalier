defmodule Espalier.Policies.PolicyVersion do
  @moduledoc """
  A numbered version of a policy. A version without `published_at` is a
  draft; `Espalier.Policies.publish_version/2` sets `published_at`, and a
  published version is read-only. `requires_refresher` moves the credentials
  whose qualification requires the policy to `refresh_due` at publication
  (README section 7, domain rule 7).
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Espalier.Policies.Policy

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "policy_versions" do
    field :number, :integer
    field :body, :string
    field :effective_from, :date
    field :published_at, :utc_datetime
    field :requires_refresher, :boolean, default: false

    belongs_to :policy, Policy

    timestamps(type: :utc_datetime)
  end

  @doc """
  Casts the fields of a draft. `policy_id` and `published_at` come from
  `Espalier.Policies`.
  """
  def changeset(policy_version, attrs) do
    policy_version
    |> cast(attrs, [:number, :body, :effective_from, :requires_refresher])
    |> validate_required([:number, :body, :effective_from, :requires_refresher])
    |> validate_number(:number, greater_than: 0)
    |> unique_constraint([:policy_id, :number])
  end
end
