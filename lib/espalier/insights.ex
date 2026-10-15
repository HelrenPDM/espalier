defmodule Espalier.Insights do
  @moduledoc """
  Anonymous insights and the reports for analysts (README sections 7 and
  10, task 0014).

  The anonymous tables `item_stats`, `self_assessment_responses`,
  `interest_votes` and `feedback_responses` carry no user key, a random
  primary key and only a date with day precision. A
  `Espalier.Insights.ParticipationMarker` records that a person has
  answered, so that each person counts once (`record_once/3`). No query
  joins a marker with an anonymous row, and no report reads the markers.

  The report functions require the role `analyst` and return cells built by
  `cell/2`: `%{count: count, value: value}`, or `%{suppressed: true}` when
  the count lies below `INSIGHTS_MIN_GROUP_SIZE`. Every report also carries
  that threshold as `min_group_size`. The reports cover the
  anonymous rows and the count of credentials per qualification and status;
  no report returns a user id, a display name or a row per person, and no
  report returns the total of a column, so that a total minus the shown
  cells cannot reveal a suppressed one.
  """

  import Ecto.Query, warn: false

  alias Espalier.Accounts.{Scope, User}
  alias Espalier.Catalog

  alias Espalier.Catalog.{
    CompanionFormat,
    Item,
    LearningObjective,
    Program,
    Qualification,
    Segment,
    Station
  }

  alias Espalier.Credentials.Credential

  alias Espalier.Insights.{
    FeedbackResponse,
    InterestVote,
    ItemStat,
    ParticipationMarker,
    SelfAssessmentResponse
  }

  alias Espalier.Learning
  alias Espalier.Repo

  # The length of `item_stats.org_unit`, a varchar(255) column, in code points.
  @org_unit_length 255

  # The longest free-text answer of the feedback station, in characters.
  @free_text_length 2_000

  @credential_statuses [:active, :refresh_due, :expired, :revoked]

  ## Settings

  @doc """
  The settings of `config :espalier, :insights`, which
  `Espalier.RuntimeConfig` parses from the environment (task 0014, step 10).
  """
  @spec settings() :: keyword()
  def settings, do: Application.get_env(:espalier, :insights, [])

  @doc "The value of `INSIGHTS_MIN_GROUP_SIZE` (default 5)."
  @spec min_group_size() :: pos_integer()
  def min_group_size, do: Keyword.get(settings(), :min_group_size, 5)

  @doc "True with `FEEDBACK_FREE_TEXT=true`."
  @spec feedback_free_text?() :: boolean()
  def feedback_free_text?, do: Keyword.get(settings(), :feedback_free_text, false)

  @doc "True with `TEST_NOTES=true`."
  @spec test_notes?() :: boolean()
  def test_notes?, do: Keyword.get(settings(), :test_notes, false)

  @doc "The longest free-text answer of the feedback station, in characters."
  @spec free_text_length() :: pos_integer()
  def free_text_length, do: @free_text_length

  ## Item statistics (task 0009)

  @doc """
  Returns the org unit of a user in the form that the anonymous rows store:
  the trimmed value cut to 255 code points, or `nil` for a missing or blank
  value and for one that is no valid UTF-8 or holds U+0000. The org unit
  comes from the directory without a length bound (task 0007), and two
  values that differ only after 255 code points share one counter.
  """
  @spec org_unit(term()) :: String.t() | nil
  def org_unit(value) when is_binary(value) do
    trimmed = if String.valid?(value), do: String.trim(value), else: ""

    if trimmed == "" or String.contains?(trimmed, <<0>>) do
      nil
    else
      trimmed |> String.codepoints() |> Enum.take(@org_unit_length) |> Enum.join()
    end
  end

  def org_unit(_value), do: nil

  @doc """
  Counts one practice answer to `item_id` in the counter of the month of
  `today`: `attempts` grows by 1, and `correct` by 1 when `correct` is
  `true`. `org_unit` is `nil` unless `INSIGHTS_ORG_UNIT=true`; all answers
  without an org unit share one counter per item and month.
  """
  @spec count_item_answer(Ecto.UUID.t(), boolean() | nil, String.t() | nil, Date.t()) :: :ok
  def count_item_answer(item_id, correct, org_unit, today \\ Date.utc_today()) do
    increment = if correct == true, do: 1, else: 0

    Repo.insert!(
      ItemStat.changeset(%ItemStat{
        item_id: item_id,
        period: Date.beginning_of_month(today),
        org_unit: org_unit,
        attempts: 1,
        correct: increment
      }),
      on_conflict: [inc: [attempts: 1, correct: increment]],
      conflict_target: [:item_id, :period, :org_unit]
    )

    :ok
  end

  ## Participation

  @doc """
  Records an anonymous answer once per person and subject.

  `subject` is `{subject_type, subject_id}`: `{:self_assessment,
  program_id}`, `{:format_vote, format_id}` or `{:feedback, program_id}`.
  In one transaction, the function inserts the participation marker of the
  scope user with `Repo.insert_all/3` and `on_conflict: :nothing`. A count
  of 1 means the marker is new: `fun` inserts the anonymous row, and its
  result, `{:ok, value}` or `{:error, reason}`, is returned; an error rolls
  the marker back. A count of 0 means the marker existed, and the function
  returns `{:ok, :already_recorded}` without calling `fun`.

  `Repo.insert/2` with `on_conflict: :nothing` returns `{:ok, struct}` with
  a client-generated id in both cases, so it cannot tell the two cases
  apart.
  """
  @spec record_once(Scope.t(), {atom(), Ecto.UUID.t()}, (-> {:ok, term()} | {:error, term()})) ::
          {:ok, term()} | {:error, term()}
  def record_once(%Scope{user: %User{id: user_id}}, {subject_type, subject_id}, fun)
      when subject_type in [:self_assessment, :format_vote, :feedback] and is_function(fun, 0) do
    row = %{user_id: user_id, subject_type: subject_type, subject_id: subject_id}

    Repo.transact(fn ->
      case Repo.insert_all(ParticipationMarker, [row],
             on_conflict: :nothing,
             conflict_target: [:user_id, :subject_type, :subject_id]
           ) do
        {1, _rows} -> fun.()
        {0, _rows} -> {:ok, :already_recorded}
      end
    end)
  end

  @doc """
  Records the self-assessment of the scope user in the published program
  `slug`: the key of a live segment of the program (README section 7,
  domain rule 1).

  For a new answer, the function stores the anonymous row and calls
  `Espalier.Learning.apply_default_path/3` with the segment's default path,
  both in the transaction of `record_once/3`. It returns
  `{:ok, %{path: path, already_recorded: false}}` with the path of the
  enrollment afterwards. For an answer that was already recorded, the
  enrollment stays unchanged and the function returns its path with
  `already_recorded: true` (`path` is `nil` without an enrollment).

  An unknown or unpublished program answers `{:error, :not_found}`, and a
  key that names no live segment of the program
  `{:error, {:validation_failed, "segment_key", "invalid"}}`.
  """
  def record_self_assessment(%Scope{} = scope, slug, segment_key)
      when is_binary(slug) and is_binary(segment_key) do
    with %Program{} = program <- Catalog.get_published_program(slug) || {:error, :not_found},
         %Segment{} = segment <-
           live_segment(program, segment_key) ||
             {:error, {:validation_failed, "segment_key", "invalid"}} do
      result =
        record_once(scope, {:self_assessment, program.id}, fn ->
          {:ok, _row} =
            %SelfAssessmentResponse{
              program_id: program.id,
              segment_key: segment.key,
              org_unit: anonymous_org_unit(scope),
              recorded_on: Date.utc_today()
            }
            |> SelfAssessmentResponse.changeset()
            |> Repo.insert()

          Learning.apply_default_path(scope, program, segment.default_path)
        end)

      case result do
        {:ok, :already_recorded} ->
          enrollment = Learning.get_enrollment(scope, program.id)
          {:ok, %{path: enrollment && enrollment.path, already_recorded: true}}

        {:ok, enrollment} ->
          {:ok, %{path: enrollment.path, already_recorded: false}}

        {:error, _reason} = error ->
          error
      end
    end
  end

  defp live_segment(program, key) do
    Repo.one(
      from s in Segment,
        where: s.program_id == ^program.id and s.key == ^key and is_nil(s.archived_at)
    )
  end

  defp anonymous_org_unit(%Scope{user: user}) do
    if Learning.insights_org_unit?(), do: org_unit(user.org_unit)
  end

  @doc """
  Records the "would use" vote of the scope user for a live companion
  format of a published program (README section 7, domain rule 11). The
  only choice is `"would_use"`. Returns `{:ok, %{already_recorded:
  boolean}}`; a vote cannot be changed afterwards. An unknown or archived
  format, or one of a program that is not published, answers
  `{:error, :not_found}`.
  """
  def vote_format(%Scope{} = scope, format_id, "would_use") do
    with %CompanionFormat{} = format <- live_format(format_id) || {:error, :not_found} do
      scope
      |> record_once({:format_vote, format.id}, fn ->
        %InterestVote{
          companion_format_id: format.id,
          choice: :would_use,
          recorded_on: Date.utc_today()
        }
        |> InterestVote.changeset()
        |> Repo.insert()
      end)
      |> recorded()
    end
  end

  defp live_format(id) do
    Repo.one(
      from f in CompanionFormat,
        join: p in assoc(f, :program),
        where: f.id == ^id and is_nil(f.archived_at) and p.status == :published
    )
  end

  @doc """
  Records the answers of the scope user to the feedback station of the
  published program `slug` (README section 7, domain rule 12).

  `answers` maps question keys of the station to answers: an option key
  for a `single_choice` question, an integer from 1 to 5 for a `scale`
  question, and a text for a `free_text` question. Free text is accepted
  only with `FEEDBACK_FREE_TEXT=true`, is valid UTF-8, is trimmed and holds
  from 1 to 2,000 code points and no U+0000. At least one question must be answered; a
  question may stay unanswered. Any other input answers
  `{:error, {:validation_failed, "answers", "invalid"}}`.

  Returns `{:ok, %{already_recorded: boolean}}`. A program that is not
  published, or that has no feedback station, answers
  `{:error, :not_found}`.
  """
  def record_feedback(%Scope{} = scope, slug, answers) when is_binary(slug) and is_map(answers) do
    with %Program{} = program <- Catalog.get_published_program(slug) || {:error, :not_found},
         %Station{} = station <- feedback_station(program) || {:error, :not_found},
         {:ok, answers} <- check_feedback(questions(station), answers) do
      scope
      |> record_once({:feedback, program.id}, fn ->
        %FeedbackResponse{program_id: program.id, answers: answers, recorded_on: Date.utc_today()}
        |> FeedbackResponse.changeset()
        |> Repo.insert()
      end)
      |> recorded()
    end
  end

  defp recorded({:ok, :already_recorded}), do: {:ok, %{already_recorded: true}}
  defp recorded({:ok, _row}), do: {:ok, %{already_recorded: false}}
  defp recorded({:error, _reason} = error), do: error

  defp feedback_station(program) do
    Repo.one(
      from s in Station,
        where: s.program_id == ^program.id and s.kind == :feedback,
        order_by: s.position,
        limit: 1
    )
  end

  # The questions of the feedback station, as the validator stores them in
  # its config (Espalier.Catalog.Pack.Schema.Feedback).
  defp questions(%Station{config: config}) do
    case config do
      %{"questions" => questions} when is_list(questions) -> Enum.filter(questions, &is_map/1)
      _other -> []
    end
  end

  defp check_feedback(questions, answers) do
    by_key = Map.new(questions, &{&1["key"], &1})

    checked =
      Enum.map(answers, fn {key, answer} ->
        key = to_string(key)
        {key, check_answer(Map.get(by_key, key), answer)}
      end)

    if checked != [] and Enum.all?(checked, fn {_key, result} -> match?({:ok, _}, result) end) do
      {:ok, Map.new(checked, fn {key, {:ok, answer}} -> {key, answer} end)}
    else
      {:error, {:validation_failed, "answers", "invalid"}}
    end
  end

  defp check_answer(%{"kind" => "single_choice", "options" => options}, answer)
       when is_binary(answer) and is_list(options) do
    if Enum.any?(options, &(is_map(&1) and &1["key"] == answer)), do: {:ok, answer}, else: :error
  end

  defp check_answer(%{"kind" => "scale"}, answer) when is_integer(answer) and answer in 1..5,
    do: {:ok, answer}

  # The limit counts code points, which bounds the size of a stored answer:
  # a single grapheme can carry any number of combining marks. A textarea
  # with maxlength 2000 counts UTF-16 code units, of which a text has at
  # least as many as code points.
  defp check_answer(%{"kind" => "free_text"}, answer) when is_binary(answer) do
    text = if String.valid?(answer), do: String.trim(answer), else: ""

    if feedback_free_text?() and text != "" and not String.contains?(text, <<0>>) and
         length(String.codepoints(text)) <= @free_text_length,
       do: {:ok, text},
       else: :error
  end

  defp check_answer(_question, _answer), do: :error

  @doc """
  Returns what the scope user has answered in the published program
  `slug`: `%{self_assessment: boolean, feedback: boolean, format_votes:
  [format_id]}` with the ids of the live formats of the program that the
  user voted for, in format order. The map comes from the participation
  markers alone: it holds no self-assessment segment and no feedback
  answer, and since a vote has the single choice `would_use`, the format
  ids are the user's own votes. An unknown or unpublished program
  answers `{:error, :not_found}`.
  """
  def participation(%Scope{user: %User{id: user_id}}, slug) when is_binary(slug) do
    with %Program{} = program <- Catalog.get_published_program(slug) || {:error, :not_found} do
      formats =
        Repo.all(
          from f in CompanionFormat,
            where: f.program_id == ^program.id and is_nil(f.archived_at),
            order_by: [f.position, f.key],
            select: f.id
        )

      markers =
        Repo.all(
          from m in ParticipationMarker,
            where:
              m.user_id == ^user_id and
                ((m.subject_type in [:self_assessment, :feedback] and m.subject_id == ^program.id) or
                   (m.subject_type == :format_vote and m.subject_id in ^formats)),
            select: {m.subject_type, m.subject_id}
        )
        |> MapSet.new()

      {:ok,
       %{
         self_assessment: MapSet.member?(markers, {:self_assessment, program.id}),
         feedback: MapSet.member?(markers, {:feedback, program.id}),
         format_votes: Enum.filter(formats, &MapSet.member?(markers, {:format_vote, &1}))
       }}
    end
  end

  ## Reports

  @doc """
  The cell of a report: `%{count: count, value: value}`, or
  `%{suppressed: true}` when `count` lies below `INSIGHTS_MIN_GROUP_SIZE`.
  Every report builds its cells through this function, so neither the
  count nor the value of a small group leaves the server.
  """
  @spec cell(non_neg_integer(), number()) ::
          %{count: pos_integer(), value: number()} | %{suppressed: true}
  def cell(count, value) when is_integer(count) do
    if count >= min_group_size(), do: %{count: count, value: value}, else: %{suppressed: true}
  end

  # A cell of a count report, whose value repeats the count.
  defp count_cell(count), do: cell(count, count)

  # A cell of a share report: the count is the number of attempts and the
  # value the share correct from 0 to 1.
  defp share_cell(attempts, correct) do
    value = if attempts > 0, do: Float.round(correct / attempts, 4), else: 0.0
    cell(attempts, value)
  end

  # Runs a report for an analyst on the program `slug` in any status, so
  # that the data of an archived program stays readable. The role check
  # comes first, so a learner learns nothing about the slug.
  defp report(%Scope{} = scope, slug, fun) when is_binary(slug) do
    cond do
      not Scope.has_role?(scope, :analyst) ->
        {:error, :forbidden}

      program = Catalog.get_program_by_slug(slug) ->
        {:ok, with_program_facts(fun.(program), program)}

      true ->
        {:error, :not_found}
    end
  end

  # Every report names the threshold, so that the SPA can render a
  # suppressed cell as "fewer than N", and the content language of the
  # program, which the list of published programs lacks for an archived one.
  defp with_program_facts(report, program),
    do: Map.merge(report, %{min_group_size: min_group_size(), locale: program.locale})

  defp shown?(%{suppressed: true}), do: false
  defp shown?(_cell), do: true

  # The months of the results in ascending order.
  defp months(results), do: results |> Enum.map(& &1.month) |> Enum.uniq() |> Enum.sort(Date)

  # One cell per month in the order of `months`; a month without a result
  # has the count 0 and is suppressed.
  defp month_cells(months, by_month, fun) do
    Enum.map(months, fn month -> fun.(Map.get(by_month, month)) end)
  end

  # nil sorts after every org unit.
  defp org_unit_order(nil), do: {1, ""}
  defp org_unit_order(org_unit), do: {0, org_unit}

  @doc """
  The distribution of the self-assessment segments of the program `slug`
  by month, and by org unit when `INSIGHTS_ORG_UNIT=true`.

  Returns `{:ok, %{by_org_unit: boolean, months: [Date.t()], rows: [row]}}`.
  Once any answer exists, every live segment of the program has a row (per
  org unit with answers when `by_org_unit`), so that a missing row tells
  nothing: a segment without answers and one with fewer answers than the
  threshold both show suppressed cells. An archived segment, and a key the
  program has no segment for, has a row only when one of its cells is
  shown. The rows follow the segment order of the program (live segments by
  position, then archived ones, then unknown keys) and then the org units,
  `nil` last. A row holds `segment_key`, `label` (`nil` for a key without a
  segment), `org_unit` (`nil` unless `by_org_unit`) and one cell per entry of
  `months`, whose count and value are the number of answers. With the
  setting false, answers stored while it was true sum into one row per
  segment. A scope without `analyst` answers `{:error, :forbidden}`, an
  unknown program `{:error, :not_found}`.
  """
  def self_assessment_report(%Scope{} = scope, slug) do
    report(scope, slug, fn program ->
      by_org_unit = Learning.insights_org_unit?()

      query =
        from r in SelfAssessmentResponse,
          where: r.program_id == ^program.id,
          group_by: [r.segment_key, selected_as(:month)],
          select: %{
            key: r.segment_key,
            month: selected_as(fragment("date_trunc('month', ?)::date", r.recorded_on), :month),
            count: count(r.id)
          }

      query =
        if by_org_unit,
          do: from(r in query, group_by: r.org_unit, select_merge: %{org_unit: r.org_unit}),
          else: from(r in query, select_merge: %{org_unit: nil})

      results = Repo.all(query)
      months = months(results)
      counts = Map.new(results, &{{&1.key, &1.org_unit, &1.month}, &1.count})
      segments = program_segments(program)
      known = MapSet.new(segments, & &1.key)

      unknown =
        for %{key: key} <- results, not MapSet.member?(known, key), uniq: true do
          %{key: key, label: nil, archived_at: :unknown}
        end

      org_units =
        if by_org_unit,
          do:
            results |> Enum.map(& &1.org_unit) |> Enum.uniq() |> Enum.sort_by(&org_unit_order/1),
          else: [nil]

      # Without any answer there are no months and no rows.
      candidates = if months == [], do: [], else: segments ++ Enum.sort_by(unknown, & &1.key)

      rows =
        for segment <- candidates,
            org_unit <- org_units,
            cells = Enum.map(months, &count_cell(Map.get(counts, {segment.key, org_unit, &1}, 0))),
            is_nil(segment.archived_at) or Enum.any?(cells, &shown?/1) do
          %{segment_key: segment.key, label: segment.label, org_unit: org_unit, cells: cells}
        end

      %{by_org_unit: by_org_unit, months: months, rows: rows}
    end)
  end

  # The segments of the program, each key once: live segments by position,
  # then archived ones.
  defp program_segments(program) do
    Repo.all(
      from s in Segment,
        where: s.program_id == ^program.id,
        order_by: [fragment("? IS NOT NULL", s.archived_at), s.position, s.key]
    )
    |> Enum.uniq_by(& &1.key)
  end

  @doc """
  The attempts and the share correct per item of the program `slug` and
  month, from `item_stats` (task 0009).

  Returns `{:ok, %{months: [Date.t()], rows: [row]}}` with one row per live
  item of a live module that has statistics, ordered by module number,
  item position and key. A row holds `item_id`, `key`, `kind`,
  `module_number`, `stem` and one cell per month: the count is the sum of
  `attempts` over all org units, and the value the share correct. Polls
  stay out, because they have no correct answer. A scope without `analyst`
  answers `{:error, :forbidden}`, an unknown program `{:error, :not_found}`.
  """
  def item_report(%Scope{} = scope, slug) do
    report(scope, slug, fn program ->
      results =
        Repo.all(
          from s in ItemStat,
            join: i in Item,
            on: i.id == s.item_id,
            join: m in assoc(i, :module),
            where:
              i.program_id == ^program.id and is_nil(i.archived_at) and is_nil(m.archived_at) and
                i.kind != ^:poll,
            group_by: [i.id, m.number, s.period],
            select: %{
              item: i,
              module_number: m.number,
              month: s.period,
              attempts: sum(s.attempts),
              correct: sum(s.correct)
            }
        )

      months = months(results)

      rows =
        results
        |> Enum.group_by(& &1.item.id)
        |> Enum.map(fn {_id, [first | _] = entries} ->
          by_month = Map.new(entries, &{&1.month, &1})

          %{
            item_id: first.item.id,
            key: first.item.key,
            kind: first.item.kind,
            module_number: first.module_number,
            stem: first.item.stem,
            position: first.item.position,
            cells: month_cells(months, by_month, &stat_cell/1)
          }
        end)
        |> Enum.sort_by(&{&1.module_number, &1.position, &1.key})
        |> Enum.map(&Map.delete(&1, :position))

      %{months: months, rows: rows}
    end)
  end

  defp stat_cell(nil), do: share_cell(0, 0)
  defp stat_cell(%{attempts: attempts, correct: correct}), do: share_cell(attempts, correct)

  @doc """
  The share correct of the items of the program `slug`, grouped by the
  competence area and the depth of the learning objectives that the items
  name through `item_objectives`, by month, and by org unit when
  `INSIGHTS_ORG_UNIT=true` (README section 7, domain rule 15).

  An item has no area and no depth of its own (task 0008), so the function
  reads both only through `item_objectives` and `learning_objectives`. A
  subquery selects the distinct triples of item id, objective area and
  objective depth of the program's live items and live objectives, each of
  a live module, without polls: an item that names two objectives of the
  same area and depth counts once in that group, and an item that names
  objectives of two areas or two depths counts in the group of each. The
  query joins `item_stats` on the item id and groups by item, area, depth
  and `period`, and by `org_unit` only when the setting is true; the
  function then sums the items of each cell.

  The item report shows the attempts of each item per month, so a cell
  would reveal a suppressed item cell, or a suppressed org-unit cell, by
  difference or by the bounds of the suppressed cells. Beyond `cell/2`, an
  item and month is therefore suppressed when the item has fewer than
  `INSIGHTS_MIN_GROUP_SIZE` attempts in one org unit of that month (without
  the breakdown: in that month), and every cell of each area and depth that
  a suppressed item names is suppressed in that month, in every org unit.
  Whether a cell is suppressed then never depends on the org units a
  suppressed item reached, a shown cell holds only attempt counts at or
  above the threshold, and about a suppressed item a reader learns no more
  than its item total and that the month had attempts of it. With the
  breakdown, each area and depth has a row for every org unit that has a
  shown cell somewhere in the report, so a suppressed cell may also hold no
  attempt, and neither a row nor a missing row tells which org units a
  suppressed item reached.

  Returns `{:ok, %{by_org_unit: boolean, months: [Date.t()], rows: [row]}}`.
  A row holds `area`, `depth`, `org_unit` and one cell per month, whose
  count is the sum of `attempts` and whose value is the share correct. The
  rows follow the order of the areas (`subject`, `method`, `self`,
  `social`), then of the depths (`know`, `apply`, `judge`), then of the org
  units, `nil` last. A combination of area and depth without statistics has
  no row. A scope
  without `analyst` answers `{:error, :forbidden}`, an unknown program
  `{:error, :not_found}`.
  """
  def competence_report(%Scope{} = scope, slug) do
    report(scope, slug, fn program ->
      by_org_unit = Learning.insights_org_unit?()

      links =
        from i in Item,
          join: im in assoc(i, :module),
          join: o in assoc(i, :objectives),
          join: om in assoc(o, :module),
          where:
            i.program_id == ^program.id and is_nil(i.archived_at) and is_nil(im.archived_at) and
              is_nil(o.archived_at) and is_nil(om.archived_at) and i.kind != ^:poll,
          distinct: true,
          select: %{item_id: i.id, area: o.area, depth: o.depth}

      query =
        from l in subquery(links),
          join: s in ItemStat,
          on: s.item_id == l.item_id,
          group_by: [l.item_id, l.area, l.depth, s.period],
          select: %{
            item_id: l.item_id,
            area: l.area,
            depth: l.depth,
            month: s.period,
            attempts: sum(s.attempts),
            correct: sum(s.correct)
          }

      query =
        if by_org_unit,
          do: from([l, s] in query, group_by: s.org_unit, select_merge: %{org_unit: s.org_unit}),
          else: from(query, select_merge: %{org_unit: nil})

      results = Repo.all(query)
      months = months(results)
      cells = competence_cells(results)
      areas = LearningObjective |> Ecto.Enum.values(:area) |> Enum.with_index() |> Map.new()
      depths = LearningObjective |> Ecto.Enum.values(:depth) |> Enum.with_index() |> Map.new()

      groups =
        results
        |> Enum.map(&{&1.area, &1.depth})
        |> Enum.uniq()
        |> Enum.sort_by(fn {area, depth} ->
          {Map.fetch!(areas, area), Map.fetch!(depths, depth)}
        end)

      org_units = competence_org_units(cells, by_org_unit)

      rows =
        for {area, depth} <- groups, org_unit <- org_units do
          %{
            area: area,
            depth: depth,
            org_unit: org_unit,
            cells:
              Enum.map(
                months,
                &Map.get(cells, {area, depth, org_unit, &1}, %{suppressed: true})
              )
          }
        end

      %{by_org_unit: by_org_unit, months: months, rows: rows}
    end)
  end

  # With the breakdown, an org unit has rows only when one of its cells is
  # shown: a unit listed for its suppressed cells alone would tell that a
  # suppressed item reached it.
  defp competence_org_units(_cells, false), do: [nil]

  defp competence_org_units(cells, true) do
    for(
      {{_area, _depth, org_unit, _month}, cell} <- cells,
      shown?(cell),
      uniq: true,
      do: org_unit
    )
    |> Enum.sort_by(&org_unit_order/1)
  end

  # The cells of the competence report by area, depth, org unit and month,
  # from the attempts that each item contributes to them (see
  # competence_report/2): an item and month with fewer attempts than the
  # threshold in one org unit suppresses every cell of each area and depth
  # it names in that month, in every org unit, and any other cell is shown
  # when its sum reaches the threshold.
  defp competence_cells(results) do
    threshold = min_group_size()

    suppressed =
      for %{attempts: attempts} = row <- results,
          attempts < threshold,
          into: MapSet.new(),
          do: {row.item_id, row.month}

    hidden_columns =
      for row <- results,
          MapSet.member?(suppressed, {row.item_id, row.month}),
          into: MapSet.new(),
          do: {row.area, row.depth, row.month}

    results
    |> Enum.group_by(&{&1.area, &1.depth, &1.org_unit, &1.month})
    |> Map.new(fn {{area, depth, _org_unit, month} = key, items} ->
      attempts = Enum.sum_by(items, & &1.attempts)

      if attempts >= threshold and not MapSet.member?(hidden_columns, {area, depth, month}),
        do: {key, share_cell(attempts, Enum.sum_by(items, & &1.correct))},
        else: {key, %{suppressed: true}}
    end)
  end

  @doc """
  The "would use" count per live companion format of the program `slug`,
  from `interest_votes`, in format order.

  Returns `{:ok, %{formats: [row]}}`; a row holds `id`, `key`, `title` and
  one cell, whose count and value are the number of votes. A scope without
  `analyst` answers `{:error, :forbidden}`, an unknown program
  `{:error, :not_found}`.
  """
  def format_report(%Scope{} = scope, slug) do
    report(scope, slug, fn program ->
      formats =
        Repo.all(
          from f in CompanionFormat,
            left_join: v in InterestVote,
            on: v.companion_format_id == f.id and v.choice == ^:would_use,
            where: f.program_id == ^program.id and is_nil(f.archived_at),
            group_by: f.id,
            order_by: [f.position, f.key],
            select: {f, count(v.id)}
        )

      %{
        formats:
          Enum.map(formats, fn {format, votes} ->
            %{id: format.id, key: format.key, title: format.title, cell: count_cell(votes)}
          end)
      }
    end)
  end

  @doc """
  The choice and scale distributions of the feedback station of the
  program `slug`, and its free-text answers.

  Returns `{:ok, %{questions: [question]}}` with the questions of the
  station in their order. A question holds `key`, `kind`, `label`,
  `choices` and `free_text`. For a `single_choice` question, `choices` has
  one entry per option (`key`, `label` and a cell with the number of
  answers), and for a `scale` question one entry per value from 1 to 5
  (`key` `"1"` to `"5"`, `label` `nil`). For a `free_text` question,
  `choices` is empty and `free_text` holds `%{count: n, answers: [text]}`
  in random order when the number of its answers reaches
  `INSIGHTS_MIN_GROUP_SIZE`, and `%{suppressed: true}` otherwise; for the
  other kinds it is `nil`. The answers of one question are listed apart
  from those of every other question. A program without a feedback station
  has no questions. A scope without `analyst` answers
  `{:error, :forbidden}`, an unknown program `{:error, :not_found}`.
  """
  def feedback_report(%Scope{} = scope, slug) do
    report(scope, slug, fn program ->
      questions =
        case feedback_station(program) do
          nil -> []
          station -> questions(station)
        end

      answers =
        Repo.all(
          from r in FeedbackResponse, where: r.program_id == ^program.id, select: r.answers
        )

      %{questions: Enum.map(questions, &question_report(&1, answers))}
    end)
  end

  defp question_report(%{"key" => key, "kind" => kind} = question, answers) do
    given = for %{^key => answer} <- answers, do: answer

    %{
      key: key,
      kind: kind,
      label: question["label"],
      choices: choices(question, given),
      free_text: free_text(kind, given)
    }
  end

  defp choices(%{"kind" => "single_choice", "options" => options}, given) when is_list(options) do
    counts = Enum.frequencies(given)

    for %{"key" => key} = option <- options do
      %{key: key, label: option["label"], cell: count_cell(Map.get(counts, key, 0))}
    end
  end

  defp choices(%{"kind" => "scale"}, given) do
    counts = Enum.frequencies(given)

    for value <- 1..5 do
      %{key: Integer.to_string(value), label: nil, cell: count_cell(Map.get(counts, value, 0))}
    end
  end

  defp choices(_question, _given), do: []

  defp free_text("free_text", given) do
    texts = Enum.filter(given, &is_binary/1)
    count = length(texts)

    if count >= min_group_size(),
      do: %{count: count, answers: Enum.shuffle(texts)},
      else: %{suppressed: true}
  end

  defp free_text(_kind, _given), do: nil

  @doc """
  The count of credentials per qualification of the program `slug` and
  status (`active`, `refresh_due`, `expired`, `revoked`), from
  `credentials` (task 0013).

  Returns `{:ok, %{qualifications: [row]}}` with the live qualifications
  ordered by position and code, followed by archived qualifications with
  at least one shown cell in the same order, so that the presence of an
  archived qualification reveals no count below the threshold. A row holds
  `code`, `title`, `archived` and one entry per status with `status` and a
  cell, whose count and value are the number of credentials. A scope
  without `analyst` answers `{:error, :forbidden}`, an unknown program
  `{:error, :not_found}`.
  """
  def credential_report(%Scope{} = scope, slug) do
    report(scope, slug, fn program ->
      counts =
        Repo.all(
          from c in Credential,
            join: q in Qualification,
            on: q.id == c.qualification_id,
            where: q.program_id == ^program.id,
            group_by: [c.qualification_id, c.status],
            select: {c.qualification_id, c.status, count(c.id)}
        )
        |> Map.new(fn {id, status, count} -> {{id, status}, count} end)

      qualifications =
        Repo.all(
          from q in Qualification,
            where: q.program_id == ^program.id,
            order_by: [fragment("? IS NOT NULL", q.archived_at), q.position, q.code]
        )

      rows =
        for qualification <- qualifications,
            statuses = status_cells(counts, qualification),
            is_nil(qualification.archived_at) or Enum.any?(statuses, &shown?(&1.cell)) do
          %{
            code: qualification.code,
            title: qualification.title,
            archived: not is_nil(qualification.archived_at),
            statuses: statuses
          }
        end

      %{qualifications: rows}
    end)
  end

  defp status_cells(counts, qualification) do
    for status <- @credential_statuses do
      %{status: status, cell: count_cell(Map.get(counts, {qualification.id, status}, 0))}
    end
  end
end
