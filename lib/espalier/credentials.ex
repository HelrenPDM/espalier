defmodule Espalier.Credentials do
  @moduledoc """
  Requirement evaluation, credentials, attendance and their lifecycle
  (README section 7, domain rules 6, 7 and 11; `credential-lifecycle.puml`).

  `evaluate/2` issues a credential once every requirement of a qualification
  holds and restores a `refresh_due` or `expired` credential once the
  refresher mode of its qualification holds. `sweep/1` (daily, through
  `Espalier.Credentials.SweepWorker`) and `mark_refresh_due_for_policy/1`
  move credentials to `refresh_due` and `expired`, and `revoke/2` ends a
  credential for good. Every transition enqueues the matching webhook event
  (`Espalier.Credentials.WebhookWorker`), and every move to `refresh_due` or
  `expired` also a mail (`Espalier.Accounts.MailWorker`).

  Person-linked rows are read and written only through the scope of their
  person. A facilitator who issues an attendance certificate writes it with
  the learner's scope from `Espalier.Accounts.Scope.for_user/1`. A credential
  is in force while its status is `active` or `refresh_due`.
  """

  import Ecto.Query, warn: false
  alias Ecto.Changeset
  alias Espalier.Accounts
  alias Espalier.Accounts.{MailWorker, Scope, User}
  alias Espalier.{Audit, Catalog, Policies, Repo}

  alias Espalier.Catalog.{
    Assessment,
    CompanionFormat,
    Program,
    Qualification,
    Requirement,
    Station
  }

  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Credentials.{AttendanceCertificate, Credential, Webhook, WebhookWorker}
  alias Espalier.Learning.{AssessmentAttempt, ModuleCompletion}
  alias Espalier.Policies.{Acknowledgement, Policy}

  # The transaction-level advisory lock that serializes the evaluations of
  # one user. Its two-key form does not share its keys with the one-key form
  # of the pack publisher; the first key names this context.
  @lock_sql "SELECT pg_advisory_xact_lock(13, hashtext($1))"

  @kind_order [
    :module_completed,
    :assessment_passed,
    :policy_acknowledged,
    :attendance,
    :qualification_held
  ]

  ## Evaluation

  @doc """
  Evaluates the requirements of the program's live qualifications for the
  scope user and returns `{:ok, changed}` with the credentials it issued or
  restored.

  A qualification whose requirements all hold and for which the user has no
  credential receives one with the status `active`, `unlocks_snapshot`
  copied from `Qualification.unlocks`, `issued_at` now and `valid_until`
  set by the qualification's validity. A revoked credential blocks a new
  issue. A `refresh_due` or `expired` credential returns to `active` when
  the refresher mode holds after `refresh_due_at`; the restore sets
  `valid_until` from the restore date, keeps `unlocks_snapshot` and clears
  `refresh_due_at`. A qualification without refresher mode (validity kind
  `none`) restores once every requirement holds again, which after a policy
  version that requires a refresher means the acknowledgement of that
  version. Each issue and each restore enqueues the webhook event
  `credential.issued`.

  The evaluation repeats until nothing changes, so that an add-on whose
  prerequisite is issued in the same call is issued as well. A program that
  is not published issues and restores nothing.
  """
  @spec evaluate(Scope.t(), Program.t()) :: {:ok, [Credential.t()]}
  def evaluate(%Scope{}, %Program{status: status}) when status != :published, do: {:ok, []}

  def evaluate(%Scope{user: %User{} = user} = scope, %Program{} = program) do
    Repo.transact(fn ->
      Repo.query!(@lock_sql, [user.id])
      qualifications = live_qualifications(program.id)
      lock_required_policies!(qualifications)
      facts = facts(user.id, program, qualifications)
      credentials = credentials_by_qualification(user.id, qualifications)
      today = Date.utc_today()

      {:ok, evaluate_until_stable(scope, qualifications, facts, credentials, today, [])}
    end)
  end

  # A share lock on the policies that the requirements name: a publication
  # (Policies.publish_version/2 locks the policy row FOR UPDATE) waits for
  # this evaluation, so its refresher move sees a credential issued here,
  # and this evaluation waits for a running publication, so it reads the
  # new current version.
  defp lock_required_policies!(qualifications) do
    case policy_keys(qualifications) do
      [] ->
        :ok

      keys ->
        Repo.all(
          from p in Policy,
            where: p.key in ^keys,
            order_by: p.key,
            lock: "FOR SHARE",
            select: p.id
        )

        :ok
    end
  end

  defp policy_keys(qualifications) do
    for qualification <- qualifications,
        %Requirement{kind: :policy_acknowledged, target_key: key} <- qualification.requirements,
        uniq: true,
        do: key
  end

  defp evaluate_until_stable(scope, qualifications, facts, credentials, today, changed) do
    {facts, credentials, round} =
      Enum.reduce(qualifications, {facts, credentials, []}, fn qualification, acc ->
        evaluate_one(scope, qualification, acc, today)
      end)

    if round == [],
      do: Enum.reverse(changed),
      else:
        evaluate_until_stable(scope, qualifications, facts, credentials, today, round ++ changed)
  end

  defp evaluate_one(scope, qualification, {facts, credentials, round}, today) do
    case Map.get(credentials, qualification.id) do
      nil ->
        if Enum.all?(qualification.requirements, &met?(&1, facts)) do
          credential = issue!(scope, qualification, today)

          {hold(facts, qualification), Map.put(credentials, qualification.id, credential),
           [credential | round]}
        else
          {facts, credentials, round}
        end

      %Credential{status: status} = credential when status in [:refresh_due, :expired] ->
        if refreshed?(qualification, facts, credential) do
          restored = restore!(qualification, credential, today)

          {hold(facts, qualification), Map.put(credentials, qualification.id, restored),
           [restored | round]}
        else
          {facts, credentials, round}
        end

      _active_or_revoked ->
        {facts, credentials, round}
    end
  end

  defp issue!(scope, qualification, today) do
    credential =
      %Credential{
        qualification_id: qualification.id,
        status: :active,
        issued_at: DateTime.utc_now(:second),
        valid_until: valid_until(qualification, today),
        unlocks_snapshot: qualification.unlocks
      }
      |> Credential.changeset(scope)
      |> Repo.insert!()

    :ok = enqueue_webhooks("credential.issued", credential)
    credential
  end

  defp restore!(qualification, credential, today) do
    restored =
      credential
      |> Changeset.change(
        status: :active,
        valid_until: valid_until(qualification, today),
        refresh_due_at: nil
      )
      |> Repo.update!()

    :ok = enqueue_webhooks("credential.issued", restored)
    restored
  end

  defp valid_until(%Qualification{validity_kind: :months, validity_months: months}, date)
       when is_integer(months),
       do: Date.shift(date, month: months)

  defp valid_until(_qualification, _date), do: nil

  defp hold(facts, qualification), do: %{facts | held: MapSet.put(facts.held, qualification.code)}

  # The requirement kinds of README section 7, domain rule 6.
  defp met?(%Requirement{kind: :module_completed, target_key: key}, facts),
    do: Map.has_key?(facts.completed, key)

  defp met?(%Requirement{kind: :assessment_passed, target_key: key}, facts),
    do: Map.has_key?(facts.passed, key)

  defp met?(%Requirement{kind: :policy_acknowledged, target_key: key}, facts),
    do: Map.has_key?(facts.acknowledged, key)

  defp met?(%Requirement{kind: :attendance, target_key: key}, facts),
    do: Map.has_key?(facts.attended, key)

  defp met?(%Requirement{kind: :qualification_held, target_key: code}, facts),
    do: MapSet.member?(facts.held, code)

  # The refresher modes of README section 7, domain rule 7. Records count
  # only when they are later than `refresh_due_at`.
  defp refreshed?(%Qualification{refresher_mode: :update_unit}, facts, credential) do
    since = refresh_reference(credential)

    facts.refresher_module_ids != [] and
      Enum.all?(facts.refresher_module_ids, &later?(Map.get(facts.completed_by_id, &1), since))
  end

  defp refreshed?(%Qualification{refresher_mode: :full_run} = qualification, facts, credential) do
    since = refresh_reference(credential)
    Enum.all?(qualification.requirements, &met_since?(&1, facts, since))
  end

  defp refreshed?(%Qualification{refresher_mode: :test_only} = qualification, facts, credential) do
    since = refresh_reference(credential)
    exams = Enum.filter(qualification.requirements, &(&1.kind == :assessment_passed))
    exams != [] and Enum.all?(exams, &met_since?(&1, facts, since))
  end

  # A qualification without refresher mode (validity_kind none) enters
  # refresh_due only through a policy version that requires a refresher. It
  # returns to active once every requirement holds again; the
  # acknowledgement counts only for the current version, so acknowledging
  # the new version restores it.
  defp refreshed?(%Qualification{refresher_mode: nil} = qualification, facts, _credential),
    do: Enum.all?(qualification.requirements, &met?(&1, facts))

  defp met_since?(%Requirement{kind: :module_completed, target_key: key}, facts, since),
    do: later?(Map.get(facts.completed, key), since)

  defp met_since?(%Requirement{kind: :assessment_passed, target_key: key}, facts, since),
    do: later?(Map.get(facts.passed, key), since)

  defp met_since?(%Requirement{kind: :attendance, target_key: key}, facts, since) do
    case Map.get(facts.attended, key) do
      %Date{} = held_on -> Date.compare(held_on, DateTime.to_date(since)) != :lt
      nil -> false
    end
  end

  defp met_since?(requirement, facts, _since), do: met?(requirement, facts)

  # A credential in refresh_due or expired always carries refresh_due_at;
  # issued_at stands in for a row that lacks it.
  defp refresh_reference(%Credential{refresh_due_at: %DateTime{} = at}), do: at
  defp refresh_reference(%Credential{issued_at: at}), do: at

  defp later?(%DateTime{} = at, since), do: DateTime.after?(at, since)
  defp later?(nil, _since), do: false

  ## Facts

  defp live_qualifications(program_id) do
    Repo.all(
      from q in Qualification,
        where: q.program_id == ^program_id and is_nil(q.archived_at),
        order_by: [q.add_on, q.code],
        preload: [requirements: ^from(r in Requirement, order_by: [r.kind, r.target_key])]
    )
  end

  # The records of the user that the requirements of the program read:
  # completions by module number (and by module id for the refresher units),
  # the latest passed attempt per exam key, the acknowledgement of the
  # current version per policy key, the latest certificate per format key
  # for formats whose attendance counts, and the codes of the
  # qualifications whose credential is in force.
  defp facts(user_id, program, qualifications) do
    completions =
      Repo.all(
        from c in ModuleCompletion,
          join: m in CatalogModule,
          on: m.id == c.module_id,
          where: c.user_id == ^user_id and m.program_id == ^program.id,
          select: {m.id, m.number, c.completed_at}
      )

    %{
      completed: latest_by(completions, fn {_id, number, at} -> {to_string(number), at} end),
      completed_by_id: latest_by(completions, fn {id, _number, at} -> {id, at} end),
      refresher_module_ids: refresher_module_ids(program.id),
      passed: passed_attempts(user_id, program.id),
      acknowledged: acknowledged_policies(user_id, qualifications),
      attended: attended_formats(user_id, program.id),
      held: held_codes(user_id, program.id)
    }
  end

  defp latest_by(rows, fun) do
    Enum.reduce(rows, %{}, fn row, acc ->
      {key, value} = fun.(row)
      Map.update(acc, key, value, &latest(&1, value))
    end)
  end

  defp latest(%DateTime{} = a, %DateTime{} = b), do: if(DateTime.after?(b, a), do: b, else: a)
  defp latest(%Date{} = a, %Date{} = b), do: if(Date.after?(b, a), do: b, else: a)

  defp refresher_module_ids(program_id) do
    Repo.all(
      from m in CatalogModule,
        where: m.program_id == ^program_id and m.refresher_unit and is_nil(m.archived_at),
        select: m.id
    )
  end

  defp passed_attempts(user_id, program_id) do
    Repo.all(
      from a in AssessmentAttempt,
        join: s in Assessment,
        on: s.id == a.assessment_id,
        where: a.user_id == ^user_id and s.program_id == ^program_id and a.outcome == :passed,
        group_by: s.key,
        select: {s.key, max(a.submitted_at)}
    )
    |> Map.new()
  end

  defp acknowledged_policies(user_id, qualifications) do
    versions = qualifications |> policy_keys() |> Policies.current_versions_by_key()
    ids = versions |> Map.values() |> Enum.map(& &1.id)

    acknowledged =
      Repo.all(
        from a in Acknowledgement,
          where: a.user_id == ^user_id and a.policy_version_id in ^ids,
          select: {a.policy_version_id, a.acknowledged_at}
      )
      |> Map.new()

    for {key, version} <- versions, Map.has_key?(acknowledged, version.id), into: %{} do
      {key, Map.fetch!(acknowledged, version.id)}
    end
  end

  defp attended_formats(user_id, program_id) do
    Repo.all(
      from c in AttendanceCertificate,
        join: f in CompanionFormat,
        on: f.id == c.companion_format_id,
        where: c.user_id == ^user_id and f.program_id == ^program_id and f.attendance_counts,
        group_by: f.key,
        select: {f.key, max(c.held_on)}
    )
    |> Map.new()
  end

  defp held_codes(user_id, program_id) do
    statuses = Credential.in_force_statuses()

    Repo.all(
      from c in Credential,
        join: q in Qualification,
        on: q.id == c.qualification_id,
        where: c.user_id == ^user_id and q.program_id == ^program_id and c.status in ^statuses,
        select: q.code
    )
    |> MapSet.new()
  end

  defp credentials_by_qualification(user_id, qualifications) do
    ids = Enum.map(qualifications, & &1.id)

    Repo.all(
      from c in Credential,
        where: c.user_id == ^user_id and c.qualification_id in ^ids,
        lock: "FOR UPDATE"
    )
    |> Map.new(&{&1.qualification_id, &1})
  end

  ## Attendance and objective evidence

  @doc """
  Returns the ids of the companion formats of the program for which the
  scope user holds an attendance certificate, each id once, ordered by id.

  The function needs no enrollment, because a certificate belongs to the
  user. It also returns formats without `attendance_counts`;
  `Espalier.Catalog.objective_links/2` lists a format as evidence only when
  its attendance counts (README section 7, domain rules 11 and 15).
  """
  @spec attended_format_ids(Scope.t(), Program.t()) :: [Ecto.UUID.t()]
  def attended_format_ids(%Scope{user: %User{id: user_id}}, %Program{id: program_id}) do
    Repo.all(
      from c in AttendanceCertificate,
        join: f in CompanionFormat,
        on: f.id == c.companion_format_id,
        where: c.user_id == ^user_id and f.program_id == ^program_id,
        distinct: true,
        order_by: f.id,
        select: f.id
    )
  end

  @doc """
  Issues one attendance certificate per active user for a live format of a
  published program, held on `held_on`. Requires the role `facilitator`.

  Returns `{:ok, results}` with one map `%{user_id: id, result: result}` per
  distinct user id (lower-case) in request order, where `result` is `:issued`, `:exists`
  (a certificate for the format and the date exists) or `:not_found` (no
  active user). Each new certificate writes the audit event
  `attendance.issued`, and every found user is evaluated in the format's
  program (`evaluate/2`). A format outside a published program answers
  `{:error, :not_found}`, and a date after today
  `{:error, {:validation_failed, "held_on", "future"}}` (ASVS 2.2.3).
  """
  def issue_attendance(%Scope{} = scope, format_id, user_ids, %Date{} = held_on)
      when is_list(user_ids) do
    cond do
      not Scope.has_role?(scope, :facilitator) ->
        {:error, :forbidden}

      Date.after?(held_on, Date.utc_today()) ->
        {:error, {:validation_failed, "held_on", "future"}}

      true ->
        with {:ok, format} <- fetch_published_format(format_id) do
          ids = user_ids |> Enum.map(&normalize_id/1) |> Enum.uniq()
          users = active_users(ids)

          {:ok,
           for id <- ids do
             %{user_id: id, result: issue_for(scope, format, Map.get(users, id), held_on)}
           end}
        end
    end
  end

  defp fetch_published_format(format_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(format_id),
         %CompanionFormat{} = format <-
           Repo.one(
             from f in CompanionFormat,
               join: p in assoc(f, :program),
               where: f.id == ^uuid and is_nil(f.archived_at) and p.status == :published,
               preload: [program: p]
           ) do
      {:ok, format}
    else
      _ -> {:error, :not_found}
    end
  end

  # Ecto.UUID.cast/1 lower-cases a UUID, so ids that differ in letter case
  # name one user.
  defp normalize_id(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> uuid
      :error -> id
    end
  end

  defp active_users(ids) do
    uuids = for id <- ids, {:ok, uuid} <- [Ecto.UUID.cast(id)], do: uuid

    Repo.all(from u in User, where: u.id in ^uuids and u.status == :active)
    |> Map.new(&{&1.id, &1})
  end

  defp issue_for(_scope, _format, nil, _held_on), do: :not_found

  defp issue_for(scope, format, %User{} = user, held_on) do
    learner = Scope.for_user(user)

    result =
      Repo.transact(fn ->
        changeset =
          %AttendanceCertificate{
            companion_format_id: format.id,
            held_on: held_on,
            issued_by_id: scope.user && scope.user.id
          }
          |> AttendanceCertificate.changeset(learner)

        with {:ok, certificate} <- Repo.insert(changeset) do
          {:ok, _event} =
            Audit.record(scope, "attendance.issued", certificate, %{
              format_key: format.key,
              held_on: Date.to_iso8601(held_on)
            })

          {:ok, certificate}
        end
      end)

    {:ok, _changed} = evaluate(learner, format.program)

    case result do
      {:ok, _certificate} -> :issued
      {:error, %Changeset{}} -> :exists
    end
  end

  @doc """
  Looks up one active user by the exact address, trimmed and lower-cased,
  through `email_hash`, for the attendance page of a facilitator. Returns
  `{:ok, user}` or `{:error, :not_found}`; requires the role `facilitator`.
  """
  def lookup_user(%Scope{} = scope, email) when is_binary(email) do
    if Scope.has_role?(scope, :facilitator) do
      case Accounts.get_user_by_email(email) do
        %User{status: :active} = user -> {:ok, user}
        _other -> {:error, :not_found}
      end
    else
      {:error, :forbidden}
    end
  end

  ## Requirements and credentials of the learner

  @doc """
  Returns the requirements of the live qualifications of the published
  program `slug` for the scope user, or `{:error, :not_found}`.

  Each entry holds `qualification`, the user's `credential` (or `nil`) and
  the lists `met` and `open`. Each requirement carries `kind`,
  `target_key` and `station_position`: the position of the station that
  satisfies it (the module station for a module or its exam, the station of
  the companion formats for attendance), or `nil` when no station of the
  program does.
  """
  def requirements(%Scope{user: %User{} = user}, slug) when is_binary(slug) do
    case Catalog.get_published_program(slug) do
      nil ->
        {:error, :not_found}

      program ->
        qualifications = live_qualifications(program.id)
        facts = facts(user.id, program, qualifications)
        credentials = user_credentials_by_qualification(user.id, qualifications)
        stations = station_positions(program.id)

        {:ok,
         for qualification <- qualifications do
           entries =
             qualification.requirements
             |> Enum.sort_by(&{kind_rank(&1.kind), &1.target_key})
             |> Enum.map(&{met?(&1, facts), requirement_entry(&1, stations)})

           %{
             qualification: qualification,
             credential: Map.get(credentials, qualification.id),
             met: for({true, entry} <- entries, do: entry),
             open: for({false, entry} <- entries, do: entry)
           }
         end}
    end
  end

  defp kind_rank(kind), do: Enum.find_index(@kind_order, &(&1 == kind))

  defp user_credentials_by_qualification(user_id, qualifications) do
    ids = Enum.map(qualifications, & &1.id)

    Repo.all(from c in Credential, where: c.user_id == ^user_id and c.qualification_id in ^ids)
    |> Map.new(&{&1.qualification_id, &1})
  end

  # Positions of the module stations by module number and by exam key, and
  # of the station of the companion formats.
  defp station_positions(program_id) do
    modules =
      Repo.all(
        from s in Station,
          join: m in CatalogModule,
          on: m.id == s.module_id,
          where: s.program_id == ^program_id and s.kind == :module,
          select: {m.id, m.number, s.position}
      )

    by_module_id = Map.new(modules, fn {id, _number, position} -> {id, position} end)

    exams =
      Repo.all(
        from a in Assessment,
          where: a.program_id == ^program_id and a.kind == :exam,
          select: {a.key, a.module_id}
      )

    formats =
      Repo.one(
        from s in Station,
          where: s.program_id == ^program_id and s.kind == :companion_formats,
          order_by: s.position,
          limit: 1,
          select: s.position
      )

    %{
      module_completed:
        Map.new(modules, fn {_id, number, position} -> {to_string(number), position} end),
      assessment_passed:
        for {key, module_id} <- exams, Map.has_key?(by_module_id, module_id), into: %{} do
          {key, Map.fetch!(by_module_id, module_id)}
        end,
      attendance: formats
    }
  end

  defp requirement_entry(%Requirement{kind: kind, target_key: key}, stations) do
    position =
      case kind do
        :module_completed -> Map.get(stations.module_completed, key)
        :assessment_passed -> Map.get(stations.assessment_passed, key)
        :attendance -> stations.attendance
        _policy_or_qualification -> nil
      end

    %{kind: kind, target_key: key, station_position: position}
  end

  @doc """
  Returns the credentials of the scope user with their qualification and
  its program, the newest first.
  """
  def list_credentials(%Scope{user: %User{id: user_id}}) do
    Repo.all(
      from c in Credential,
        where: c.user_id == ^user_id,
        order_by: [desc: c.issued_at, asc: c.id],
        preload: [qualification: :program]
    )
  end

  @doc """
  Returns the credential `id` of the scope user with its qualification and
  its program, or `nil` for any other id (ASVS 8.2.2).
  """
  def get_credential(%Scope{user: %User{id: user_id}}, id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        Repo.one(
          from c in Credential,
            where: c.id == ^uuid and c.user_id == ^user_id,
            preload: [qualification: :program]
        )

      :error ->
        nil
    end
  end

  ## Registrar and integration API

  @doc """
  Returns the credentials of the qualifications with `code`, one map per
  credential with `display_name`, `org_unit`, `status`, `issued_at` and
  `valid_until`, ordered by display name (README section 10). Codes are
  unique per program, so a person who holds the code in two programs
  appears once per program. Requires the
  role `registrar` (`{:error, :forbidden}`) and `REGISTRAR_ENABLED=true`
  (`{:error, :not_found}` otherwise).
  """
  def registrar_list(%Scope{} = scope, code) when is_binary(code) do
    cond do
      not Application.get_env(:espalier, :registrar_enabled, false) ->
        {:error, :not_found}

      not Scope.has_role?(scope, :registrar) ->
        {:error, :forbidden}

      true ->
        rows =
          Repo.all(
            from c in Credential,
              join: q in Qualification,
              on: q.id == c.qualification_id,
              join: u in User,
              on: u.id == c.user_id,
              where: q.code == ^code,
              select: {u, c}
          )

        {:ok,
         rows
         |> Enum.map(fn {user, credential} ->
           %{
             display_name: user.display_name,
             org_unit: user.org_unit,
             status: credential.status,
             issued_at: credential.issued_at,
             valid_until: credential.valid_until
           }
         end)
         |> Enum.sort_by(
           &{is_nil(&1.display_name), &1.display_name, DateTime.to_unix(&1.issued_at)}
         )}
    end
  end

  @doc """
  Returns the credentials in force (`active` or `refresh_due`) of the user
  with the address `email`, each with `qualification_code`, `status`,
  `unlocks_snapshot` and `valid_until`, for the integration API (ASVS
  15.3.1). An unknown address returns `[]`.
  """
  def in_force_for_email(email) when is_binary(email) do
    case Accounts.get_user_by_email(email) do
      %User{id: user_id} ->
        statuses = Credential.in_force_statuses()

        Repo.all(
          from c in Credential,
            join: q in Qualification,
            on: q.id == c.qualification_id,
            where: c.user_id == ^user_id and c.status in ^statuses,
            order_by: [q.code, c.issued_at],
            select: %{
              qualification_code: q.code,
              status: c.status,
              unlocks_snapshot: c.unlocks_snapshot,
              valid_until: c.valid_until
            }
        )

      nil ->
        []
    end
  end

  ## Lifecycle

  @doc """
  Moves credentials along the validity period on `today`.

  An `active` credential whose `valid_until` minus `CREDENTIAL_NOTICE_DAYS`
  falls on or before `today` moves to `refresh_due`, with `refresh_due_at`
  now. A `refresh_due` credential whose `valid_until` plus
  `CREDENTIAL_GRACE_DAYS` lies before `today` moves to `expired`. The
  expiry runs first, so one sweep moves a credential by one state. A
  credential without `valid_until` stays where it is. Every transition
  enqueues one mail and the matching webhook events. Returns
  `{:ok, %{refresh_due: moved, expired: moved}}`.
  """
  def sweep(%Date{} = today) do
    Repo.transact(fn ->
      expired =
        from(c in Credential,
          where:
            c.status == :refresh_due and not is_nil(c.valid_until) and
              c.valid_until < ^Date.add(today, -grace_days())
        )
        |> transition(:expired)

      refresh_due =
        from(c in Credential,
          where:
            c.status == :active and not is_nil(c.valid_until) and
              c.valid_until <= ^Date.add(today, notice_days())
        )
        |> transition(:refresh_due)

      {:ok, %{refresh_due: refresh_due, expired: expired}}
    end)
  end

  @doc """
  Moves every `active` credential whose qualification has a
  `policy_acknowledged` requirement on `policy_key` to `refresh_due`, with
  `refresh_due_at` now, and returns `{:ok, moved}`. Every move enqueues one
  mail and the webhook event `credential.refresh_due`.
  """
  def mark_refresh_due_for_policy(policy_key) when is_binary(policy_key) do
    Repo.transact(fn -> {:ok, policy_query(policy_key) |> transition(:refresh_due)} end)
  end

  @doc """
  Returns the number of credentials that `mark_refresh_due_for_policy/1`
  would move now.
  """
  def count_affected_by_policy(policy_key) when is_binary(policy_key) do
    Repo.aggregate(policy_query(policy_key), :count)
  end

  defp policy_query(policy_key) do
    qualification_ids =
      from r in Requirement,
        where: r.kind == :policy_acknowledged and r.target_key == ^policy_key,
        select: r.qualification_id

    from c in Credential,
      where: c.status == :active and c.qualification_id in subquery(qualification_ids)
  end

  # Moves the credentials of `query` to `status` in one statement, then
  # enqueues one mail per credential and the webhook events.
  defp transition(query, status) do
    now = DateTime.utc_now(:second)

    set =
      if status == :refresh_due,
        do: [status: status, refresh_due_at: now, updated_at: now],
        else: [status: status, updated_at: now]

    {_count, moved} = query |> select([c], c) |> Repo.update_all(set: set)

    for credential <- moved do
      {:ok, _job} =
        "credential_#{status}"
        |> MailWorker.job(%{user_id: credential.user_id, credential_id: credential.id})
        |> Oban.insert()

      :ok = enqueue_webhooks("credential.#{status}", credential)
    end

    moved
  end

  @doc """
  Revokes a credential. Requires the role `admin` (`{:error, :forbidden}`
  otherwise). A revoked credential is terminal: a second revocation answers
  `{:error, :already_revoked}`, and `evaluate/2`, `sweep/1` and
  `mark_refresh_due_for_policy/1` leave it unchanged. The revocation writes
  the audit event `credential.revoked` and enqueues the webhook event of
  the same name.
  """
  def revoke(%Scope{} = scope, %Credential{} = credential) do
    if Scope.admin?(scope) do
      Repo.transact(fn -> revoke_in(scope, credential.id) end)
    else
      {:error, :forbidden}
    end
  end

  defp revoke_in(scope, credential_id) do
    case Repo.one(from c in Credential, where: c.id == ^credential_id, lock: "FOR UPDATE") do
      nil ->
        {:error, :not_found}

      %Credential{status: :revoked} ->
        {:error, :already_revoked}

      locked ->
        revoked = locked |> Changeset.change(status: :revoked) |> Repo.update!()

        {:ok, _event} =
          Audit.record(scope, "credential.revoked", revoked, %{previous_status: locked.status})

        :ok = enqueue_webhooks("credential.revoked", revoked)
        {:ok, revoked}
    end
  end

  ## Webhooks

  @doc """
  Inserts one `Espalier.Credentials.WebhookWorker` job per active webhook
  subscribed to `event`. The job arguments carry ids, the event and the time
  of the event only.
  """
  def enqueue_webhooks(event, %Credential{} = credential) when is_binary(event) do
    occurred_at = DateTime.utc_now(:second) |> DateTime.to_iso8601()

    jobs =
      Repo.all(from w in Webhook, where: w.active and ^event in w.events, select: w.id)
      |> Enum.map(fn webhook_id ->
        WebhookWorker.new(%{
          webhook_id: webhook_id,
          event: event,
          credential_id: credential.id,
          occurred_at: occurred_at
        })
      end)

    _jobs = Oban.insert_all(jobs)
    :ok
  end

  ## Settings

  defp notice_days, do: Application.get_env(:espalier, :credential_notice_days, 30)
  defp grace_days, do: Application.get_env(:espalier, :credential_grace_days, 30)
end
