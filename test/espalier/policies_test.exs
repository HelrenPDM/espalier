defmodule Espalier.PoliciesTest do
  @moduledoc """
  The Policies context and the revocation of task 0013 (spec step 24,
  bullet "Policies and revocation", with steps 8 and 14; ASVS 2.3.3 and
  8.2.1). The current version of a policy is its published version with
  the highest number; `create_version/3`, `publish_version/2` and
  `Espalier.Credentials.revoke/2` require `admin` and write an audit event;
  a publication with `requires_refresher` moves exactly the active
  credentials that `count_affected_by_policy/1` counted beforehand;
  `acknowledge/2` is idempotent, refuses a draft and evaluates the enrolled
  programs and the programs that require the policy; a revoked credential
  stays revoked through `evaluate/2`, `sweep/1` and a policy publication.
  """
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Accounts.{MailWorker, Scope}
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.{Program, Qualification, Requirement}
  alias Espalier.{Credentials, Learning, Policies}
  alias Espalier.Credentials.{Credential, WebhookWorker}
  alias Espalier.Learning.Enrollment
  alias Espalier.Policies.{Acknowledgement, PolicyVersion}

  defp admin_scope do
    admin = user_with_role_fixture(:admin)
    %Scope{Scope.for_user(admin) | roles: [:learner, :admin]}
  end

  defp staff_scope do
    user = user_fixture()
    %Scope{Scope.for_user(user) | roles: [:learner, :facilitator, :registrar]}
  end

  defp audit_events(action),
    do: Repo.all(from e in AuditEvent, where: e.action == ^action, order_by: e.inserted_at)

  defp reload(%Credential{id: id}), do: Repo.get!(Credential, id)

  # The mail jobs of credential transitions as {kind, credential_id}.
  defp credential_mails do
    for(
      %{args: %{"kind" => "credential_" <> _status = kind} = args} <-
        all_enqueued(worker: MailWorker),
      do: {kind, args["credential_id"]}
    )
    |> Enum.sort()
  end

  defp hours_ago(hours), do: DateTime.add(DateTime.utc_now(:second), -hours, :hour)

  describe "current_versions/0 and current_version/1" do
    test "pick the published version with the highest number and ignore drafts" do
      policy = policy_fixture(%{key: "b-policy"})
      first = draft_version_fixture(policy)
      second = draft_version_fixture(policy)
      _draft = draft_version_fixture(policy)
      {:ok, _published} = Policies.publish_version(Scope.system(), second)
      {:ok, _published} = Policies.publish_version(Scope.system(), first)

      single = published_version_fixture(policy_fixture(%{key: "a-policy"}))
      draft_version_fixture(policy_fixture(%{key: "c-policy"}))

      assert %PolicyVersion{number: 2} = current = Policies.current_version("b-policy")
      assert current.id == second.id
      assert current.policy.key == "b-policy"
      assert Policies.current_version("a-policy").id == single.id
      assert Policies.current_version("c-policy") == nil
      assert Policies.current_version("missing-policy") == nil

      assert Enum.map(Policies.current_versions(), &{&1.policy.key, &1.id}) ==
               [{"a-policy", single.id}, {"b-policy", second.id}]

      assert Policies.current_versions_by_key(["a-policy", "b-policy", "c-policy"])
             |> Map.new(fn {key, version} -> {key, version.id} end) ==
               %{"a-policy" => single.id, "b-policy" => second.id}
    end

    test "get_published_version/1 returns only a published version" do
      policy = policy_fixture()
      published = published_version_fixture(policy)
      draft = draft_version_fixture(policy)

      assert Policies.get_published_version(published.id).id == published.id
      assert Policies.get_published_version(draft.id) == nil
      assert Policies.get_published_version(Ecto.UUID.generate()) == nil
      assert Policies.get_published_version("not-a-uuid") == nil
    end
  end

  describe "create_version/3" do
    test "requires admin" do
      policy = policy_fixture()
      attrs = %{body: "Text.", effective_from: ~D[2026-01-01], requires_refresher: false}

      for scope <- [scope_for(user_fixture()), staff_scope()] do
        assert Policies.create_version(scope, policy, attrs) == {:error, :forbidden}
      end

      assert Repo.aggregate(PolicyVersion, :count) == 0
      assert audit_events("policy_version.created") == []
    end

    test "creates drafts with the next number and writes the audit event" do
      scope = admin_scope()
      policy = policy_fixture()
      attrs = %{body: "Text.", effective_from: ~D[2026-01-01], requires_refresher: false}

      assert {:ok, %PolicyVersion{number: 1, published_at: nil} = first} =
               Policies.create_version(scope, policy, Map.put(attrs, :number, 7))

      assert {:ok, %PolicyVersion{number: 2, published_at: nil} = second} =
               Policies.create_version(scope, policy, attrs)

      # Both events can carry the same second, so their order is not asserted.
      events = audit_events("policy_version.created")

      assert events |> Enum.map(&{&1.subject_id, &1.details["number"]}) |> Enum.sort() ==
               Enum.sort([{first.id, 1}, {second.id, 2}])

      assert %AuditEvent{} = event = Enum.find(events, &(&1.subject_id == second.id))
      assert event.actor_id == scope.user.id
      assert event.details == %{"policy_key" => policy.key, "number" => 2}
    end
  end

  describe "publish_version/2" do
    test "answers forbidden for a scope without admin and keeps the draft" do
      draft = draft_version_fixture(policy_fixture())

      for scope <- [scope_for(user_fixture()), staff_scope()] do
        assert Policies.publish_version(scope, draft) == {:error, :forbidden}
      end

      assert Repo.get!(PolicyVersion, draft.id).published_at == nil
      assert audit_events("policy_version.published") == []
    end

    test "an admin sets published_at and writes the audit event policy_version.published" do
      scope = admin_scope()
      policy = policy_fixture()
      draft = draft_version_fixture(policy)

      assert {:ok, %PolicyVersion{published_at: %DateTime{}} = published} =
               Policies.publish_version(scope, draft)

      assert Repo.get!(PolicyVersion, draft.id).published_at == published.published_at

      assert [event] = audit_events("policy_version.published")
      assert event.subject_type == "PolicyVersion"
      assert event.subject_id == draft.id
      assert event.actor_id == scope.user.id

      assert event.details == %{
               "policy_key" => policy.key,
               "number" => 1,
               "requires_refresher" => false,
               "refresh_due_count" => 0
             }
    end

    test "the system scope publishes without an actor" do
      draft = draft_version_fixture(policy_fixture())

      assert {:ok, _published} = Policies.publish_version(Scope.system(), draft)
      assert [%AuditEvent{actor_id: nil}] = audit_events("policy_version.published")
    end

    test "a second publication answers published and writes no second event" do
      draft = draft_version_fixture(policy_fixture())
      {:ok, published} = Policies.publish_version(Scope.system(), draft)

      assert Policies.publish_version(Scope.system(), draft) == {:error, :published}
      assert Policies.publish_version(Scope.system(), published) == {:error, :published}
      assert length(audit_events("policy_version.published")) == 1
    end

    test "an unknown version answers not_found" do
      assert Policies.publish_version(Scope.system(), %PolicyVersion{id: Ecto.UUID.generate()}) ==
               {:error, :not_found}
    end

    test "with requires_refresher moves the active credentials that count_affected_by_policy/1 counted" do
      program = publish_demo!()
      current = published_policy!("usage-policy")
      basics = qualification!(program, "basics")
      [first, second, third, fourth] = for _n <- 1..4, do: user_fixture()
      earlier = hours_ago(24)

      active = [credential_fixture(first, basics), credential_fixture(second, basics)]
      due = credential_fixture(third, basics, status: :refresh_due, refresh_due_at: earlier)
      revoked = credential_fixture(fourth, basics, status: :revoked)
      add_on = credential_fixture(first, qualification!(program, "workshop"))

      draft = draft_version_fixture(current.policy, %{requires_refresher: true})
      assert Credentials.count_affected_by_policy("usage-policy") == 2

      published_after = DateTime.utc_now(:second)

      assert {:ok, %PolicyVersion{requires_refresher: true}} =
               Policies.publish_version(Scope.system(), draft)

      for credential <- active do
        moved = reload(credential)
        assert moved.status == :refresh_due
        assert DateTime.compare(moved.refresh_due_at, published_after) != :lt
      end

      assert reload(due).refresh_due_at == earlier
      assert reload(revoked).status == :revoked
      assert reload(add_on).status == :active
      assert Credentials.count_affected_by_policy("usage-policy") == 0

      assert %AuditEvent{} =
               event =
               Enum.find(audit_events("policy_version.published"), &(&1.subject_id == draft.id))

      assert event.details["requires_refresher"] == true
      assert event.details["refresh_due_count"] == 2

      assert credential_mails() ==
               active |> Enum.map(&{"credential_refresh_due", &1.id}) |> Enum.sort()
    end

    test "without requires_refresher moves no credential" do
      program = publish_demo!()
      current = published_policy!("usage-policy")
      credential = credential_fixture(user_fixture(), qualification!(program, "basics"))

      draft = draft_version_fixture(current.policy, %{requires_refresher: false})
      assert {:ok, _published} = Policies.publish_version(Scope.system(), draft)

      assert reload(credential).status == :active
      assert credential_mails() == []
    end
  end

  describe "acknowledge/2" do
    test "a second acknowledgement leaves one row and returns the stored one" do
      scope = scope_for(user_fixture())
      version = published_version_fixture(policy_fixture())

      assert {:ok, %Acknowledgement{} = first} = Policies.acknowledge(scope, version)
      assert first.user_id == scope.user.id

      earlier = hours_ago(48)

      {1, _rows} =
        Repo.update_all(from(a in Acknowledgement, where: a.id == ^first.id),
          set: [acknowledged_at: earlier]
        )

      assert {:ok, %Acknowledgement{} = second} = Policies.acknowledge(scope, version)
      assert second.id == first.id
      assert second.acknowledged_at == earlier
      assert Repo.aggregate(Acknowledgement, :count) == 1
    end

    test "an acknowledgement of a draft answers not_found and stores nothing" do
      scope = scope_for(user_fixture())
      draft = draft_version_fixture(policy_fixture())

      assert Policies.acknowledge(scope, draft) == {:error, :not_found}
      assert Repo.aggregate(Acknowledgement, :count) == 0
    end

    test "evaluates the published programs in which the user is enrolled" do
      program = publish_demo!()
      scope = scope_for(user_fixture())
      version = published_policy!("usage-policy")
      enroll!(scope)
      exam = assessment!(program, "module-1-exam")
      answers = Map.new(exam_answers(exam), fn {id, answer} -> {id, cast_answer(answer)} end)
      {:ok, %{outcome: :passed}, _results} = Learning.submit_attempt(scope, exam.id, answers)
      {:ok, _completion} = Learning.complete_module(scope, module!(program, 1).id)
      {:ok, _completion} = Learning.complete_module(scope, module!(program, 2).id)
      assert credential_for(scope.user, program, "basics") == nil

      assert {:ok, _acknowledgement} = Policies.acknowledge(scope, version)
      assert %Credential{status: :active} = credential_for(scope.user, program, "basics")
    end

    test "issues a credential to a learner without an enrollment whose last missing requirement is the acknowledgement" do
      program = publish_demo!()
      version = published_policy!("usage-policy")
      scope = scope_for(user_fixture())
      workshop = qualification!(program, "workshop")

      credential_fixture(scope.user, qualification!(program, "basics"))
      certificate_fixture(scope.user, format!(program, "workshop"))

      Repo.insert!(%Requirement{
        qualification_id: workshop.id,
        kind: :policy_acknowledged,
        target_key: "usage-policy"
      })

      assert {:ok, []} = Credentials.evaluate(scope, program)
      assert credential_for(scope.user, program, "workshop") == nil

      assert {:ok, _acknowledgement} = Policies.acknowledge(scope, version)
      assert %Credential{status: :active} = credential_for(scope.user, program, "workshop")
      assert Repo.all(from e in Enrollment, where: e.user_id == ^scope.user.id) == []
    end

    test "does not evaluate a published program that neither requires the policy nor holds an enrollment" do
      scope = scope_for(user_fixture())
      version = published_version_fixture(policy_fixture())

      other =
        Repo.insert!(%Program{
          slug: "other-program-#{System.unique_integer([:positive])}",
          title: "Other program",
          locale: "en",
          status: :published,
          pack_version: "1.0.0"
        })

      # Without requirements, an evaluation issues this qualification.
      qualification =
        Repo.insert!(%Qualification{
          program_id: other.id,
          code: "other",
          title: "Other qualification",
          audience: "Everyone.",
          validity_kind: :none
        })

      assert {:ok, _acknowledgement} = Policies.acknowledge(scope, version)
      assert Repo.all(from c in Credential, where: c.user_id == ^scope.user.id) == []

      assert {:ok, [%Credential{} = issued]} = Credentials.evaluate(scope, other)
      assert issued.qualification_id == qualification.id
    end
  end

  describe "list_current_for/1" do
    test "returns the current versions with the acknowledged_at of the scope user" do
      scope = scope_for(user_fixture())
      a_policy = policy_fixture(%{key: "a-policy"})
      a_version = published_version_fixture(a_policy)
      b_version = published_version_fixture(policy_fixture(%{key: "b-policy"}))
      {:ok, acknowledgement} = Policies.acknowledge(scope, a_version)
      {:ok, _other} = Policies.acknowledge(scope_for(user_fixture()), b_version)

      assert [
               %{version: %PolicyVersion{} = first, acknowledged_at: acknowledged_at},
               %{version: %PolicyVersion{} = second, acknowledged_at: nil}
             ] = Policies.list_current_for(scope)

      assert {first.id, first.policy.key} == {a_version.id, "a-policy"}
      assert second.id == b_version.id
      assert acknowledged_at == acknowledgement.acknowledged_at

      assert Policies.acknowledged_at(scope, [a_version.id, b_version.id]) ==
               %{a_version.id => acknowledgement.acknowledged_at}

      newer = published_version_fixture(a_policy)

      assert [%{version: %PolicyVersion{} = current, acknowledged_at: nil}, _b] =
               Policies.list_current_for(scope)

      assert current.id == newer.id
    end
  end

  describe "list_approved_tools/0" do
    test "orders the tools by position" do
      for {name, position} <- [{"Charlie", 3}, {"Zulu", 1}, {"Alpha", 2}, {"Bravo", 1}] do
        approved_tool_fixture(%{name: name, position: position})
      end

      assert Enum.map(Policies.list_approved_tools(), &{&1.position, &1.name}) ==
               [{1, "Bravo"}, {1, "Zulu"}, {2, "Alpha"}, {3, "Charlie"}]
    end
  end

  describe "Credentials.revoke/2" do
    setup do
      program = publish_demo!()
      scope = scope_for(user_fixture())
      credential = qualify_basics!(scope, program)
      %{program: program, scope: scope, credential: credential}
    end

    test "answers forbidden for a scope without admin and changes nothing",
         %{scope: scope, credential: credential} do
      webhook_fixture()

      for other <- [scope, staff_scope()] do
        assert Credentials.revoke(other, credential) == {:error, :forbidden}
      end

      assert reload(credential).status == :active
      assert audit_events("credential.revoked") == []
      assert all_enqueued(worker: WebhookWorker) == []
    end

    test "an admin revokes, writes the audit event and enqueues credential.revoked",
         %{credential: credential} do
      subscribed = webhook_fixture(%{events: ["credential.revoked"]})
      webhook_fixture(%{events: ["credential.issued"]})
      scope = admin_scope()

      assert {:ok, %Credential{status: :revoked}} = Credentials.revoke(scope, credential)
      assert reload(credential).status == :revoked

      assert [event] = audit_events("credential.revoked")
      assert event.subject_type == "Credential"
      assert event.subject_id == credential.id
      assert event.actor_id == scope.user.id
      assert event.details == %{"previous_status" => "active"}

      assert [job] = all_enqueued(worker: WebhookWorker)

      assert job.args["webhook_id"] == subscribed.id
      assert job.args["event"] == "credential.revoked"
      assert job.args["credential_id"] == credential.id
    end

    test "the system scope revokes a refresh_due credential, and a second revocation answers already_revoked",
         %{credential: credential} do
      credential = put_credential!(credential, status: :refresh_due, refresh_due_at: hours_ago(1))
      webhook_fixture(%{events: ["credential.revoked"]})

      assert {:ok, %Credential{status: :revoked}} = Credentials.revoke(Scope.system(), credential)
      assert Credentials.revoke(Scope.system(), credential) == {:error, :already_revoked}

      assert [event] = audit_events("credential.revoked")
      assert event.actor_id == nil
      assert event.details == %{"previous_status" => "refresh_due"}
      assert length(all_enqueued(worker: WebhookWorker)) == 1
    end

    test "an admin revokes an expired credential and records the previous status expired",
         %{credential: credential} do
      credential =
        put_credential!(credential,
          status: :expired,
          refresh_due_at: hours_ago(24 * 60),
          valid_until: Date.add(Date.utc_today(), -40)
        )

      webhook_fixture(%{events: ["credential.revoked"]})

      assert {:ok, %Credential{status: :revoked}} = Credentials.revoke(admin_scope(), credential)
      assert reload(credential).status == :revoked

      assert [event] = audit_events("credential.revoked")
      assert event.subject_id == credential.id
      assert event.details == %{"previous_status" => "expired"}

      assert [job] = all_enqueued(worker: WebhookWorker)
      assert job.args["event"] == "credential.revoked"
      assert job.args["credential_id"] == credential.id
    end

    test "a revoked credential stays revoked through evaluate/2, sweep/1 and a policy publication",
         %{program: program, scope: scope, credential: credential} do
      today = Date.utc_today()

      credential =
        put_credential!(credential,
          refresh_due_at: hours_ago(24),
          valid_until: Date.add(today, -100)
        )

      {:ok, _revoked} = Credentials.revoke(Scope.system(), credential)
      webhook_fixture()

      assert {:ok, []} = Credentials.evaluate(scope, program)
      {:ok, _completion} = Learning.complete_module(scope, module!(program, 2).id)
      assert reload(credential).status == :revoked

      assert {:ok, %{refresh_due: [], expired: []}} = Credentials.sweep(today)
      assert {:ok, %{refresh_due: [], expired: []}} = Credentials.sweep(Date.add(today, 365))
      assert reload(credential).status == :revoked

      assert Credentials.count_affected_by_policy("usage-policy") == 0
      current = Policies.current_version("usage-policy")
      draft = draft_version_fixture(current.policy, %{requires_refresher: true})
      assert {:ok, _published} = Policies.publish_version(Scope.system(), draft)

      assert [%Credential{status: :revoked} = stored] =
               Repo.all(from c in Credential, where: c.user_id == ^scope.user.id)

      assert stored.id == credential.id
      assert stored.valid_until == credential.valid_until
      assert all_enqueued(worker: WebhookWorker) == []
      assert credential_mails() == []
    end

    test "an unknown credential answers not_found" do
      assert Credentials.revoke(Scope.system(), %Credential{id: Ecto.UUID.generate()}) ==
               {:error, :not_found}
    end
  end
end
