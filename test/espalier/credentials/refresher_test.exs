defmodule Espalier.Credentials.RefresherTest do
  @moduledoc """
  The refresher of task 0013 (spec step 24, bullet "Refresher", with steps
  10 and 11 and README section 7, domain rule 7) on the demo qualification
  `basics`. For each refresher mode, a record dated before or at
  `refresh_due_at` restores nothing, and a record after it restores
  `active` with a new `valid_until` counted from the restore date, keeps
  `unlocks_snapshot`, clears `refresh_due_at` and enqueues
  `credential.issued` again. `update_unit` counts the module flagged
  `refresher_unit`, `full_run` every requirement and `test_only` the exam;
  under `full_run` an attendance counts from the date of `refresh_due_at`
  on. An expired credential returns in the same way. A qualification
  without refresher mode returns to `active` once every requirement holds
  again, which after a policy version that requires a refresher means the
  acknowledgement of that version.
  """
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Accounts.Scope
  alias Espalier.Catalog.{Qualification, Requirement}
  alias Espalier.Credentials
  alias Espalier.Credentials.{Credential, WebhookWorker}
  alias Espalier.{Learning, Policies}
  alias Espalier.Learning.AssessmentAttempt

  setup do
    program = publish_demo!()
    scope = scope_for(user_fixture())
    credential = qualify_basics!(scope, program)

    now = DateTime.utc_now(:second)
    due_at = DateTime.add(now, -1, :hour)
    before = DateTime.add(due_at, -1, :day)
    old_valid_until = Date.add(Date.utc_today(), 10)

    set_completed_at!(scope.user, program, 1, before)
    set_completed_at!(scope.user, program, 2, before)
    set_submitted_at!(scope.user, before)

    credential =
      put_credential!(credential,
        status: :refresh_due,
        refresh_due_at: due_at,
        issued_at: DateTime.add(now, -355, :day),
        valid_until: old_valid_until
      )

    # A later pack version changes the unlocked tasks; the credential keeps
    # what it permitted at issue time.
    {1, _rows} =
      Repo.update_all(
        from(q in Qualification, where: q.id == ^credential.qualification_id),
        set: [unlocks: ["A task that a later pack version names"]]
      )

    # Subscribed after the issue, so that only restores enqueue jobs.
    webhook = webhook_fixture(%{events: ["credential.issued"]})

    %{
      program: program,
      scope: scope,
      credential: credential,
      due_at: due_at,
      webhook: webhook
    }
  end

  defp set_submitted_at!(user, %DateTime{} = at) do
    {count, _rows} =
      Repo.update_all(from(a in AssessmentAttempt, where: a.user_id == ^user.id),
        set: [submitted_at: at]
      )

    true = count > 0
    :ok
  end

  defp set_mode!(credential, mode) do
    {1, _rows} =
      Repo.update_all(
        from(q in Qualification, where: q.id == ^credential.qualification_id),
        set: [refresher_mode: mode]
      )

    :ok
  end

  defp pass_exam!(scope, program) do
    exam = assessment!(program, "module-1-exam")
    answers = Map.new(exam_answers(exam), fn {id, answer} -> {id, cast_answer(answer)} end)
    {:ok, %{outcome: :passed}, _results} = Learning.submit_attempt(scope, exam.id, answers)
    :ok
  end

  defp complete!(scope, program, number) do
    {:ok, _completion} = Learning.complete_module(scope, module!(program, number).id)
    :ok
  end

  defp current(%{credential: credential}), do: Repo.get!(Credential, credential.id)

  defp assert_not_restored(%{credential: credential} = context) do
    stored = current(context)
    assert stored.status == credential.status
    assert stored.refresh_due_at == credential.refresh_due_at
    assert stored.valid_until == credential.valid_until
    assert all_enqueued(worker: WebhookWorker) == []
  end

  defp assert_restored(%{credential: credential, webhook: webhook} = context) do
    stored = current(context)
    assert stored.id == credential.id
    assert stored.status == :active
    assert stored.refresh_due_at == nil
    assert stored.valid_until == Date.shift(Date.utc_today(), month: 12)
    assert stored.unlocks_snapshot == credential.unlocks_snapshot
    refute stored.unlocks_snapshot == Repo.get!(Qualification, stored.qualification_id).unlocks

    assert [job] = all_enqueued(worker: WebhookWorker)

    assert job.args["webhook_id"] == webhook.id
    assert job.args["event"] == "credential.issued"
    assert job.args["credential_id"] == credential.id
  end

  describe "update_unit" do
    test "a completion of the refresher unit dated before or at refresh_due_at restores nothing",
         %{program: program, scope: scope, due_at: due_at} = context do
      assert Repo.get!(Qualification, context.credential.qualification_id).refresher_mode ==
               :update_unit

      assert module!(program, 2).refresher_unit

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert_not_restored(context)

      set_completed_at!(scope.user, program, 2, due_at)
      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert_not_restored(context)
    end

    test "a completion of another module after refresh_due_at restores nothing",
         %{program: program, scope: scope} = context do
      complete!(scope, program, 1)
      assert_not_restored(context)
    end

    test "a completion of the refresher unit after refresh_due_at restores active",
         %{program: program, scope: scope} = context do
      complete!(scope, program, 2)
      assert_restored(context)
    end

    test "an expired credential is restored as well",
         %{program: program, scope: scope, credential: credential} = context do
      credential =
        put_credential!(credential,
          status: :expired,
          valid_until: Date.add(Date.utc_today(), -40)
        )

      context = %{context | credential: credential}
      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert_not_restored(context)

      complete!(scope, program, 2)
      assert_restored(context)
    end
  end

  describe "full_run" do
    setup %{credential: credential} do
      set_mode!(credential, :full_run)
    end

    test "records dated before refresh_due_at restore nothing",
         %{program: program, scope: scope} = context do
      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert_not_restored(context)
    end

    test "new module completions without a new passed exam restore nothing",
         %{program: program, scope: scope} = context do
      complete!(scope, program, 1)
      complete!(scope, program, 2)
      assert_not_restored(context)
    end

    test "every requirement met again after refresh_due_at restores active",
         %{program: program, scope: scope} = context do
      complete!(scope, program, 1)
      complete!(scope, program, 2)
      pass_exam!(scope, program)
      assert_restored(context)
    end

    test "a new passed exam restores nothing until each module is completed again",
         %{program: program, scope: scope} = context do
      pass_exam!(scope, program)
      assert_not_restored(context)

      # Module 2 still carries its completion from before refresh_due_at.
      complete!(scope, program, 1)
      assert_not_restored(context)

      complete!(scope, program, 2)
      assert_restored(context)
    end

    test "a new policy version needs its acknowledgement before the restore",
         %{program: program, scope: scope} = context do
      newer = published_version_fixture(Policies.get_policy_by_key("usage-policy"))
      complete!(scope, program, 1)
      complete!(scope, program, 2)
      pass_exam!(scope, program)
      assert_not_restored(context)

      {:ok, _acknowledgement} = Policies.acknowledge(scope, newer)
      assert_restored(context)
    end
  end

  describe "full_run with an attendance requirement" do
    # The add-on workshop requires basics and the attendance of the format
    # workshop. Basics stays in force; the workshop credential is due.
    setup %{program: program, scope: scope, credential: basics} do
      put_credential!(basics, status: :active, refresh_due_at: nil)
      workshop = qualification!(program, "workshop")

      {1, _rows} =
        Repo.update_all(from(q in Qualification, where: q.id == ^workshop.id),
          set: [
            refresher_mode: :full_run,
            validity_kind: :months,
            validity_months: 12,
            unlocks: ["A task that a later pack version names"]
          ]
        )

      credential =
        credential_fixture(scope.user, workshop,
          status: :refresh_due,
          refresh_due_at: ~U[2026-05-04 15:00:00Z],
          issued_at: ~U[2025-06-03 09:00:00Z],
          valid_until: ~D[2026-06-03]
        )

      %{credential: credential, format: format!(program, "workshop")}
    end

    test "a certificate held before the date of refresh_due_at restores nothing, one held on that date restores active",
         %{program: program, scope: scope, credential: credential, format: format} = context do
      due_on = DateTime.to_date(credential.refresh_due_at)

      certificate_fixture(scope.user, format, Date.add(due_on, -1))
      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert_not_restored(context)

      certificate_fixture(scope.user, format, due_on)
      assert {:ok, [_restored]} = Credentials.evaluate(scope, program)
      assert_restored(context)
    end
  end

  describe "test_only" do
    setup %{credential: credential} do
      set_mode!(credential, :test_only)
    end

    test "a passed exam dated before refresh_due_at restores nothing",
         %{program: program, scope: scope} = context do
      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert_not_restored(context)
    end

    test "module completions after refresh_due_at restore nothing",
         %{program: program, scope: scope} = context do
      complete!(scope, program, 1)
      complete!(scope, program, 2)
      assert_not_restored(context)
    end

    test "a passed exam after refresh_due_at restores active",
         %{program: program, scope: scope} = context do
      pass_exam!(scope, program)
      assert_restored(context)
    end
  end

  describe "after a policy version that requires a refresher" do
    test "the refresher unit restores the credential that the publication moved",
         %{program: program, scope: scope, credential: credential} = context do
      credential = put_credential!(credential, status: :active, refresh_due_at: nil)
      current = Policies.current_version("usage-policy")
      draft = draft_version_fixture(current.policy, %{requires_refresher: true})
      {:ok, _published} = Policies.publish_version(Scope.system(), draft)

      assert %{status: :refresh_due, refresh_due_at: %DateTime{}} = moved = current(context)

      # Timestamps carry seconds only; the completion must be later.
      moved =
        put_credential!(moved, refresh_due_at: DateTime.add(moved.refresh_due_at, -1, :hour))

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert_not_restored(%{context | credential: moved})

      complete!(scope, program, 2)
      assert_restored(%{context | credential: credential})
    end

    test "a qualification without refresher mode returns to active once the new version is acknowledged",
         %{program: program, scope: scope, webhook: webhook} do
      workshop = qualification!(program, "workshop")
      assert {workshop.validity_kind, workshop.refresher_mode} == {:none, nil}

      Repo.insert!(%Requirement{
        qualification_id: workshop.id,
        kind: :policy_acknowledged,
        target_key: "usage-policy"
      })

      certificate_fixture(scope.user, format!(program, "workshop"))
      credential = credential_fixture(scope.user, workshop)

      current = Policies.current_version("usage-policy")
      draft = draft_version_fixture(current.policy, %{requires_refresher: true})
      {:ok, newer} = Policies.publish_version(Scope.system(), draft)

      assert %Credential{status: :refresh_due, refresh_due_at: %DateTime{}} =
               Repo.get!(Credential, credential.id)

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert %Credential{status: :refresh_due} = Repo.get!(Credential, credential.id)
      assert all_enqueued(worker: WebhookWorker) == []

      {:ok, _acknowledgement} = Policies.acknowledge(scope, newer)

      restored = Repo.get!(Credential, credential.id)
      assert restored.status == :active
      assert restored.valid_until == nil
      assert restored.refresh_due_at == nil

      assert [job] = all_enqueued(worker: WebhookWorker)

      assert job.args["webhook_id"] == webhook.id
      assert job.args["event"] == "credential.issued"
      assert job.args["credential_id"] == credential.id
    end
  end
end
