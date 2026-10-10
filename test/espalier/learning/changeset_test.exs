defmodule Espalier.Learning.ChangesetTest do
  @moduledoc """
  The record changesets cast nothing (review of PR #24): `Espalier.Learning`
  sets every value on the struct, and the changeset only adds `user_id` from
  the scope, so no member of these rows is assignable from outside.
  """
  use ExUnit.Case, async: true

  alias Espalier.Accounts.{Scope, User}
  alias Espalier.Insights.ItemStat
  alias Espalier.Learning.{AssessmentAttempt, ItemResponse, ModuleCompletion}

  @scope %Scope{user: %User{id: "6f1d1e5c-0c43-4c0a-9a65-6f5b1f1b2d10"}, roles: [:learner]}

  test "the changesets take no attributes" do
    for schema <- [ItemResponse, AssessmentAttempt, ModuleCompletion] do
      Code.ensure_loaded!(schema)
      assert function_exported?(schema, :changeset, 2), inspect(schema)
      refute function_exported?(schema, :changeset, 3), inspect(schema)
    end

    refute function_exported?(ItemStat, :changeset, 2)
  end

  test "a struct without the server values is invalid, and user_id comes from the scope" do
    for {schema, required} <- [
          {ItemResponse, [:enrollment_id, :item_id, :attempt_no, :answered_on]},
          {AssessmentAttempt,
           [:enrollment_id, :assessment_id, :number, :wrong_count, :outcome, :submitted_at]},
          {ModuleCompletion, [:enrollment_id, :module_id, :completed_at]}
        ] do
      changeset = schema.changeset(struct(schema), @scope)
      refute changeset.valid?, inspect(schema)
      assert Enum.sort(Keyword.keys(changeset.errors)) == Enum.sort(required), inspect(schema)
      assert changeset.changes == %{user_id: @scope.user.id}
    end
  end

  test "values set on the struct pass, and the changeset changes nothing but user_id" do
    attempt = %AssessmentAttempt{
      enrollment_id: Ecto.UUID.generate(),
      assessment_id: Ecto.UUID.generate(),
      number: 1,
      wrong_count: 0,
      core_failed: false,
      outcome: :passed,
      submitted_at: DateTime.utc_now(:second)
    }

    changeset = AssessmentAttempt.changeset(attempt, @scope)
    assert changeset.valid?
    assert changeset.changes == %{user_id: @scope.user.id}
  end
end
