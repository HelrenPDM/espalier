defmodule EspalierWeb.Schemas.Admin.StaleDraft do
  @moduledoc """
  The 409 answers of the workbench routes (task 0016a, step 9):
  `stale_draft` with the stored `lock_version` when the draft changed since
  the request read it, `draft_limit` with the configured `max_drafts`, and
  the conflicts `path_taken`, `too_many_files`, `draft_too_large` and
  `no_payload` without a further member.
  """
  require OpenApiSpex

  alias EspalierWeb.Schemas.Fields
  alias OpenApiSpex.Schema

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(
        %{
          error:
            Fields.enum(
              ~w(stale_draft path_taken too_many_files draft_too_large draft_limit no_payload)
            ),
          lock_version: %Schema{
            type: :integer,
            minimum: 1,
            description: "For `stale_draft`: the stored version."
          },
          max_drafts: %Schema{
            type: :integer,
            minimum: 1,
            description: "For `draft_limit`: the largest number of drafts."
          }
        },
        optional: [:lock_version, :max_drafts]
      ),
      %{title: "AdminStaleDraft", description: "A conflict with the stored draft."}
    ),
    struct?: false,
    derive?: false
  )
end
