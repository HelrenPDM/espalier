defmodule Espalier.Learning.ApplyDefaultPathTest do
  @moduledoc """
  `Espalier.Learning.apply_default_path/3` of task 0014 (spec steps 4 and
  13, README section 7, domain rule 1): without an enrollment it creates
  one on the segment's default path with `started_at` set and
  `path_chosen_manually` false; an enrollment whose path the learner has
  not chosen by hand takes the new path; a manual choice keeps priority;
  and an equal path leaves the row untouched.
  """
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Learning
  alias Espalier.Learning.Enrollment

  setup do
    program = publish_demo!()
    %{program: program, scope: scope_for(user_fixture())}
  end

  # Moves `updated_at` and `started_at` of the enrollment one hour into the
  # past, so that a test can tell whether a later call wrote the row.
  defp backdate!(%Enrollment{id: id}) do
    past = DateTime.add(DateTime.utc_now(:second), -3600, :second)

    {1, _} =
      Repo.update_all(from(e in Enrollment, where: e.id == ^id),
        set: [updated_at: past, started_at: past]
      )

    Repo.get!(Enrollment, id)
  end

  defp enrollments(scope), do: Repo.all(from e in Enrollment, where: e.user_id == ^scope.user.id)

  test "without an enrollment, creates one on the path with started_at set",
       %{program: program, scope: scope} do
    before = DateTime.utc_now(:second)

    assert {:ok, %Enrollment{} = enrollment} = Learning.apply_default_path(scope, program, :full)

    assert enrollment.path == :full
    refute enrollment.path_chosen_manually
    assert enrollment.user_id == scope.user.id
    assert enrollment.program_id == program.id
    assert %DateTime{} = enrollment.started_at
    refute DateTime.before?(enrollment.started_at, before)

    assert [stored] = enrollments(scope)
    assert stored.id == enrollment.id
    assert stored.path == :full
    refute stored.path_chosen_manually
  end

  test "an enrollment with path_chosen_manually false takes the new path",
       %{program: program, scope: scope} do
    enrollment = scope |> enroll!("short") |> backdate!()
    refute enrollment.path_chosen_manually

    assert {:ok, updated} = Learning.apply_default_path(scope, program, :full)

    assert updated.id == enrollment.id
    assert updated.path == :full
    refute updated.path_chosen_manually
    assert updated.started_at == enrollment.started_at

    stored = Repo.get!(Enrollment, enrollment.id)
    assert stored.path == :full
    assert DateTime.after?(stored.updated_at, enrollment.updated_at)
    assert [_one] = enrollments(scope)
  end

  test "an enrollment with path_chosen_manually true keeps its path",
       %{program: program, scope: scope} do
    enrollment = enroll!(scope, "short")
    {:ok, manual} = Learning.update_path(scope, enrollment.id, "full")
    manual = backdate!(manual)
    assert manual.path_chosen_manually

    assert {:ok, kept} = Learning.apply_default_path(scope, program, :short)

    assert kept.id == enrollment.id
    assert kept.path == :full
    assert kept.path_chosen_manually
    assert Repo.get!(Enrollment, enrollment.id) == manual
  end

  test "an equal path leaves the enrollment unchanged", %{program: program, scope: scope} do
    enrollment = scope |> enroll!("full") |> backdate!()

    assert {:ok, same} = Learning.apply_default_path(scope, program, :full)

    assert same == enrollment
    assert Repo.get!(Enrollment, enrollment.id) == enrollment
  end

  test "touches only the enrollment of the scope user", %{program: program, scope: scope} do
    other = scope_for(user_fixture())
    others = other |> enroll!("short") |> backdate!()

    assert {:ok, own} = Learning.apply_default_path(scope, program, :full)

    refute own.id == others.id
    assert Repo.get!(Enrollment, others.id) == others
    assert [_one] = enrollments(scope)
  end
end
