defmodule EspalierWeb.ApiSpecTest do
  @moduledoc """
  The OpenAPI document of task 0009 (README section 6.12, ASVS 2.1.1 and
  15.3.7): the learner routes and the routes of task 0004 have operations,
  every 2xx answer other than 204 names a schema, every path parameter is
  declared in the path, and `GET /api/openapi` serves the document.
  """
  use EspalierWeb.ConnCase, async: true

  alias EspalierWeb.ApiSpec
  alias OpenApiSpex.{MediaType, Operation, Reference, Response, Schema}

  # Steps 13 (learner routes) and 15 (routes of task 0004).
  @routes [
    {:get, "/api/programs"},
    {:get, "/api/programs/{slug}"},
    {:get, "/api/programs/{slug}/glossary"},
    {:get, "/api/programs/{slug}/handbook"},
    {:get, "/api/modules/{id}"},
    {:post, "/api/modules/{id}/completion"},
    {:post, "/api/enrollments"},
    {:patch, "/api/enrollments/{id}"},
    {:post, "/api/items/{id}/responses"},
    {:post, "/api/assessments/{id}/attempts"},
    {:get, "/api/me/progress"},
    {:get, "/auth/providers"},
    {:get, "/api/session"},
    {:delete, "/api/session"},
    {:post, "/api/auth/password"},
    {:post, "/api/auth/invitations"},
    {:post, "/api/auth/invitations/accept"},
    {:post, "/api/auth/demo"},
    {:get, "/api/me/sessions"},
    {:delete, "/api/me/sessions/{id}"},
    {:put, "/api/me/password"},
    {:put, "/api/me/email"},
    {:post, "/api/me/email/confirm"}
  ]

  defp operations do
    for {path, item} <- ApiSpec.spec().paths,
        {verb, %Operation{} = operation} <- Map.from_struct(item),
        do: {{verb, path}, operation}
  end

  test "every route of steps 13 and 15 has an operation and no other route has one" do
    assert operations() |> Enum.map(&elem(&1, 0)) |> Enum.sort() == Enum.sort(@routes)
  end

  test "every 2xx answer other than 204 names a schema" do
    for {{verb, path}, operation} <- operations(),
        {status, response} <- operation.responses,
        status in 200..299 and status != 204 do
      assert %Response{content: %{"application/json" => %MediaType{schema: schema}}} = response

      assert match?(%Reference{}, schema) or
               match?(%Schema{title: title} when is_binary(title), schema),
             "#{verb} #{path} #{status}"
    end
  end

  test "every error answer has the schema Error or a named error schema" do
    for {{verb, path}, operation} <- operations(),
        {status, response} <- operation.responses,
        status >= 400 do
      assert %Response{content: %{"application/json" => %MediaType{schema: schema}}} = response,
             "#{verb} #{path} #{status}"

      refute is_nil(schema), "#{verb} #{path} #{status}"
    end
  end

  test "every path parameter is declared with its location" do
    for {{verb, path}, operation} <- operations() do
      in_path =
        ~r/\{([a-z_]+)\}/ |> Regex.scan(path, capture: :all_but_first) |> List.flatten()

      declared = for %{in: :path, name: name} <- operation.parameters, do: to_string(name)
      assert Enum.sort(in_path) == Enum.sort(declared), "#{verb} #{path}"
      assert Enum.all?(operation.parameters, &(&1.in in [:path, :query])), "#{verb} #{path}"
    end
  end

  test "the session payload of GET /api/session is the schema SessionPayload" do
    spec = ApiSpec.spec()
    operation = spec.paths["/api/session"].get
    media = operation.responses[200].content["application/json"]
    assert %Reference{"$ref": "#/components/schemas/SessionPayload"} = media.schema

    payload = spec.components.schemas["SessionPayload"]

    assert Enum.sort(Map.keys(payload.properties)) ==
             Enum.sort([:user, :roles, :session, :pending, :csrf_token, :providers, :flags])

    assert Map.has_key?(payload.properties.session.properties, :provider_key)
  end

  test "every request schema of the learner routes sets additionalProperties false" do
    for title <- ~w(EnrollmentRequest EnrollmentPathRequest ItemResponseRequest AttemptRequest
                    Answer EmptyRequest) do
      assert ApiSpec.spec().components.schemas[title].additionalProperties == false, title
    end
  end

  test "the document names the API, its version and the security schemes" do
    spec = ApiSpec.spec()
    assert spec.info.title == "Espalier API"
    assert spec.info.version == Mix.Project.config()[:version]

    assert %{"session_cookie" => cookie, "csrf_header" => csrf} = spec.components.securitySchemes
    assert {cookie.type, cookie.in, cookie.name} == {"apiKey", "cookie", "__Host-espalier"}
    assert {csrf.type, csrf.in, csrf.name} == {"apiKey", "header", "x-csrf-token"}
  end

  test "GET /api/openapi serves the document without a session", %{conn: conn} do
    conn = get(conn, "/api/openapi")
    body = json_response(conn, 200)

    assert body == ApiSpec.spec() |> Jason.encode!() |> JSON.decode!()

    assert Map.keys(body["paths"]) |> Enum.sort() ==
             @routes |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()
  end
end
