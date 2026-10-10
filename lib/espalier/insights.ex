defmodule Espalier.Insights do
  @moduledoc """
  Anonymous insights (README section 10). Rows of this context carry no user
  key, a random primary key and only a date with day precision. Task 0009
  adds the item statistics; task 0014 adds the other anonymous tables, the
  reports and the retention.
  """

  alias Espalier.Insights.ItemStat
  alias Espalier.Repo

  # The length of `item_stats.org_unit`, a varchar(255) column, in code points.
  @org_unit_length 255

  @doc """
  Returns the org unit of a user in the form that `item_stats` stores: the
  trimmed value cut to 255 code points, or `nil` for a missing or blank
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
end
