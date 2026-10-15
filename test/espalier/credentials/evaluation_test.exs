defmodule Espalier.Credentials.EvaluationTest do
  @moduledoc """
  Requirement evaluation of task 0013 (spec step 24, bullet "Evaluation",
  with step 10 and README section 7, domain rule 6) on the demo
  qualifications `basics` and `workshop`: each requirement kind is open
  until its record exists and met afterwards, `policy_acknowledged` counts
  only the current version, a certificate counts only for a format with
  `attendance_counts`, the last missing requirement issues the credential
  with `unlocks_snapshot` and `valid_until` from the qualification, an
  add-on needs its prerequisite in force and follows it in the same call,
  also when `qualifications.yaml` lists it first, a revoked credential
  blocks a new issue, another program issues nothing
  for the demo program, and each issue enqueues `credential.issued` once
  per subscribed active webhook.
  """
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Accounts.Scope
  alias Espalier.Catalog.Pack.{Importer, Publisher}
  alias Espalier.Catalog.{PackImport, Program, Requirement}
  alias Espalier.Credentials
  alias Espalier.Credentials.{Credential, WebhookWorker}
  alias Espalier.{Learning, PackFixtures, Policies}
  alias Espalier.Policies.Acknowledgement

  @basics_requirements Enum.sort([
                         {:module_completed, "1"},
                         {:module_completed, "2"},
                         {:assessment_passed, "module-1-exam"},
                         {:policy_acknowledged, "usage-policy"}
                       ])
  @workshop_requirements Enum.sort([{:qualification_held, "basics"}, {:attendance, "workshop"}])

  setup do
    program = publish_demo!()
    %{program: program, scope: scope_for(user_fixture())}
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

  # Every requirement of basics except the acknowledgement; each step runs
  # the evaluation of the Learning context.
  defp basics_but_policy!(scope, program) do
    enroll!(scope)
    pass_exam!(scope, program)
    complete!(scope, program, 1)
    complete!(scope, program, 2)
  end

  # Inserts an acknowledgement without the evaluation of acknowledge/2.
  defp acknowledge_quietly!(user, version) do
    Repo.insert!(%Acknowledgement{
      user_id: user.id,
      policy_version_id: version.id,
      acknowledged_at: DateTime.utc_now(:second)
    })
  end

  defp requirement_state(scope, code) do
    {:ok, entries} = Credentials.requirements(scope, demo_slug())
    entry = Enum.find(entries, &(&1.qualification.code == code))
    %{met: keys(entry.met), open: keys(entry.open)}
  end

  defp keys(requirements), do: requirements |> Enum.map(&{&1.kind, &1.target_key}) |> Enum.sort()

  defp hours_ago(hours), do: DateTime.add(DateTime.utc_now(:second), -hours, :hour)

  defp publish_minimal_pack! do
    path = PackFixtures.copy_pack!("minimal")
    {:ok, %PackImport{status: :validated} = pack_import} = Importer.import(path, nil)
    {:ok, %PackImport{status: :published}} = Publisher.publish(pack_import)
    Repo.get_by!(Program, slug: "minimal-pack")
  end

  describe "requirement kinds" do
    test "each kind is open until its record exists and met afterwards",
         %{program: program, scope: scope} do
      version = published_policy!("usage-policy")
      enroll!(scope)

      assert requirement_state(scope, "basics") == %{met: [], open: @basics_requirements}
      assert requirement_state(scope, "workshop") == %{met: [], open: @workshop_requirements}

      pass_exam!(scope, program)
      assert {:assessment_passed, "module-1-exam"} in requirement_state(scope, "basics").met

      complete!(scope, program, 1)
      assert {:module_completed, "1"} in requirement_state(scope, "basics").met

      complete!(scope, program, 2)
      assert {:module_completed, "2"} in requirement_state(scope, "basics").met
      assert requirement_state(scope, "basics").open == [{:policy_acknowledged, "usage-policy"}]
      assert credential_for(scope.user, program, "basics") == nil

      {:ok, _acknowledgement} = Policies.acknowledge(scope, version)
      assert requirement_state(scope, "basics") == %{met: @basics_requirements, open: []}
      assert %Credential{status: :active} = credential_for(scope.user, program, "basics")

      assert requirement_state(scope, "workshop") == %{
               met: [{:qualification_held, "basics"}],
               open: [{:attendance, "workshop"}]
             }

      certificate_fixture(scope.user, format!(program, "workshop"))
      assert requirement_state(scope, "workshop") == %{met: @workshop_requirements, open: []}
    end

    test "policy_acknowledged counts only the current version of the policy",
         %{program: program, scope: scope} do
      policy = policy_fixture(%{key: "usage-policy"})
      older = published_version_fixture(policy)
      basics_but_policy!(scope, program)
      current = published_version_fixture(policy)
      _draft = draft_version_fixture(policy)

      {:ok, _acknowledgement} = Policies.acknowledge(scope, older)

      assert requirement_state(scope, "basics").open == [{:policy_acknowledged, "usage-policy"}]
      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert credential_for(scope.user, program, "basics") == nil

      {:ok, _acknowledgement} = Policies.acknowledge(scope, current)
      assert %Credential{status: :active} = credential_for(scope.user, program, "basics")
    end

    test "a policy without a published version leaves the requirement open",
         %{program: program, scope: scope} do
      policy = policy_fixture(%{key: "usage-policy"})
      draft = draft_version_fixture(policy)
      basics_but_policy!(scope, program)
      acknowledge_quietly!(scope.user, draft)

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert requirement_state(scope, "basics").open == [{:policy_acknowledged, "usage-policy"}]
    end

    test "a certificate for a format without attendance_counts satisfies no requirement",
         %{program: program, scope: scope} do
      qualify_basics!(scope, program)
      workshop = qualification!(program, "workshop")
      help_desk = format!(program, "help-desk")
      refute help_desk.attendance_counts

      {1, _rows} =
        Repo.update_all(
          from(r in Requirement,
            where: r.qualification_id == ^workshop.id and r.kind == :attendance
          ),
          set: [target_key: "help-desk"]
        )

      certificate_fixture(scope.user, help_desk)

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert requirement_state(scope, "workshop").open == [{:attendance, "help-desk"}]
      assert credential_for(scope.user, program, "workshop") == nil
    end

    test "a certificate of another user satisfies no requirement",
         %{program: program, scope: scope} do
      qualify_basics!(scope, program)
      certificate_fixture(user_fixture(), format!(program, "workshop"))

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert requirement_state(scope, "workshop").open == [{:attendance, "workshop"}]
    end
  end

  describe "issue" do
    test "the last missing requirement issues basics with its unlocks and twelve months of validity",
         %{program: program, scope: scope} do
      qualification = qualification!(program, "basics")
      assert {qualification.validity_kind, qualification.validity_months} == {:months, 12}

      enroll!(scope)
      {:ok, _acknowledgement} = Policies.acknowledge(scope, published_policy!("usage-policy"))
      pass_exam!(scope, program)
      complete!(scope, program, 2)
      assert credential_for(scope.user, program, "basics") == nil

      complete!(scope, program, 1)

      assert %Credential{status: :active, refresh_due_at: nil} =
               credential = credential_for(scope.user, program, "basics")

      assert credential.unlocks_snapshot == qualification.unlocks
      assert length(credential.unlocks_snapshot) == 2
      assert DateTime.diff(DateTime.utc_now(:second), credential.issued_at) in 0..60

      assert credential.valid_until ==
               Date.shift(DateTime.to_date(credential.issued_at), month: 12)
    end

    test "workshop of validity_kind none is issued without valid_until",
         %{program: program, scope: scope} do
      qualification = qualification!(program, "workshop")
      assert qualification.validity_kind == :none

      qualify_basics!(scope, program)
      certificate_fixture(scope.user, format!(program, "workshop"))

      assert {:ok, [%Credential{} = credential]} = Credentials.evaluate(scope, program)
      assert credential.qualification_id == qualification.id
      assert credential.status == :active
      assert credential.valid_until == nil
      assert credential.unlocks_snapshot == qualification.unlocks
    end

    test "an add-on is not issued while its prerequisite qualification is missing",
         %{program: program, scope: scope} do
      enroll!(scope)
      certificate_fixture(scope.user, format!(program, "workshop"))

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert credential_for(scope.user, program, "workshop") == nil
      assert requirement_state(scope, "workshop").open == [{:qualification_held, "basics"}]
    end

    test "an add-on is issued while its prerequisite is refresh_due",
         %{program: program, scope: scope} do
      basics = qualify_basics!(scope, program)
      set_completed_at!(scope.user, program, 2, hours_ago(48))
      put_credential!(basics, status: :refresh_due, refresh_due_at: hours_ago(1))
      certificate_fixture(scope.user, format!(program, "workshop"))

      assert {:ok, [%Credential{} = workshop]} = Credentials.evaluate(scope, program)
      assert workshop.qualification_id == qualification!(program, "workshop").id
      assert credential_for(scope.user, program, "basics").status == :refresh_due
    end

    test "an add-on is not issued while its prerequisite is expired",
         %{program: program, scope: scope} do
      basics = qualify_basics!(scope, program)
      set_completed_at!(scope.user, program, 2, hours_ago(48))
      put_credential!(basics, status: :expired, refresh_due_at: hours_ago(1))
      certificate_fixture(scope.user, format!(program, "workshop"))

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert credential_for(scope.user, program, "workshop") == nil
    end

    test "an add-on is issued in the same evaluation as its prerequisite",
         %{program: program, scope: scope} do
      version = published_policy!("usage-policy")
      certificate_fixture(scope.user, format!(program, "workshop"))
      basics_but_policy!(scope, program)
      acknowledge_quietly!(scope.user, version)

      assert {:ok, changed} = Credentials.evaluate(scope, program)

      assert changed |> Enum.map(& &1.qualification_id) |> Enum.sort() ==
               Enum.sort([
                 qualification!(program, "basics").id,
                 qualification!(program, "workshop").id
               ])

      assert Enum.all?(changed, &(&1.status == :active))
      assert {:ok, []} = Credentials.evaluate(scope, program)
    end

    test "an add-on listed before its prerequisite is issued in the same evaluation as well",
         %{scope: scope} do
      # The demo pack again with workshop first in qualifications.yaml, so
      # the evaluation reaches the add-on before basics.
      pack = PackFixtures.copy_pack!(PackFixtures.demo_path())
      PackFixtures.update_yaml!(pack, "qualifications.yaml", &Enum.reverse/1)
      program = publish_demo!(pack)
      workshop = qualification!(program, "workshop")
      basics = qualification!(program, "basics")
      assert {workshop.position, basics.position} == {1, 2}

      version = published_policy!("usage-policy")
      certificate_fixture(scope.user, format!(program, "workshop"))
      basics_but_policy!(scope, program)
      acknowledge_quietly!(scope.user, version)

      assert {:ok, changed} = Credentials.evaluate(scope, program)

      assert changed |> Enum.map(& &1.qualification_id) |> Enum.sort() ==
               Enum.sort([basics.id, workshop.id])

      assert Enum.all?(changed, &(&1.status == :active))
      assert {:ok, []} = Credentials.evaluate(scope, program)
    end

    test "a revoked credential blocks a new issue", %{program: program, scope: scope} do
      credential = qualify_basics!(scope, program)
      {:ok, _revoked} = Credentials.revoke(Scope.system(), credential)

      assert {:ok, []} = Credentials.evaluate(scope, program)
      complete!(scope, program, 2)

      assert [%Credential{status: :revoked} = revoked] =
               Repo.all(from c in Credential, where: c.user_id == ^scope.user.id)

      assert revoked.id == credential.id
    end

    test "a revoked prerequisite blocks its add-on", %{program: program, scope: scope} do
      credential = qualify_basics!(scope, program)
      {:ok, _revoked} = Credentials.revoke(Scope.system(), credential)
      certificate_fixture(scope.user, format!(program, "workshop"))

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert credential_for(scope.user, program, "workshop") == nil
    end

    test "evaluate of an unpublished or another program issues nothing for this one",
         %{program: program, scope: scope} do
      version = published_policy!("usage-policy")
      basics_but_policy!(scope, program)
      acknowledge_quietly!(scope.user, version)

      draft =
        Repo.insert!(%Program{
          slug: "draft-program",
          title: "A draft program",
          locale: "en",
          status: :draft,
          pack_version: "0.1.0"
        })

      other = publish_minimal_pack!()

      assert {:ok, []} = Credentials.evaluate(scope, draft)
      assert {:ok, []} = Credentials.evaluate(scope, other)
      assert Repo.all(from c in Credential, where: c.user_id == ^scope.user.id) == []

      assert {:ok, [%Credential{} = credential]} = Credentials.evaluate(scope, program)
      assert credential.qualification_id == qualification!(program, "basics").id
    end
  end

  describe "webhook jobs" do
    test "each issue enqueues credential.issued once per subscribed active webhook",
         %{program: program, scope: scope} do
      all_events = webhook_fixture()
      issued_only = webhook_fixture(%{events: ["credential.issued"]})
      webhook_fixture(%{events: ["credential.revoked"]})
      webhook_fixture(%{active: false})
      subscribed = Enum.sort([all_events.id, issued_only.id])

      basics = qualify_basics!(scope, program)
      jobs = all_enqueued(worker: WebhookWorker)

      assert jobs |> Enum.map(& &1.args["webhook_id"]) |> Enum.sort() == subscribed

      for job <- jobs do
        assert job.queue == "webhooks"

        assert job.args |> Map.keys() |> Enum.sort() ==
                 ~w(credential_id event occurred_at webhook_id)

        assert %{"event" => "credential.issued", "credential_id" => credential_id} = job.args
        assert credential_id == basics.id
      end

      certificate_fixture(scope.user, format!(program, "workshop"))
      assert {:ok, [workshop]} = Credentials.evaluate(scope, program)

      workshop_jobs =
        for %{args: %{"credential_id" => id} = args} <- all_enqueued(worker: WebhookWorker),
            id == workshop.id,
            do: args

      assert workshop_jobs |> Enum.map(& &1["webhook_id"]) |> Enum.sort() == subscribed
      assert Enum.all?(workshop_jobs, &(&1["event"] == "credential.issued"))
      assert length(all_enqueued(worker: WebhookWorker)) == 4
    end

    test "an evaluation that changes nothing enqueues no job", %{program: program, scope: scope} do
      qualify_basics!(scope, program)
      webhook_fixture()

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert all_enqueued(worker: WebhookWorker) == []
    end
  end
end
