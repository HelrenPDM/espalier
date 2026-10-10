defmodule EspalierWeb.CastErrorRendererTest do
  @moduledoc """
  The renderer of `CastAndValidate` errors: 422 `validation_failed` with the
  first path element as member and the reason as string, without the
  submitted value.
  """
  use ExUnit.Case, async: true

  alias EspalierWeb.CastErrorRenderer
  alias OpenApiSpex.Cast.Error

  test "an unexpected field answers 422 validation_failed with its member and reason" do
    conn = render([%Error{reason: :unexpected_field, name: "user_id", path: ["user_id"]}])

    assert conn.status == 422
    assert [content_type] = Plug.Conn.get_resp_header(conn, "content-type")
    assert content_type =~ "application/json"

    assert JSON.decode!(conn.resp_body) == %{
             "error" => "validation_failed",
             "fields" => %{"user_id" => ["unexpected_field"]}
           }
  end

  test "a nested path names its first element as member" do
    path = ["answers", Ecto.UUID.generate(), "options"]
    conn = render([%Error{reason: :max_items, path: path}])

    assert fields(conn) == %{"answers" => ["max_items"]}
  end

  test "an error without a path has the member body" do
    conn = render([%Error{reason: :invalid_type, path: []}])

    assert fields(conn) == %{"body" => ["invalid_type"]}
  end

  test "two errors on one member are listed once each, other members apart" do
    conn =
      render([
        %Error{reason: :max_length, path: ["answers", Ecto.UUID.generate(), "initials"]},
        %Error{reason: :invalid_enum, path: ["answers", Ecto.UUID.generate(), "options"]},
        %Error{reason: :max_length, path: ["answers", Ecto.UUID.generate(), "initials"]},
        %Error{reason: :missing_field, path: ["path"]}
      ])

    assert fields(conn) == %{
             "answers" => ["max_length", "invalid_enum"],
             "path" => ["missing_field"]
           }
  end

  test "the body never repeats the submitted value" do
    secret = "s3cr3t-Answer-Value-4711"

    conn =
      render([
        %Error{reason: :invalid_enum, path: ["path"], value: secret},
        %Error{reason: :unexpected_field, name: "outcome", path: ["outcome"], value: secret},
        %Error{reason: :max_length, path: ["answers", "x", "initials"], value: secret, length: 5}
      ])

    assert conn.status == 422
    refute conn.resp_body =~ secret
    refute conn.resp_body =~ "s3cr3t"
  end

  defp render(errors) do
    conn = Plug.Test.conn(:post, "/")
    CastErrorRenderer.call(conn, CastErrorRenderer.init(errors))
  end

  defp fields(conn) do
    assert conn.status == 422
    assert %{"error" => "validation_failed", "fields" => fields} = JSON.decode!(conn.resp_body)
    fields
  end
end
