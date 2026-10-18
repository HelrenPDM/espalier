defmodule EspalierWeb.Admin.AdminRoutesTest do
  @moduledoc """
  The route tests of task 0015 (step 19, bullet "Route tests", and
  Acceptance). Each test selects every route under `/api/admin` from
  `Phoenix.Router.routes/1`, reads its pipelines with
  `Phoenix.Router.route_info/4` and sends a request per route, with a valid
  UUID for every path parameter.

  `protect_api_from_forgery/2` runs before the role plugs, so every request
  carries the CSRF token of its session, also a signed-out request that
  expects 401, and every request fetches its token anew after a sign-in.

  - Every route answers 401 without a session and 403 `forbidden` to a
    learner (ASVS 8.2.1).
  - With `ADMIN_REQUIRE_PASSKEY=true`, every route in `:admin` and
    `:admin_write` answers 403 `passkey_required` to an admin without a
    passkey; with `false`, the same admin passes the gate (README section
    6.11).
  - Every route in `:admin_write` and `:author_write` answers 403
    `reauth_required` when `mfa_at` lies 11 minutes back and passes the plug
    with `mfa_at` now; the routes in `:admin` and `:author`, among them the
    user lookup and the check of a pack draft, need no recent second factor
    (ASVS 7.5.1).
  - Every POST, PUT, PATCH and DELETE route apart from
    `POST /api/admin/user-lookups` and `POST /api/admin/pack-drafts/:id/check`
    runs `:admin_write` or `:author_write`, the lookup runs `:admin`, the
    check of a pack draft (task 0016a), which changes no state, runs
    `:author`, and every GET runs `:admin` or `:author`.
  - Only the pack upload and the upload of a pack draft (task 0016a) run
    `:pack_upload`, and only the media upload (task 0018) runs
    `:media_upload`, each after `:author_write`, and all three check the
    content type only after the checks of `:author_write`.
  - A failed role check, a missing recent second factor and a closed
    passkey gate log `authz_fail` (ASVS 16.3.2).
  - Every answer under `/api/admin` carries `cache-control: no-store` (ASVS
    14.2.2 and 14.3.2), and no route takes an e-mail address in its path or
    query string (ASVS 14.2.1).
  - Every POST route apart from the three uploads and every PUT and PATCH
    route answers 422 `validation_failed` for a JSON body with an extra
    member (ASVS 15.3.3).
  """
  # put_setting/2 changes the application environment.
  use EspalierWeb.ConnCase, async: false

  import Espalier.CredentialsFixtures

  alias Espalier.Accounts
  alias Espalier.Accounts.Scope
  alias EspalierWeb.{ApiSpec, Router}
  alias OpenApiSpex.{Operation, Parameter}

  @host "www.example.com"
  @lookup "/api/admin/user-lookups"
  @draft_check "/api/admin/pack-drafts/:id/check"
  @pack_upload "/api/admin/packs"
  @draft_upload "/api/admin/pack-draft-uploads"
  @media_upload "/api/admin/media"
  @pack_uploads [@pack_upload, @draft_upload]
  @uploads [@pack_upload, @draft_upload, @media_upload]
  @uuid "6f1c2d3e-4b5a-4c6d-8e7f-0a1b2c3d4e5f"

  # A body of every POST route that its request schema accepts. The test of
  # extra members merges the member "unexpected" into it. The three uploads
  # are multipart bodies with the archive or the media file in the field
  # "file" and have no JSON members, so that test leaves them out; the
  # archive and media upload tests cover them.
  @post_bodies %{
    "/api/admin/policies" => %{policy: %{key: "route-test", title: "A policy"}},
    "/api/admin/approved-tools" => %{
      approved_tool: %{name: "A tool", vendor: "A vendor", status: "approved", position: 1}
    },
    "/api/admin/webhooks" => %{
      webhook: %{
        url: "https://hooks.example.org/espalier",
        events: ["credential.issued"],
        secret_env: "WEBHOOK_SECRET_TEST"
      }
    },
    "/api/admin/policy-versions" => %{
      policy_id: @uuid,
      body: "The text of the policy.",
      effective_from: "2026-01-01"
    },
    "/api/admin/policy-versions/:id/publish" => %{requires_refresher: false},
    "/api/admin/role-grants" => %{user_id: @uuid, role: "author"},
    "/api/admin/api-clients" => %{name: "A client", scopes: ["credentials:read"]},
    "/api/admin/user-lookups" => %{email: "someone@example.com"},
    "/api/admin/users" => %{email: "invitee@example.com", display_name: "An invitee"},
    "/api/admin/users/:id/invitation" => %{},
    "/api/admin/users/:id/disable" => %{},
    "/api/admin/users/:id/reset-factors" => %{identity_verified: true},
    "/api/admin/users/:id/reset-failure-counters" => %{},
    "/api/admin/credentials/:id/revoke" => %{},
    "/api/admin/packs/:id/publish" => %{},
    "/api/admin/exports" => %{module_id: @uuid, scorm_version: "scorm12"},
    "/api/admin/pack-drafts" => %{source: "empty", name: "A pack"},
    "/api/admin/pack-drafts/:id/check" => %{},
    "/api/admin/pack-drafts/:id/files" => %{
      path: "sources.yaml",
      content: "[]\n",
      lock_version: 1
    },
    "/api/admin/pack-drafts/:id/imports" => %{lock_version: 1},
    "/api/admin/pack-drafts/:id/media" => %{
      media_asset_id: @uuid,
      path: "media/photo.webp",
      lock_version: 1
    }
  }

  # A body of every PUT and PATCH route that its request schema accepts,
  # for the test of extra members. A resource route with `:update` answers
  # PUT and PATCH with one schema; the file of a pack draft takes its
  # content with PUT and its path with PATCH (task 0016a).
  @update_bodies %{
    {:put, "/api/admin/policies/:id"} => %{policy: %{title: "A policy"}},
    {:patch, "/api/admin/policies/:id"} => %{policy: %{title: "A policy"}},
    {:put, "/api/admin/approved-tools/:id"} => %{approved_tool: %{name: "A tool"}},
    {:patch, "/api/admin/approved-tools/:id"} => %{approved_tool: %{name: "A tool"}},
    {:put, "/api/admin/webhooks/:id"} => %{webhook: %{active: false}},
    {:patch, "/api/admin/webhooks/:id"} => %{webhook: %{active: false}},
    {:put, "/api/admin/policy-versions/:id"} => %{requires_refresher: false},
    {:patch, "/api/admin/policy-versions/:id"} => %{requires_refresher: false},
    {:put, "/api/admin/pack-drafts/:id/files/:file_id"} => %{content: "", lock_version: 1},
    {:patch, "/api/admin/pack-drafts/:id/files/:file_id"} => %{
      path: "sources.yaml",
      lock_version: 1
    },
    # Task 0018: the title of a library asset and the path of a media entry.
    {:patch, "/api/admin/media/:id"} => %{title: "A title"},
    {:patch, "/api/admin/pack-drafts/:id/media/:media_id"} => %{
      path: "media/photo.webp",
      lock_version: 1
    }
  }

  # Every route under /api/admin with its method, a path with a valid UUID
  # for every path parameter, and the pipelines of route_info/4.
  defp admin_routes do
    routes =
      for %{verb: verb, path: "/api/admin/" <> _rest = pattern} <- Phoenix.Router.routes(Router) do
        method = verb |> Atom.to_string() |> String.upcase()
        path = concrete_path(pattern)

        assert %{route: ^pattern, pipe_through: pipes} =
                 Phoenix.Router.route_info(Router, method, path, @host)

        %{verb: verb, method: method, pattern: pattern, path: path, pipes: pipes}
      end

    patterns = Enum.map(routes, & &1.pattern)
    assert @lookup in patterns
    assert @draft_check in patterns
    assert Enum.all?(@uploads, &(&1 in patterns))
    routes
  end

  defp concrete_path(pattern) do
    pattern
    |> String.split("/")
    |> Enum.map_join("/", fn
      ":" <> _name -> Ecto.UUID.generate()
      segment -> segment
    end)
  end

  defp label(route), do: "#{route.method} #{route.pattern}"

  defp admin_route?(%{pipes: pipes}), do: :admin in pipes or :admin_write in pipes
  defp write_route?(%{pipes: pipes}), do: :admin_write in pipes or :author_write in pipes
  defp author_route?(%{pipes: pipes}), do: :author in pipes or :author_write in pipes

  defp admin_with_passkey do
    admin = user_with_role_fixture(:admin)
    passkey_fixture(admin)
    admin
  end

  # A new session of `user` (strength mfa, mfa_at now) and its token.
  defp sign_in(user) do
    conn = log_in_user(api_conn(), user)
    get_session(conn, :user_token)
  end

  defp session_conn(token), do: init_test_session(api_conn(), %{user_token: token})

  defp minutes_ago(minutes), do: DateTime.add(DateTime.utc_now(:second), -minutes, :minute)

  defp set_mfa_at(token, mfa_at), do: assert({1, _} = override_session(token, mfa_at: mfa_at))

  # Sends the request of `route` with the CSRF token of the session of
  # `conn` and returns `{status, headers, decoded body}`. GET and DELETE
  # send no body, the three uploads send the multipart body of the pack
  # upload with a file that holds no zip archive, and every other route
  # sends `body` as JSON. An exception that the endpoint rendered as a
  # client error before it raised it again, such as `Ecto.NoResultsError`
  # as 404 for an unknown id, counts with the answer it sent; any other
  # exception fails the test.
  defp send_route(conn, route, body \\ %{}) do
    discard_sent()

    conn =
      case route do
        %{verb: verb} when verb in [:get, :delete] ->
          json_request(conn, verb, route.path)

        %{verb: :post, pattern: pattern} when pattern in @uploads ->
          upload_request(conn, route.path, "not a zip archive")

        %{verb: verb} ->
          json_request(conn, verb, route.path, body)
      end

    {conn.status, conn.resp_headers, decode(conn.resp_body)}
  rescue
    exception in [ExUnit.AssertionError] ->
      reraise exception, __STACKTRACE__

    exception ->
      case last_sent(nil) do
        {status, headers, body} when status < 500 -> {status, headers, decode(body)}
        _other -> reraise exception, __STACKTRACE__
      end
  end

  defp discard_sent do
    receive do
      {ref, {_status, _headers, _body}} when is_reference(ref) -> discard_sent()
      {:plug_conn, :sent} -> discard_sent()
    after
      0 -> :ok
    end
  end

  # The last answer of the test adapter: the CSRF request comes first.
  defp last_sent(last) do
    receive do
      {ref, {status, headers, body}} when is_reference(ref) -> last_sent({status, headers, body})
      {:plug_conn, :sent} -> last_sent(last)
    after
      0 -> last
    end
  end

  defp decode(""), do: nil

  defp decode(body) do
    case JSON.decode(body) do
      {:ok, decoded} -> decoded
      {:error, _reason} -> body
    end
  end

  defp no_store?(headers), do: {"cache-control", "no-store"} in headers

  defp assert_passes(route, {status, headers, body}) do
    assert status not in [401, 403] and status < 500,
           "#{label(route)} answered #{status}: #{inspect(body)}"

    assert no_store?(headers), label(route)
  end

  describe "the pipelines" do
    test "every mutating route runs :admin_write or :author_write, the lookup, the check and every GET a read pipeline" do
      for route <- admin_routes() do
        assert [:api | _rest] = route.pipes, label(route)

        case route do
          %{verb: :post, pattern: @lookup} ->
            assert :admin in route.pipes, label(route)
            refute write_route?(route), label(route)

          # The check of a draft writes and removes a temporary directory
          # and changes no state (task 0016a, step 9).
          %{verb: :post, pattern: @draft_check} ->
            assert route.pipes == [:api, :author], label(route)

          %{verb: :get} ->
            assert :admin in route.pipes or :author in route.pipes, label(route)
            refute write_route?(route), label(route)

          %{verb: verb} when verb in [:post, :put, :patch, :delete] ->
            assert write_route?(route), label(route)
            refute :admin in route.pipes or :author in route.pipes, label(route)
        end

        # The upload parsers run only for the three uploads and only after
        # the checks of :author_write: the parser of the pack upload for the
        # two archives, the parser of the media upload for media files.
        case route do
          %{verb: :post, pattern: pattern} when pattern in @pack_uploads ->
            assert route.pipes == [:api, :author_write, :pack_upload], label(route)

          %{verb: :post, pattern: @media_upload} ->
            assert route.pipes == [:api, :author_write, :media_upload], label(route)

          _other ->
            refute :pack_upload in route.pipes, label(route)
            refute :media_upload in route.pipes, label(route)
        end
      end
    end

    test "no route takes an e-mail address in its path or query string" do
      for route <- admin_routes() do
        refute route.pattern =~ ~r/mail|@/i, label(route)
      end

      for {path, item} <- ApiSpec.spec().paths,
          String.starts_with?(path, "/api/admin/"),
          {verb, %Operation{} = operation} <- Map.from_struct(item),
          %Parameter{name: name} <- operation.parameters do
        refute to_string(name) =~ ~r/mail/i, "#{verb} #{path} #{name}"
      end

      # The user list declares a query parameter, so CastAndValidate rejects
      # any other member of its query string.
      token = sign_in(admin_with_passkey())
      route = %{verb: :get, method: "GET", pattern: "/api/admin/users"}
      path = "/api/admin/users?email=" <> URI.encode_www_form("someone@example.com")

      assert {422, _headers, body} = send_route(session_conn(token), Map.put(route, :path, path))

      assert body == %{
               "error" => "validation_failed",
               "fields" => %{"email" => ["unexpected_field"]}
             }
    end
  end

  describe "the role checks" do
    test "every route answers 401 without a session, with cache-control no-store" do
      for route <- admin_routes() do
        {status, headers, body} = send_route(api_conn(), route)

        assert {status, body} == {401, %{"error" => "unauthenticated"}}, label(route)
        assert no_store?(headers), label(route)
      end
    end

    test "every route answers 403 forbidden to a learner and logs authz_fail" do
      learner = user_fixture()
      learner_id = learner.id
      token = sign_in(learner)
      ref = attach_security_events()

      for route <- admin_routes() do
        {status, headers, body} = send_route(session_conn(token), route)

        assert {status, body} == {403, %{"error" => "forbidden"}}, label(route)
        assert no_store?(headers), label(route)

        assert_received {^ref, %{name: :authz_fail, reason: "forbidden", user_id: ^learner_id}},
                        label(route)
      end
    end
  end

  describe "the passkey gate" do
    test "with ADMIN_REQUIRE_PASSKEY=true every admin route answers 403 passkey_required to an admin without a passkey" do
      put_setting(:admin_require_passkey, true)
      admin = user_with_role_fixture(:admin)
      admin_id = admin.id
      token = sign_in(admin)
      ref = attach_security_events()
      routes = Enum.filter(admin_routes(), &admin_route?/1)
      assert routes != []

      for route <- routes do
        {status, _headers, body} = send_route(session_conn(token), route)

        assert {status, body} == {403, %{"error" => "passkey_required"}}, label(route)

        assert_received {^ref,
                         %{name: :authz_fail, reason: "passkey_required", user_id: ^admin_id}},
                        label(route)
      end
    end

    test "with ADMIN_REQUIRE_PASSKEY=false the same admin passes the gate" do
      put_setting(:admin_require_passkey, false)
      admin = user_with_role_fixture(:admin)
      ref = attach_security_events()

      # A new session per route: DELETE /api/admin/sessions ends every
      # session, also the acting admin's own.
      for route <- admin_routes(), admin_route?(route) do
        assert_passes(route, send_route(session_conn(sign_in(admin)), route))
        refute_received {^ref, %{name: :authz_fail}}, label(route)
      end
    end
  end

  describe "the recent second factor" do
    test "every write route answers 403 reauth_required 11 minutes after the second factor and passes with one now" do
      # The gate is open for the admin, who holds a passkey; the author
      # holds none, because the author pipelines run no passkey gate.
      put_setting(:admin_require_passkey, true)
      actors = %{admin: admin_with_passkey(), author: user_with_role_fixture(:author)}
      ref = attach_security_events()
      routes = Enum.filter(admin_routes(), &write_route?/1)
      assert Enum.any?(routes, &author_route?/1)

      for route <- routes do
        actor = if author_route?(route), do: actors.author, else: actors.admin
        actor_id = actor.id
        token = sign_in(actor)

        set_mfa_at(token, minutes_ago(11))
        {status, headers, body} = send_route(session_conn(token), route)

        assert {status, body} == {403, %{"error" => "reauth_required"}}, label(route)
        assert no_store?(headers), label(route)

        assert_received {^ref,
                         %{name: :authz_fail, reason: "reauth_required", user_id: ^actor_id}},
                        label(route)

        set_mfa_at(token, DateTime.utc_now(:second))
        assert_passes(route, send_route(session_conn(token), route))
        refute_received {^ref, %{name: :authz_fail}}, label(route)
      end
    end

    test "the read routes, the user lookup and the check of a draft need no recent second factor" do
      put_setting(:admin_require_passkey, true)
      admin_token = sign_in(admin_with_passkey())
      author_token = sign_in(user_with_role_fixture(:author))
      set_mfa_at(admin_token, minutes_ago(11))
      set_mfa_at(author_token, minutes_ago(11))
      routes = Enum.reject(admin_routes(), &write_route?/1)
      assert Enum.any?(routes, &(&1.pattern == @lookup))
      assert Enum.any?(routes, &(&1.pattern == @draft_check))

      for route <- routes do
        token = if author_route?(route), do: author_token, else: admin_token
        assert_passes(route, send_route(session_conn(token), route))
      end
    end

    test "the three uploads check the content type only after the checks of :author_write" do
      author = user_with_role_fixture(:author)
      token = sign_in(author)
      learner_token = sign_in(user_fixture())

      for path <- @uploads do
        conn = json_request(api_conn(), :post, path, %{})
        assert json_response(conn, 401) == %{"error" => "unauthenticated"}, path

        conn = json_request(session_conn(learner_token), :post, path, %{})
        assert json_response(conn, 403) == %{"error" => "forbidden"}, path

        set_mfa_at(token, minutes_ago(11))
        conn = json_request(session_conn(token), :post, path, %{})
        assert json_response(conn, 403) == %{"error" => "reauth_required"}, path

        set_mfa_at(token, DateTime.utc_now(:second))
        conn = json_request(session_conn(token), :post, path, %{})
        assert json_response(conn, 415) == %{"error" => "unsupported_media_type"}, path
        assert get_resp_header(conn, "cache-control") == ["no-store"], path
      end
    end
  end

  describe "the request bodies" do
    # The three uploads are multipart bodies without JSON members; the
    # archive and media upload tests check them.
    test "every POST route answers 422 validation_failed for a body with an extra member" do
      token = sign_in(staff_with_passkey())

      posts =
        for %{verb: :post, pattern: pattern} = route <- admin_routes(),
            pattern not in @uploads,
            do: route

      assert Enum.sort(Enum.map(posts, & &1.pattern)) == Enum.sort(Map.keys(@post_bodies))

      for route <- posts do
        body = Map.put(Map.fetch!(@post_bodies, route.pattern), :unexpected, 1)
        {status, _headers, answer} = send_route(session_conn(token), route, body)

        assert {status, answer} ==
                 {422,
                  %{
                    "error" => "validation_failed",
                    "fields" => %{"unexpected" => ["unexpected_field"]}
                  }},
               label(route)
      end
    end

    test "every PUT and PATCH route answers 422 validation_failed for a body with an extra member" do
      token = sign_in(staff_with_passkey())

      updates =
        for %{verb: verb} = route <- admin_routes(), verb in [:put, :patch], do: route

      assert Enum.sort(Enum.map(updates, &{&1.verb, &1.pattern})) ==
               Enum.sort(Map.keys(@update_bodies))

      for route <- updates do
        body = Map.put(Map.fetch!(@update_bodies, {route.verb, route.pattern}), :unexpected, 1)
        {status, _headers, answer} = send_route(session_conn(token), route, body)

        assert {status, answer} ==
                 {422,
                  %{
                    "error" => "validation_failed",
                    "fields" => %{"unexpected" => ["unexpected_field"]}
                  }},
               label(route)
      end
    end
  end

  # An admin with a passkey who also holds the role author, so that one
  # session reaches every route with the passkey gate on.
  defp staff_with_passkey do
    put_setting(:admin_require_passkey, true)
    staff = user_with_role_fixture(:admin)
    {:ok, _grant} = Accounts.grant_role(Scope.system(), staff, :author)
    passkey_fixture(staff)
    staff
  end
end
