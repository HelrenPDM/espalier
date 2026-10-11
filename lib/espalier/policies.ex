defmodule Espalier.Policies do
  @moduledoc """
  The Policies context: policies with numbered versions, the
  acknowledgements of learners and the approved tool list (README section
  7, domain rule 8).

  Policy tables hold no person. An acknowledgement belongs to the person in
  its `user_id` and is written only through the scope of that person. The
  published version with the highest `number` is the current version of a
  policy; a draft has no `published_at`, and a published version is
  read-only. Task 0015 adds the admin routes that create and edit policies,
  drafts and tools.
  """

  import Ecto.Query, warn: false
  alias Ecto.Changeset
  alias Espalier.Accounts.Scope
  alias Espalier.{Audit, Credentials, Repo}
  alias Espalier.Catalog.{Program, Qualification}
  alias Espalier.Learning.Enrollment
  alias Espalier.Policies.{Acknowledgement, ApprovedTool, Policy, PolicyVersion}

  @doc "Returns the policies, ordered by key."
  def list_policies do
    Repo.all(from p in Policy, order_by: p.key)
  end

  @doc """
  Gets a single policy.

  Raises `Ecto.NoResultsError` if the Policy does not exist.
  """
  def get_policy!(id), do: Repo.get!(Policy, id)

  @doc "Returns the policy with `key`, or `nil`."
  def get_policy_by_key(key) when is_binary(key), do: Repo.get_by(Policy, key: key)

  ## Versions

  @doc """
  Returns the current version of every policy, with its policy, ordered by
  policy key: per policy the published version with the highest `number`.
  """
  def current_versions do
    Repo.all(
      from v in PolicyVersion,
        join: p in assoc(v, :policy),
        where: not is_nil(v.published_at),
        distinct: [asc: p.key],
        order_by: [asc: p.key, desc: v.number],
        preload: [policy: p]
    )
  end

  @doc "Returns the current version of the policy `key` with its policy, or `nil`."
  def current_version(key) when is_binary(key) do
    Repo.one(
      from v in PolicyVersion,
        join: p in assoc(v, :policy),
        where: p.key == ^key and not is_nil(v.published_at),
        order_by: [desc: v.number],
        limit: 1,
        preload: [policy: p]
    )
  end

  @doc """
  Returns a map of policy key to current version for the given keys; a key
  without a published version is missing from the map.
  """
  def current_versions_by_key(keys) when is_list(keys) do
    case Enum.uniq(keys) do
      [] ->
        %{}

      keys ->
        Repo.all(
          from v in PolicyVersion,
            join: p in assoc(v, :policy),
            where: p.key in ^keys and not is_nil(v.published_at),
            distinct: [asc: p.key],
            order_by: [asc: p.key, desc: v.number],
            preload: [policy: p]
        )
        |> Map.new(&{&1.policy.key, &1})
    end
  end

  @doc "Returns the published version with `id`, with its policy, or `nil`."
  def get_published_version(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Repo.one(
          from v in PolicyVersion,
            where: v.id == ^uuid and not is_nil(v.published_at),
            preload: :policy
        )

      :error ->
        nil
    end
  end

  @doc """
  Creates a draft version of `policy` with the next `number`. Requires the
  role `admin`. The version stays a draft until `publish_version/2`.
  """
  def create_version(%Scope{} = scope, %Policy{} = policy, attrs) do
    if Scope.admin?(scope) do
      Repo.transact(fn -> create_version_in(scope, policy, attrs) end)
    else
      {:error, :forbidden}
    end
  end

  # The row lock on the policy serializes two drafts of one policy, so they
  # receive distinct numbers.
  defp create_version_in(scope, policy, attrs) do
    Repo.one!(from p in Policy, where: p.id == ^policy.id, lock: "FOR UPDATE", select: p.id)

    number =
      Repo.one(
        from v in PolicyVersion,
          where: v.policy_id == ^policy.id,
          select: coalesce(max(v.number), 0)
      ) + 1

    attrs = attrs |> Map.new() |> Map.drop([:number, "number"])

    with {:ok, version} <-
           %PolicyVersion{policy_id: policy.id, number: number}
           |> PolicyVersion.changeset(attrs)
           |> Changeset.put_change(:number, number)
           |> Repo.insert() do
      {:ok, _event} =
        Audit.record(scope, "policy_version.created", version, %{
          policy_key: policy.key,
          number: number
        })

      {:ok, version}
    end
  end

  @doc """
  Publishes a draft version. Requires the role `admin` (`{:error,
  :forbidden}` otherwise); a published version answers `{:error,
  :published}`, an unknown one `{:error, :not_found}`, and a draft whose
  policy has a published version with a higher number `{:error,
  :superseded}`, because it would never become the current version.

  In one transaction, the function sets `published_at`, writes the audit
  event `policy_version.published` and, when the version requires a
  refresher, moves the affected credentials to `refresh_due` through
  `Espalier.Credentials.mark_refresh_due_for_policy/1` (ASVS 2.3.3).
  """
  def publish_version(%Scope{} = scope, %PolicyVersion{} = version) do
    if Scope.admin?(scope) do
      Repo.transact(fn -> publish_in(scope, version.id) end)
    else
      {:error, :forbidden}
    end
  end

  defp publish_in(scope, version_id) do
    locked =
      Repo.one(
        from v in PolicyVersion,
          where: v.id == ^version_id,
          lock: "FOR UPDATE",
          preload: :policy
      )

    case locked do
      nil ->
        {:error, :not_found}

      %PolicyVersion{published_at: %DateTime{}} ->
        {:error, :published}

      version ->
        # Credentials.evaluate/2 holds a share lock on the policies it reads,
        # so a publication waits for a running evaluation, and an evaluation
        # that starts later reads the new current version. The lock also
        # serializes the publications of one policy.
        Repo.one!(
          from p in Policy, where: p.id == ^version.policy_id, lock: "FOR UPDATE", select: p.id
        )

        if superseded?(version), do: {:error, :superseded}, else: publish!(scope, version)
    end
  end

  defp superseded?(version) do
    Repo.exists?(
      from v in PolicyVersion,
        where:
          v.policy_id == ^version.policy_id and not is_nil(v.published_at) and
            v.number > ^version.number
    )
  end

  defp publish!(scope, version) do
    {:ok, published} =
      version
      |> Changeset.change(published_at: DateTime.utc_now(:second))
      |> Repo.update()

    {:ok, moved} =
      if published.requires_refresher,
        do: Credentials.mark_refresh_due_for_policy(published.policy.key),
        else: {:ok, []}

    {:ok, _event} =
      Audit.record(scope, "policy_version.published", published, %{
        policy_key: published.policy.key,
        number: published.number,
        requires_refresher: published.requires_refresher,
        refresh_due_count: length(moved)
      })

    {:ok, published}
  end

  ## Acknowledgements

  @doc """
  Records that the scope user acknowledged a published version and returns
  `{:ok, acknowledgement}`. A repeated acknowledgement changes nothing and
  returns the stored row; a draft answers `{:error, :not_found}`.

  Afterwards the function evaluates the requirements
  (`Espalier.Credentials.evaluate/2`) of every published program in which
  the user holds an enrollment, and of every published program whose live
  qualifications require the policy, so that a learner without an
  enrollment receives a credential whose last missing requirement was the
  acknowledgement.
  """
  def acknowledge(%Scope{} = scope, %PolicyVersion{published_at: %DateTime{}} = version) do
    {:ok, _row} =
      %Acknowledgement{
        policy_version_id: version.id,
        acknowledged_at: DateTime.utc_now(:second)
      }
      |> Acknowledgement.changeset(scope)
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :policy_version_id])

    acknowledgement =
      Repo.get_by!(Acknowledgement, user_id: scope.user.id, policy_version_id: version.id)

    %PolicyVersion{policy: policy} = Repo.preload(version, :policy)

    for program <- programs_to_evaluate(scope, policy.key) do
      {:ok, _changed} = Credentials.evaluate(scope, program)
    end

    {:ok, acknowledgement}
  end

  def acknowledge(%Scope{}, %PolicyVersion{}), do: {:error, :not_found}

  # The published programs in which the user holds an enrollment, and those
  # whose live qualifications require the policy: a learner without an
  # enrollment can meet a qualification through attendance and the
  # acknowledgement alone.
  defp programs_to_evaluate(scope, policy_key) do
    requiring =
      from q in Qualification,
        join: r in assoc(q, :requirements),
        where:
          is_nil(q.archived_at) and r.kind == :policy_acknowledged and
            r.target_key == ^policy_key,
        select: q.program_id

    enrolled = from e in Enrollment, where: e.user_id == ^scope.user.id, select: e.program_id

    Repo.all(
      from p in Program,
        where:
          p.status == :published and
            (p.id in subquery(requiring) or p.id in subquery(enrolled)),
        order_by: p.slug
    )
  end

  @doc """
  Returns the current versions with the acknowledgement of the scope user:
  one map per policy with `version` (with its policy) and
  `acknowledged_at` (or `nil`), ordered by policy key.
  """
  def list_current_for(%Scope{} = scope) do
    versions = current_versions()
    acknowledged = acknowledged_at(scope, Enum.map(versions, & &1.id))

    for version <- versions do
      %{version: version, acknowledged_at: Map.get(acknowledged, version.id)}
    end
  end

  @doc """
  Returns a map of version id to `acknowledged_at` for the versions among
  `version_ids` that the scope user acknowledged.
  """
  def acknowledged_at(%Scope{} = scope, version_ids) when is_list(version_ids) do
    Repo.all(
      from a in Acknowledgement,
        where: a.user_id == ^scope.user.id and a.policy_version_id in ^version_ids,
        select: {a.policy_version_id, a.acknowledged_at}
    )
    |> Map.new()
  end

  ## Approved tools

  @doc "Returns the approved tool list, ordered by `position` and name."
  def list_approved_tools do
    Repo.all(from t in ApprovedTool, order_by: [t.position, t.name])
  end
end
