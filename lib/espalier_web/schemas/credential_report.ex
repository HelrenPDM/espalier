defmodule EspalierWeb.Schemas.CredentialReport do
  @moduledoc "The answer of `GET /api/insights/credentials`."
  require OpenApiSpex

  alias EspalierWeb.Schemas.{Fields, ReportCell}

  OpenApiSpex.schema(
    Map.merge(
      Fields.object(%{
        min_group_size:
          Fields.integer(
            "`INSIGHTS_MIN_GROUP_SIZE`: a cell whose count lies below it is suppressed."
          ),
        locale:
          Fields.string(
            "The content language of the program, which the pack text of the report carries."
          ),
        qualifications:
          Fields.array(
            Fields.object(%{
              code: Fields.string(),
              title: Fields.string(),
              archived:
                Fields.boolean("True for an archived qualification that still has credentials."),
              statuses:
                Fields.array(
                  Fields.object(%{
                    status: Fields.enum(~w(active refresh_due expired revoked)),
                    cell: ReportCell
                  }),
                  "One entry per status, in the order active, refresh_due, expired, revoked."
                )
            }),
            "The live qualifications, then archived ones with credentials."
          )
      }),
      %{
        title: "CredentialReport",
        description: "The number of credentials per qualification and status."
      }
    ),
    struct?: false,
    derive?: false
  )
end
