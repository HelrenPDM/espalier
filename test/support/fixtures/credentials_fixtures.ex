defmodule Espalier.CredentialsFixtures do
  @moduledoc """
  Helpers for the tests of task 0013: policies and versions, approved
  tools, webhooks, API clients, users with a role, certificates, and the
  path of the demo learner to the credential `basics`.
  """

  import Ecto.Query

  alias Espalier.{Accounts, AccountsFixtures, Learning, LearningFixtures, Policies, Repo}
  alias Espalier.Accounts.Scope
  alias Espalier.Catalog.Qualification
  alias Espalier.Credentials.{AttendanceCertificate, Credential, Webhook}
  alias Espalier.Learning.ModuleCompletion
  alias Espalier.Policies.{ApprovedTool, Policy, PolicyVersion}

  @doc "Inserts a policy with `key` (default: a unique key)."
  def policy_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs)

    %Policy{}
    |> Policy.changeset(
      Map.merge(%{key: "policy-#{System.unique_integer([:positive])}", title: "A policy"}, attrs)
    )
    |> Repo.insert!()
  end

  @doc """
  Inserts a draft version of `policy` with the next number. `attrs` may set
  `body`, `effective_from` and `requires_refresher`.
  """
  def draft_version_fixture(%Policy{} = policy, attrs \\ %{}) do
    {:ok, version} = Policies.create_version(Scope.system(), policy, version_attrs(attrs))
    version
  end

  @doc "Inserts a draft version of `policy` and publishes it."
  def published_version_fixture(%Policy{} = policy, attrs \\ %{}) do
    version = draft_version_fixture(policy, attrs)
    {:ok, published} = Policies.publish_version(Scope.system(), version)
    Repo.preload(published, :policy, force: true)
  end

  defp version_attrs(attrs) do
    Map.merge(
      %{
        body: "The text of the policy.",
        effective_from: ~D[2026-01-01],
        requires_refresher: false
      },
      Map.new(attrs)
    )
  end

  @doc """
  Returns the policy `key` with a published version, creating both when
  the policy does not exist yet.
  """
  def published_policy!(key, attrs \\ %{}) do
    policy = Repo.get_by(Policy, key: key) || policy_fixture(%{key: key})

    case Policies.current_version(key) do
      nil -> published_version_fixture(policy, attrs)
      version -> version
    end
  end

  @doc "Inserts an approved tool."
  def approved_tool_fixture(attrs \\ %{}) do
    %ApprovedTool{}
    |> ApprovedTool.changeset(
      Map.merge(
        %{
          name: "Tool #{System.unique_integer([:positive])}",
          vendor: "Example vendor",
          status: :approved,
          conditions: "Internal drafts only.",
          reviewed_on: ~D[2026-09-01],
          position: 1
        },
        Map.new(attrs)
      )
    )
    |> Repo.insert!()
  end

  @doc """
  Inserts a webhook without the checks of the changeset, so that a test
  can set up a URL that the allowlist no longer admits.
  """
  def webhook_fixture(attrs \\ %{}) do
    Repo.insert!(
      struct!(
        Webhook,
        Map.merge(
          %{
            url: "https://hooks.example.org/espalier",
            events: Webhook.events(),
            secret_env: "WEBHOOK_SECRET_TEST",
            active: true
          },
          Map.new(attrs)
        )
      )
    )
  end

  @doc "Creates a user who holds `role` (granted before any session exists)."
  def user_with_role_fixture(role, attrs \\ %{}) do
    user = AccountsFixtures.user_fixture(attrs)
    {:ok, _grant} = Accounts.grant_role(Scope.system(), user, role)
    user
  end

  @doc "Creates a machine client with `scopes` and returns `{client, token}`."
  def api_client_fixture(scopes \\ ["credentials:read"]) do
    {:ok, {client, token}} =
      Accounts.create_api_client(Scope.system(), %{
        name: "client #{System.unique_integer([:positive])}",
        scopes: scopes
      })

    {client, token}
  end

  @doc "The qualification `code` of `program`."
  def qualification!(program, code),
    do: Repo.get_by!(Qualification, program_id: program.id, code: code)

  @doc "The credential of `user` for the qualification `code` of `program`, or `nil`."
  def credential_for(user, program, code) do
    qualification = qualification!(program, code)
    Repo.get_by(Credential, user_id: user.id, qualification_id: qualification.id)
  end

  @doc """
  Inserts a credential of `user` for `qualification` without evaluation.
  `attrs` may set `status`, `issued_at`, `valid_until` and
  `refresh_due_at`.
  """
  def credential_fixture(user, %Qualification{} = qualification, attrs \\ %{}) do
    Repo.insert!(
      struct!(
        Credential,
        Map.merge(
          %{
            user_id: user.id,
            qualification_id: qualification.id,
            status: :active,
            issued_at: DateTime.utc_now(:second),
            valid_until: nil,
            unlocks_snapshot: qualification.unlocks
          },
          Map.new(attrs)
        )
      )
    )
  end

  @doc "Inserts an attendance certificate of `user` for `format` held on `held_on`."
  def certificate_fixture(user, format, held_on \\ Date.utc_today(), issued_by \\ nil) do
    Repo.insert!(%AttendanceCertificate{
      user_id: user.id,
      companion_format_id: format.id,
      held_on: held_on,
      issued_by_id: issued_by && issued_by.id
    })
  end

  @doc """
  Walks the user of `scope` through the demo program to the credential
  `basics`: enrollment, modules 1 and 2, the passed exam `module-1-exam`
  and the acknowledgement of the current `usage-policy` version. Returns
  the credential.
  """
  def qualify_basics!(scope, program) do
    LearningFixtures.enroll!(scope)
    exam = LearningFixtures.assessment!(program, "module-1-exam")

    {:ok, %{outcome: :passed}, _results} =
      Learning.submit_attempt(
        scope,
        exam.id,
        exam
        |> LearningFixtures.exam_answers()
        |> Map.new(fn {id, answer} -> {id, LearningFixtures.cast_answer(answer)} end)
      )

    {:ok, _} = Learning.complete_module(scope, LearningFixtures.module!(program, 1).id)
    {:ok, _} = Learning.complete_module(scope, LearningFixtures.module!(program, 2).id)
    version = published_policy!("usage-policy")
    {:ok, _ack} = Policies.acknowledge(scope, version)
    credential_for(scope.user, program, "basics")
  end

  @doc "Sets `completed_at` of the user's completion of module `number` to `at`."
  def set_completed_at!(user, program, number, %DateTime{} = at) do
    module = LearningFixtures.module!(program, number)

    {1, _} =
      Repo.update_all(
        from(c in ModuleCompletion,
          where: c.user_id == ^user.id and c.module_id == ^module.id
        ),
        set: [completed_at: at]
      )

    :ok
  end

  @doc "Sets `refresh_due_at` (and the status) of a credential."
  def put_credential!(%Credential{} = credential, changes) do
    credential |> Ecto.Changeset.change(changes) |> Repo.update!()
  end

  @doc "Returns the version struct for a published version id."
  def version!(id), do: Repo.get!(PolicyVersion, id) |> Repo.preload(:policy)
end
