defmodule EspalierWeb.CastErrorRenderer do
  @moduledoc """
  Renders the errors of `OpenApiSpex.Plug.CastAndValidate` as the body that
  task 0004 uses for changeset errors: 422
  `{"error":"validation_failed","fields":{"<member>":["<reason>"]}}`.

  The member is the first element of the error path, and the reason is the
  error reason as a string, for example `unexpected_field`, `missing_field`,
  `invalid_enum` or `max_length`. An error without a path, such as a missing
  or unsupported `content-type` or a body that is no JSON object, has the
  member `body`. The body never repeats the submitted value.
  """
  @behaviour Plug

  import Plug.Conn

  @impl Plug
  def init(errors), do: errors

  @impl Plug
  def call(conn, errors) do
    fields =
      errors
      |> List.wrap()
      |> Enum.group_by(&member/1, &reason/1)
      |> Map.new(fn {member, reasons} -> {member, Enum.uniq(reasons)} end)

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(422, JSON.encode!(%{error: "validation_failed", fields: fields}))
  end

  defp member(%OpenApiSpex.Cast.Error{path: [first | _rest]}), do: to_string(first)
  defp member(_error), do: "body"

  defp reason(%OpenApiSpex.Cast.Error{reason: reason}) when is_atom(reason),
    do: Atom.to_string(reason)

  defp reason(_error), do: "invalid"
end
