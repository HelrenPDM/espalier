defmodule EspalierWeb.ApiSpecTest do
  @moduledoc """
  The OpenAPI document of task 0009 (README section 6.12, ASVS 2.1.1 and
  15.3.7): the learner routes, the routes of task 0004 and, since task 0011,
  the `/api` routes of tasks 0005, 0006 and 0007 have operations, every 2xx
  answer other than 204 names a schema, every path parameter is declared in
  the path, and `GET /api/openapi` serves the document.

  Task 0013 step 15 adds the operations of its ten routes: every request
  schema of its POST routes sets `additionalProperties: false` (ASVS
  15.3.3), and the integration operation alone names the security scheme
  `bearer_token`, which the document declares.

  Task 0014 steps 4 and 8 add the operations of its ten routes, and every
  request schema of its three POST routes sets `additionalProperties:
  false` at the top level (ASVS 2.1.1 and 15.3.3).

  Task 0015 step 10 adds the operations of the admin area under
  `/api/admin`, and every request schema of its POST routes, the multipart
  schema of the pack upload included, sets `additionalProperties: false`
  (ASVS 2.1.1 and 15.3.3). The seeding routes under `/api/dev` have no
  operation.

  Task 0016 step 10 adds the operations of the three export routes: the
  request schema of `POST /api/admin/exports` sets `additionalProperties:
  false` (ASVS 2.1.1 and 15.3.3), and the download answers the zip as
  `application/zip`.

  Task 0016a step 9 adds the operations of the 13 routes of the pack
  workbench: every request schema of its POST, PUT and PATCH routes, the
  multipart schema of the upload of a draft included, sets
  `additionalProperties: false` and the limits of step 3 (a path of at
  most 255 characters, a content of at most 1,048,576 characters, a
  `lock_version` of at least 1), the descriptions of the upload, the file
  create and the file update name the limits of a draft (ASVS 2.1.1, 2.1.3,
  5.1.1 and 15.3.3), and the download answers the zip as
  `application/zip`.

  Task 0018 steps 15 and 16 add the operations of the five routes of the
  media library and the three routes of the media entries of a draft:
  every request schema of their POST and PATCH routes, the multipart schema
  of the media upload included, sets `additionalProperties: false`, and the
  description of the upload names the accepted types, their signatures and
  the limits (ASVS 2.1.1, 2.1.3, 5.1.1 and 15.3.3). The pack upload counts
  every file below `media/` against `max_pack_media`, and the archive start
  of a draft describes its media files and the 409 `media_limit`. The
  check and the import of a draft name the downloads of drafts, which take
  the same two slots.
  """
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Catalog.Pack.Entries
  alias Espalier.Media
  alias EspalierWeb.ApiSpec

  alias OpenApiSpex.{
    MediaType,
    Operation,
    Reference,
    RequestBody,
    Response,
    Schema,
    SecurityScheme
  }

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
    {:post, "/api/me/email/confirm"},
    # Task 0011 step 1: the /api routes of tasks 0005, 0006 and 0007.
    {:post, "/api/auth/passkey/options"},
    {:post, "/api/auth/passkey"},
    {:post, "/api/auth/second-factor"},
    {:post, "/api/auth/recovery/start"},
    {:post, "/api/auth/recovery/verify"},
    {:get, "/api/me/security"},
    {:post, "/api/me/passkeys/options"},
    {:post, "/api/me/passkeys"},
    {:delete, "/api/me/passkeys/{id}"},
    {:post, "/api/me/totp"},
    {:post, "/api/me/totp/confirm"},
    {:delete, "/api/me/totp"},
    {:post, "/api/me/recovery-codes"},
    {:post, "/api/me/reauth"},
    {:post, "/api/auth/finish"},
    {:post, "/api/auth/oidc/{provider}/intents"},
    {:post, "/api/auth/ldap/{provider}"},
    {:post, "/api/me/identities/ldap/{provider}"},
    # Task 0013 step 15: policies, credentials, attendance, the registrar
    # list and the integration API.
    {:get, "/api/policies"},
    {:post, "/api/policy-versions/{id}/acknowledgements"},
    {:get, "/api/approved-tools"},
    {:get, "/api/me/requirements"},
    {:get, "/api/me/credentials"},
    {:get, "/api/me/credentials/{id}"},
    {:post, "/api/formats/{id}/attendance"},
    {:post, "/api/facilitator/user-lookups"},
    {:get, "/api/registrar/credentials"},
    {:post, "/api/integration/credential-lookups"},
    # Task 0014 steps 4 and 8: the anonymous insights of learners and the
    # reports for analysts.
    {:post, "/api/self-assessments"},
    {:post, "/api/formats/{id}/votes"},
    {:post, "/api/feedback"},
    {:get, "/api/me/participation"},
    {:get, "/api/insights/self-assessment"},
    {:get, "/api/insights/items"},
    {:get, "/api/insights/competence"},
    {:get, "/api/insights/formats"},
    {:get, "/api/insights/feedback"},
    {:get, "/api/insights/credentials"},
    # Task 0015 step 10: the admin area of steps 2, 3, 4, 6, 7 and 8. A
    # resource route with `:update` answers PUT and PATCH alike.
    {:get, "/api/admin/policies"},
    {:post, "/api/admin/policies"},
    {:get, "/api/admin/policies/{id}"},
    {:put, "/api/admin/policies/{id}"},
    {:patch, "/api/admin/policies/{id}"},
    {:delete, "/api/admin/policies/{id}"},
    {:get, "/api/admin/approved-tools"},
    {:post, "/api/admin/approved-tools"},
    {:get, "/api/admin/approved-tools/{id}"},
    {:put, "/api/admin/approved-tools/{id}"},
    {:patch, "/api/admin/approved-tools/{id}"},
    {:delete, "/api/admin/approved-tools/{id}"},
    {:get, "/api/admin/webhooks"},
    {:post, "/api/admin/webhooks"},
    {:get, "/api/admin/webhooks/{id}"},
    {:put, "/api/admin/webhooks/{id}"},
    {:patch, "/api/admin/webhooks/{id}"},
    {:delete, "/api/admin/webhooks/{id}"},
    {:get, "/api/admin/policy-versions"},
    {:post, "/api/admin/policy-versions"},
    {:get, "/api/admin/policy-versions/{id}"},
    {:put, "/api/admin/policy-versions/{id}"},
    {:patch, "/api/admin/policy-versions/{id}"},
    {:post, "/api/admin/policy-versions/{id}/publish"},
    {:get, "/api/admin/role-grants"},
    {:post, "/api/admin/role-grants"},
    {:delete, "/api/admin/role-grants/{id}"},
    {:get, "/api/admin/api-clients"},
    {:post, "/api/admin/api-clients"},
    {:delete, "/api/admin/api-clients/{id}"},
    {:get, "/api/admin/users"},
    {:post, "/api/admin/user-lookups"},
    {:post, "/api/admin/users"},
    {:post, "/api/admin/users/{id}/invitation"},
    {:post, "/api/admin/users/{id}/disable"},
    {:delete, "/api/admin/users/{id}/sessions"},
    {:delete, "/api/admin/sessions"},
    {:post, "/api/admin/users/{id}/reset-factors"},
    {:post, "/api/admin/users/{id}/reset-failure-counters"},
    {:post, "/api/admin/credentials/{id}/revoke"},
    {:get, "/api/admin/audit"},
    {:post, "/api/admin/packs"},
    {:get, "/api/admin/packs/{id}"},
    {:get, "/api/admin/packs/{id}/diff"},
    {:post, "/api/admin/packs/{id}/publish"},
    # Task 0016 step 10: the SCORM export.
    {:post, "/api/admin/exports"},
    {:get, "/api/admin/exports/{id}"},
    {:get, "/api/admin/exports/{id}/download"},
    # Task 0016a step 9: the pack workbench.
    {:get, "/api/admin/pack-drafts"},
    {:post, "/api/admin/pack-drafts"},
    {:post, "/api/admin/pack-draft-uploads"},
    {:get, "/api/admin/pack-drafts/{id}"},
    {:delete, "/api/admin/pack-drafts/{id}"},
    {:get, "/api/admin/pack-drafts/{id}/download"},
    {:post, "/api/admin/pack-drafts/{id}/check"},
    {:post, "/api/admin/pack-drafts/{id}/imports"},
    {:post, "/api/admin/pack-drafts/{id}/files"},
    {:get, "/api/admin/pack-drafts/{id}/files/{file_id}"},
    {:put, "/api/admin/pack-drafts/{id}/files/{file_id}"},
    {:patch, "/api/admin/pack-drafts/{id}/files/{file_id}"},
    {:delete, "/api/admin/pack-drafts/{id}/files/{file_id}"},
    # Task 0018 steps 15 and 16: the media library and the media entries of
    # a pack draft.
    {:get, "/api/admin/media"},
    {:post, "/api/admin/media"},
    {:get, "/api/admin/media/{id}"},
    {:patch, "/api/admin/media/{id}"},
    {:delete, "/api/admin/media/{id}"},
    {:post, "/api/admin/pack-drafts/{id}/media"},
    {:patch, "/api/admin/pack-drafts/{id}/media/{media_id}"},
    {:delete, "/api/admin/pack-drafts/{id}/media/{media_id}"}
  ]

  # The 2xx answers that carry a file instead of JSON (tasks 0016 and
  # 0016a).
  @binary_answers %{
    {:get, "/api/admin/exports/{id}/download"} => "application/zip",
    {:get, "/api/admin/pack-drafts/{id}/download"} => "application/zip"
  }

  # The POST routes of task 0013 and the schema of their request body.
  @posts_0013 %{
    "/api/policy-versions/{id}/acknowledgements" => "EmptyRequest",
    "/api/formats/{id}/attendance" => "AttendanceRequest",
    "/api/facilitator/user-lookups" => "EmailLookupRequest",
    "/api/integration/credential-lookups" => "EmailLookupRequest"
  }

  # The POST routes of task 0014 and the schema of their request body.
  @posts_0014 %{
    "/api/self-assessments" => "SelfAssessmentRequest",
    "/api/formats/{id}/votes" => "FormatVoteRequest",
    "/api/feedback" => "FeedbackRequest"
  }

  # The POST routes of task 0015 and the schema of their request body. The
  # pack upload is a multipart body with an inline schema.
  @posts_0015 %{
    "/api/admin/policies" => "AdminPolicyRequest",
    "/api/admin/approved-tools" => "AdminApprovedToolRequest",
    "/api/admin/webhooks" => "AdminWebhookRequest",
    "/api/admin/policy-versions" => "AdminPolicyVersionRequest",
    "/api/admin/policy-versions/{id}/publish" => "AdminPolicyVersionPublishRequest",
    "/api/admin/role-grants" => "AdminRoleGrantRequest",
    "/api/admin/api-clients" => "AdminApiClientRequest",
    "/api/admin/user-lookups" => "EmailLookupRequest",
    "/api/admin/users" => "AdminUserInviteRequest",
    "/api/admin/users/{id}/invitation" => "EmptyRequest",
    "/api/admin/users/{id}/disable" => "EmptyRequest",
    "/api/admin/users/{id}/reset-factors" => "AdminFactorResetRequest",
    "/api/admin/users/{id}/reset-failure-counters" => "EmptyRequest",
    "/api/admin/credentials/{id}/revoke" => "EmptyRequest",
    "/api/admin/packs" => "AdminPackUpload",
    "/api/admin/packs/{id}/publish" => "EmptyRequest"
  }

  # The POST route of task 0016 and the schema of its request body.
  @posts_0016 %{"/api/admin/exports" => "AdminExportRequest"}

  # The POST, PUT and PATCH routes of task 0016a and the schema of their
  # request body. The upload of a draft is a multipart body with an inline
  # schema, and the body of the check is optional.
  @requests_0016a %{
    {:post, "/api/admin/pack-drafts"} => "AdminPackDraftRequest",
    {:post, "/api/admin/pack-draft-uploads"} => "AdminPackDraftUpload",
    {:post, "/api/admin/pack-drafts/{id}/check"} => "AdminPackDraftCheckRequest",
    {:post, "/api/admin/pack-drafts/{id}/files"} => "AdminPackDraftFileRequest",
    {:put, "/api/admin/pack-drafts/{id}/files/{file_id}"} => "AdminPackDraftFileUpdate",
    {:patch, "/api/admin/pack-drafts/{id}/files/{file_id}"} => "AdminPackDraftRename",
    {:post, "/api/admin/pack-drafts/{id}/imports"} => "AdminPackDraftImportRequest"
  }

  @posts_0016a for {{:post, path}, _title} <- @requests_0016a, do: path

  # The POST and PATCH routes of task 0018 and the schema of their request
  # body. The media upload is a multipart body with an inline schema, as the
  # pack upload.
  @requests_0018 %{
    {:post, "/api/admin/media"} => "AdminMediaUpload",
    {:patch, "/api/admin/media/{id}"} => "AdminMediaUpdate",
    {:post, "/api/admin/pack-drafts/{id}/media"} => "AdminDraftMediaAttach",
    {:patch, "/api/admin/pack-drafts/{id}/media/{media_id}"} => "AdminDraftMediaRename"
  }

  @posts_0018 for {{:post, path}, _title} <- @requests_0018, do: path

  defp operations do
    for {path, item} <- ApiSpec.spec().paths,
        {verb, %Operation{} = operation} <- Map.from_struct(item),
        do: {{verb, path}, operation}
  end

  test "every listed route has an operation and no other route has one" do
    assert operations() |> Enum.map(&elem(&1, 0)) |> Enum.sort() == Enum.sort(@routes)
  end

  test "every 2xx answer other than 204 names a schema" do
    for {{verb, path}, operation} <- operations(),
        {status, response} <- operation.responses,
        status in 200..299 and status != 204 do
      case Map.fetch(@binary_answers, {verb, path}) do
        {:ok, media_type} ->
          assert %Response{content: %{^media_type => %MediaType{schema: schema}}} = response
          assert %Schema{type: :string, format: :binary} = schema, "#{verb} #{path} #{status}"

        :error ->
          assert %Response{content: %{"application/json" => %MediaType{schema: schema}}} =
                   response

          assert match?(%Reference{}, schema) or
                   match?(%Schema{title: title} when is_binary(title), schema),
                 "#{verb} #{path} #{status}"
      end
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

  test "DELETE /api/session documents the 200 answer with logout_url and the 204 answer" do
    spec = ApiSpec.spec()
    responses = spec.paths["/api/session"].delete.responses

    assert %Reference{"$ref": "#/components/schemas/LogoutRedirect"} =
             responses[200].content["application/json"].schema

    assert %Response{content: nil} = responses[204]
    assert Map.keys(spec.components.schemas["LogoutRedirect"].properties) == [:logout_url]
  end

  test "GET /api/me/security names linked_providers and the session flag admin_passkey_required" do
    spec = ApiSpec.spec()
    summary = spec.components.schemas["SecuritySummary"]

    assert %Schema{type: :array, items: %Schema{type: :string}} =
             summary.properties.linked_providers

    assert :linked_providers in summary.required

    flags = spec.components.schemas["SessionPayload"].properties.flags
    assert Map.has_key?(flags.properties, :admin_passkey_required)
  end

  test "the answers that extend the session payload keep its members" do
    schemas = ApiSpec.spec().components.schemas
    payload = Map.keys(schemas["SessionPayload"].properties)

    for {title, extra} <- [
          {"SecondFactorSession", :recovery_codes_remaining},
          {"ReauthSession", :recent_auth_until},
          {"FinishSession", :linked}
        ] do
      assert Enum.sort(Map.keys(schemas[title].properties)) == Enum.sort([extra | payload]),
             title
    end

    assert :recent_auth_until in schemas["ReauthSession"].required
    refute :linked in schemas["FinishSession"].required
  end

  test "every request schema of the learner routes sets additionalProperties false" do
    for title <- ~w(EnrollmentRequest EnrollmentPathRequest ItemResponseRequest AttemptRequest
                    Answer EmptyRequest) do
      assert ApiSpec.spec().components.schemas[title].additionalProperties == false, title
    end
  end

  test "every request schema of the POST routes of task 0013 sets additionalProperties false" do
    spec = ApiSpec.spec()

    for {path, title} <- @posts_0013 do
      assert %Operation{requestBody: %RequestBody{content: content}} = spec.paths[path].post
      assert %{"application/json" => %MediaType{schema: schema}} = content
      assert %Reference{"$ref": "#/components/schemas/" <> ^title} = schema, path

      for object <- objects(resolve(spec, schema), spec) do
        assert object.additionalProperties == false, "#{path} #{title}"
      end
    end
  end

  # Task 0014, Security requirement 15.3.3. The member `answers` of
  # FeedbackRequest maps question keys to answers, so its object admits
  # further members only through the schema of an answer.
  test "every request schema of the POST routes of task 0014 sets additionalProperties false" do
    spec = ApiSpec.spec()

    for {path, title} <- @posts_0014 do
      assert %Operation{requestBody: %RequestBody{content: content, required: true}} =
               spec.paths[path].post

      assert %{"application/json" => %MediaType{schema: schema}} = content
      assert %Reference{"$ref": "#/components/schemas/" <> ^title} = schema, path
      assert %Schema{type: :object, additionalProperties: false} = resolve(spec, schema), path

      for object <- objects(resolve(spec, schema), spec) do
        assert object.additionalProperties == false or
                 match?(%Schema{}, object.additionalProperties),
               "#{path} #{title}"
      end
    end

    answers = spec.components.schemas["FeedbackRequest"].properties.answers
    assert %Schema{type: :object, additionalProperties: %Schema{}} = answers
  end

  # Task 0015 step 10, Security requirement 15.3.3: every POST route under
  # /api/admin is listed, and the multipart schema of the pack upload sets
  # additionalProperties false like the JSON schemas.
  test "every request schema of the POST routes of task 0015 sets additionalProperties false" do
    spec = ApiSpec.spec()

    admin_posts =
      for {{:post, "/api/admin/" <> _rest = path}, _operation} <- operations(), do: path

    assert Enum.sort(admin_posts) ==
             Enum.sort(
               Map.keys(@posts_0015) ++ Map.keys(@posts_0016) ++ @posts_0016a ++ @posts_0018
             )

    for {path, title} <- @posts_0015 do
      assert %Operation{requestBody: %RequestBody{content: content}} = spec.paths[path].post

      media_type =
        if path == "/api/admin/packs", do: "multipart/form-data", else: "application/json"

      assert [{^media_type, %MediaType{schema: schema}}] = Map.to_list(content), path
      schema = resolve(spec, schema)
      assert %Schema{title: ^title, type: :object, additionalProperties: false} = schema, path

      for object <- objects(schema, spec) do
        assert object.additionalProperties == false, "#{path} #{title}"
      end
    end

    # The upload is described as a binary field `file` (step 10).
    upload = spec.paths["/api/admin/packs"].post.requestBody.content["multipart/form-data"]
    assert %Schema{type: :string, format: :binary} = upload.schema.properties.file
    assert upload.schema.required == [:file]
  end

  # Task 0016 step 10, Security requirements 2.1.1 and 15.3.3.
  test "the request schema of the POST route of task 0016 sets additionalProperties false" do
    spec = ApiSpec.spec()

    for {path, title} <- @posts_0016 do
      assert %Operation{requestBody: %RequestBody{content: content, required: true}} =
               spec.paths[path].post

      assert [{"application/json", %MediaType{schema: schema}}] = Map.to_list(content), path
      schema = resolve(spec, schema)
      assert %Schema{title: ^title, type: :object, additionalProperties: false} = schema, path
      assert schema.properties.scorm_version.enum == ["scorm12", "scorm2004"]

      for object <- objects(schema, spec) do
        assert object.additionalProperties == false, "#{path} #{title}"
      end
    end
  end

  # Task 0016a step 9, Security requirements 2.1.1, 2.1.3, 5.1.1 and 15.3.3.
  test "the request schemas of the POST, PUT and PATCH routes of task 0016a set additionalProperties false" do
    spec = ApiSpec.spec()

    for {{verb, path}, title} <- @requests_0016a do
      label = "#{verb} #{path}"
      item = spec.paths[path]
      assert %Operation{requestBody: %RequestBody{content: content} = body} = Map.get(item, verb)
      assert body.required == (path != "/api/admin/pack-drafts/{id}/check"), label

      media_type =
        if path == "/api/admin/pack-draft-uploads",
          do: "multipart/form-data",
          else: "application/json"

      assert [{^media_type, %MediaType{schema: schema}}] = Map.to_list(content), label
      schema = resolve(spec, schema)
      assert %Schema{title: ^title, type: :object, additionalProperties: false} = schema, label

      for object <- objects(schema, spec) do
        assert object.additionalProperties == false, "#{label} #{title}"
      end

      for {member, %Schema{} = property} <- schema.properties do
        case member do
          :path -> assert {property.minLength, property.maxLength} == {1, 527}, label
          :content -> assert property.maxLength == 1_048_576, label
          :lock_version -> assert {property.type, property.minimum} == {:integer, 1}, label
          :name -> assert {property.minLength, property.maxLength} == {1, 255}, label
          _other -> :ok
        end
      end
    end

    # The starting points and the overlay of the check.
    request = spec.components.schemas["AdminPackDraftRequest"]
    assert request.properties.source.enum == ["empty", "program", "import"]
    assert request.required == [:source]

    check = spec.components.schemas["AdminPackDraftCheckRequest"]
    assert check.required == []
    assert Enum.sort(Map.keys(check.properties)) == [:content, :file_id]

    # The upload is described as a binary field `file`, as the pack upload.
    upload =
      spec.paths["/api/admin/pack-draft-uploads"].post.requestBody.content["multipart/form-data"]

    assert %Schema{type: :string, format: :binary} = upload.schema.properties.file
    assert upload.schema.required == [:file]

    # The descriptions of the upload, the file create and the file update
    # name the limits of a draft.
    for {verb, path} <- [
          {:post, "/api/admin/pack-draft-uploads"},
          {:post, "/api/admin/pack-drafts/{id}/files"},
          {:put, "/api/admin/pack-drafts/{id}/files/{file_id}"}
        ] do
      description = Map.get(spec.paths[path], verb).description

      for limit <- ["2,000", "1,048,576", "PACK_UPLOAD_MAX_MB", "U+0000"] do
        assert description =~ limit, "#{verb} #{path}: #{limit}"
      end
    end

    # The delete of a file takes the lock_version in its query string.
    delete = spec.paths["/api/admin/pack-drafts/{id}/files/{file_id}"].delete

    assert [%{schema: %Schema{type: :integer, minimum: 1}, required: true}] =
             Enum.filter(delete.parameters, &(&1.in == :query and &1.name == :lock_version))
  end

  # Task 0018 steps 15 and 16, Security requirements 2.1.1, 2.1.3, 5.1.1
  # and 15.3.3.
  test "the request schemas of the POST and PATCH routes of task 0018 set additionalProperties false" do
    spec = ApiSpec.spec()

    for {{verb, path}, title} <- @requests_0018 do
      label = "#{verb} #{path}"
      item = spec.paths[path]

      assert %Operation{requestBody: %RequestBody{content: content, required: true}} =
               Map.get(item, verb),
             label

      media_type =
        if path == "/api/admin/media", do: "multipart/form-data", else: "application/json"

      assert [{^media_type, %MediaType{schema: schema}}] = Map.to_list(content), label
      schema = resolve(spec, schema)
      assert %Schema{title: ^title, type: :object, additionalProperties: false} = schema, label

      for object <- objects(schema, spec) do
        assert object.additionalProperties == false, "#{label} #{title}"
      end

      for {member, %Schema{} = property} <- schema.properties do
        case member do
          :path -> assert {property.minLength, property.maxLength} == {1, 527}, label
          :lock_version -> assert {property.type, property.minimum} == {:integer, 1}, label
          :title -> assert {property.minLength, property.maxLength} == {1, 255}, label
          _other -> :ok
        end
      end
    end

    # The upload is described as a binary field `file`, as the pack upload,
    # and its description names the accepted types, their signatures and
    # the limits.
    upload = spec.paths["/api/admin/media"].post
    multipart = upload.requestBody.content["multipart/form-data"]
    assert %Schema{type: :string, format: :binary} = multipart.schema.properties.file
    assert multipart.schema.required == [:file]

    for text <- [
          ".png",
          ".jpg",
          ".gif",
          ".webp",
          ".svg",
          ".mp4",
          ".webm",
          ".vtt",
          "89 50 4E 47",
          "1A 45 DF A3",
          "WEBVTT",
          "MEDIA_IMAGE_MAX_MB",
          "MEDIA_VIDEO_MAX_MB",
          "MEDIA_STORAGE_MAX_GB",
          "1,048,576",
          "524,288",
          "40,000,000"
        ] do
      assert upload.description =~ text, text
    end

    # The delete of a media entry takes the lock_version in its query string.
    delete = spec.paths["/api/admin/pack-drafts/{id}/media/{media_id}"].delete

    assert [%{schema: %Schema{type: :integer, minimum: 1}, required: true}] =
             Enum.filter(delete.parameters, &(&1.in == :query and &1.name == :lock_version))
  end

  # Task 0018 steps 10 and 16, Security requirements 2.1.1, 2.1.3 and 5.1.1.
  test "the pack upload and the draft archive upload describe the media of the archive" do
    spec = ApiSpec.spec()

    # The loader counts every file below media/, referenced or not.
    pack = spec.paths["/api/admin/packs"].post

    assert pack.description =~
             "at most #{Entries.number(Media.max_pack_media())} files (`max_pack_media`), " <>
               "whether a lesson references them or not"

    assert pack.description =~ "the media path rules and the size limit of its kind"

    # The archive start ingests the media files into the library.
    upload = spec.paths["/api/admin/pack-draft-uploads"].post

    for text <- [
          "the captions files `.vtt` below `media/` as text files",
          "at most #{Entries.number(Media.max_draft_media())} (`max_draft_media`)",
          "becomes an asset of the media library",
          "the directives of the lessons follow the new paths",
          "reject the archive with 422 entries",
          "never appear in `skipped`"
        ] do
      assert upload.description =~ text, text
    end

    assert %Response{description: conflict} = upload.responses[409]
    assert conflict =~ "`media_limit`"
  end

  # Task 0018 step 16: a download of a draft builds its zip in a slot of
  # the checks and imports, so their operations name the zip builds, and
  # the download names its own bound and the deadline of the transfer.
  test "the check, the import and the download of a draft name their slots" do
    spec = ApiSpec.spec()

    for {verb, path} <- [
          {:post, "/api/admin/pack-drafts/{id}/check"},
          {:post, "/api/admin/pack-drafts/{id}/imports"}
        ] do
      description = Map.get(spec.paths[path], verb).description

      assert description =~
               "At most two checks, imports and zip builds of draft downloads run at once."

      assert %Response{} = Map.get(spec.paths[path], verb).responses[429], "#{verb} #{path}"
    end

    download = spec.paths["/api/admin/pack-drafts/{id}/download"].get

    for text <- [
          "At most two downloads run at once, one per user",
          "builds the archive in one of the two slots of the checks and imports and frees " <>
            "it before the transfer",
          "When the user runs a download already or no slot is free, the download " <>
            "answers 429 `checks_busy` and builds nothing.",
          "the size of the archive at 256 KiB per second and at least 60 seconds"
        ] do
      assert download.description =~ text, text
    end

    assert %Response{} = download.responses[429]
  end

  test "the schema of media_not_ready names the publish, the start and the download" do
    schema = ApiSpec.spec().components.schemas["AdminMediaNotReady"]

    assert schema.description =~
             "at the publish of an import, at the start of a draft from a program or an " <>
               "import, or at the download of a draft"
  end

  test "the integration operation names the bearer token, which the document declares" do
    spec = ApiSpec.spec()

    assert spec.paths["/api/integration/credential-lookups"].post.security == [
             %{"bearer_token" => []}
           ]

    assert %SecurityScheme{type: "http", scheme: "bearer"} =
             spec.components.securitySchemes["bearer_token"]

    for {{verb, path}, operation} <- operations(),
        path != "/api/integration/credential-lookups",
        requirement <- operation.security || [] do
      refute Map.has_key?(requirement, "bearer_token"), "#{verb} #{path}"
    end
  end

  defp resolve(spec, %Reference{"$ref": "#/components/schemas/" <> title}),
    do: spec.components.schemas[title]

  defp resolve(_spec, %Schema{} = schema), do: schema

  # The schema and every object schema nested in its properties and items.
  defp objects(%Schema{} = schema, spec) do
    nested =
      Map.values(schema.properties || %{}) ++ if(schema.items, do: [schema.items], else: [])

    own = if schema.type == :object, do: [schema], else: []
    own ++ Enum.flat_map(nested, &objects(resolve(spec, &1), spec))
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
