defmodule Espalier.AdminContextTest do
  @moduledoc """
  The admin context functions of task 0015 (spec steps 2, 3, 6 and 19,
  bullet "Admin context functions"; ASVS 8.2.1). Every function that takes
  a scope returns `{:error, :forbidden}` for a scope without the role
  `admin`, writes no audit event and changes no row. `delete_policy/2`
  refuses a policy with a published version (`:policy_in_use`) and deletes
  a policy whose versions are drafts together with its drafts;
  `update_version/3` refuses a published version (`:published`); the
  readers return `{:error, :not_found}` for an unknown or malformed id; and
  `get_approved_tool!/1`, which takes no scope, raises
  `Ecto.NoResultsError` for an unknown id.
  """
  use Espalier.DataCase, async: true

  import Espalier.AccountsFixtures
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Accounts.Scope
  alias Espalier.Audit.AuditEvent
  alias Espalier.{Credentials, Policies}
  alias Espalier.Credentials.{Credential, Webhook}
  alias Espalier.Policies.{ApprovedTool, Policy, PolicyVersion}

  # Every function of steps 2, 3 and 6 that takes the scope first.
  @calls [
    {Policies, :create_policy},
    {Policies, :update_policy},
    {Policies, :delete_policy},
    {Policies, :create_approved_tool},
    {Policies, :update_approved_tool},
    {Policies, :delete_approved_tool},
    {Policies, :list_versions},
    {Policies, :get_version},
    {Policies, :update_version},
    {Policies, :publish_draft},
    {Credentials, :list_webhooks},
    {Credentials, :get_webhook},
    {Credentials, :create_webhook},
    {Credentials, :update_webhook},
    {Credentials, :delete_webhook},
    {Credentials, :get_any_credential}
  ]

  setup do
    program = publish_demo!()
    policy = policy_fixture(%{key: "usage-policy"})
    learner = user_fixture()
    admin = user_with_role_fixture(:admin)

    %{
      policy: policy,
      draft: draft_version_fixture(policy),
      tool: approved_tool_fixture(),
      webhook: webhook_fixture(),
      credential: credential_fixture(learner, qualification!(program, "basics")),
      learner_scope: Scope.for_user(learner),
      staff_scope: %Scope{
        Scope.for_user(user_fixture())
        | roles: [:learner, :author, :facilitator, :analyst, :registrar]
      },
      admin_scope: %Scope{Scope.for_user(admin) | roles: [:learner, :admin]}
    }
  end

  # The arguments after the scope.
  defp args(:create_policy, _ctx), do: [%{key: "new-policy", title: "New"}]
  defp args(:update_policy, ctx), do: [ctx.policy, %{title: "Changed"}]
  defp args(:delete_policy, ctx), do: [ctx.policy]

  defp args(:create_approved_tool, _ctx),
    do: [%{name: "New tool", vendor: "Vendor", status: :approved, position: 1}]

  defp args(:update_approved_tool, ctx), do: [ctx.tool, %{status: :not_approved}]
  defp args(:delete_approved_tool, ctx), do: [ctx.tool]
  defp args(:list_versions, ctx), do: [ctx.policy]
  defp args(:get_version, ctx), do: [ctx.draft.id]
  defp args(:update_version, ctx), do: [ctx.draft, %{body: "Changed."}]
  defp args(:publish_draft, ctx), do: [ctx.draft, true]
  defp args(:list_webhooks, _ctx), do: []
  defp args(:get_webhook, ctx), do: [ctx.webhook.id]

  defp args(:create_webhook, _ctx),
    do: [
      %{
        url: "https://hooks.example.org/new",
        events: ["credential.issued"],
        secret_env: "WEBHOOK_SECRET_NEW",
        active: true
      }
    ]

  defp args(:update_webhook, ctx), do: [ctx.webhook, %{active: false}]
  defp args(:delete_webhook, ctx), do: [ctx.webhook]
  defp args(:get_any_credential, ctx), do: [ctx.credential.id]

  # Every row that one of the functions could write.
  defp snapshot do
    for schema <- [AuditEvent, Policy, PolicyVersion, ApprovedTool, Webhook, Credential],
        into: %{},
        do: {schema, Repo.all(from r in schema, order_by: r.id)}
  end

  defp audit_events(action),
    do: Repo.all(from e in AuditEvent, where: e.action == ^action)

  describe "a scope without admin" do
    for {module, fun} <- @calls do
      @call {module, fun}

      test "#{inspect(module)}.#{fun} answers forbidden and writes nothing", ctx do
        {module, fun} = @call
        args = args(fun, ctx)
        before = snapshot()

        for scope <- [ctx.learner_scope, ctx.staff_scope] do
          assert apply(module, fun, [scope | args]) == {:error, :forbidden},
                 "#{inspect(module)}.#{fun}/#{length(args) + 1} with roles #{inspect(scope.roles)}"
        end

        assert snapshot() == before
      end
    end

    test "the list covers the scoped admin functions of steps 2, 3 and 6", ctx do
      assert length(@calls) == 16

      for {module, fun} <- @calls do
        arity = length(args(fun, ctx)) + 1
        assert function_exported?(module, fun, arity), "#{inspect(module)}.#{fun}/#{arity}"
      end
    end
  end

  describe "delete_policy/2" do
    test "answers policy_in_use for a policy with a published version", %{admin_scope: scope} do
      policy = policy_fixture()
      published = published_version_fixture(policy)
      draft = draft_version_fixture(policy)

      assert Policies.delete_policy(scope, policy) == {:error, :policy_in_use}

      assert Repo.get(Policy, policy.id)
      assert Repo.get(PolicyVersion, published.id)
      assert Repo.get(PolicyVersion, draft.id)
      assert audit_events("policy.deleted") == []
    end

    test "deletes a policy whose versions are drafts together with its drafts",
         %{admin_scope: scope, policy: other_policy, draft: other_draft} do
      policy = policy_fixture(%{key: "draft-policy"})
      first = draft_version_fixture(policy)
      second = draft_version_fixture(policy)

      assert {:ok, %Policy{id: id}} = Policies.delete_policy(scope, policy)
      assert id == policy.id

      assert Repo.get(Policy, policy.id) == nil
      assert Repo.get(PolicyVersion, first.id) == nil
      assert Repo.get(PolicyVersion, second.id) == nil
      assert Repo.get(Policy, other_policy.id)
      assert Repo.get(PolicyVersion, other_draft.id)

      assert [event] = audit_events("policy.deleted")
      assert event.actor_id == scope.user.id
      assert event.subject_type == "Policy"
      assert event.subject_id == policy.id
      assert event.details == %{"key" => "draft-policy", "drafts" => 2}
    end

    test "deletes a policy without versions and answers not_found once it is gone",
         %{admin_scope: scope} do
      policy = policy_fixture()

      assert {:ok, _deleted} = Policies.delete_policy(scope, policy)
      assert [%AuditEvent{details: %{"drafts" => 0}}] = audit_events("policy.deleted")
      assert Policies.delete_policy(scope, policy) == {:error, :not_found}
      assert length(audit_events("policy.deleted")) == 1
    end
  end

  describe "update_version/3" do
    test "answers published for a published version", %{admin_scope: scope} do
      published = published_version_fixture(policy_fixture(), %{body: "Published."})

      assert Policies.update_version(scope, published, %{body: "Changed."}) ==
               {:error, :published}

      assert %PolicyVersion{body: "Published."} = Repo.get!(PolicyVersion, published.id)
      assert audit_events("policy_version.updated") == []
    end
  end

  describe "readers" do
    test "answer not_found for an unknown or malformed id", %{admin_scope: scope} do
      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        assert Policies.get_version(scope, id) == {:error, :not_found}
        assert Credentials.get_webhook(scope, id) == {:error, :not_found}
        assert Credentials.get_any_credential(scope, id) == {:error, :not_found}
      end
    end

    test "return the record of an admin scope",
         %{admin_scope: scope, draft: draft, webhook: webhook, credential: credential} do
      assert {:ok, %PolicyVersion{id: draft_id, policy: %Policy{key: "usage-policy"}}} =
               Policies.get_version(scope, draft.id)

      assert draft_id == draft.id
      assert {:ok, %Webhook{id: webhook_id}} = Credentials.get_webhook(scope, webhook.id)
      assert webhook_id == webhook.id

      assert {:ok, %Credential{id: credential_id, qualification: %{code: "basics"}}} =
               Credentials.get_any_credential(scope, credential.id)

      assert credential_id == credential.id
    end
  end

  describe "get_approved_tool!/1" do
    test "returns a tool and raises Ecto.NoResultsError for an unknown id", %{tool: tool} do
      assert Policies.get_approved_tool!(tool.id).id == tool.id

      assert_raise Ecto.NoResultsError, fn ->
        Policies.get_approved_tool!(Ecto.UUID.generate())
      end
    end
  end
end
