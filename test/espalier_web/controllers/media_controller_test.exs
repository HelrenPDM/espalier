defmodule EspalierWeb.MediaControllerTest do
  @moduledoc """
  The media route `GET /media/:file` (task 0018, steps 13 and 23): the
  session check of the pipeline `:media`, the name rule, the authorization
  rule of `Espalier.Media.servable/3` (ASVS 8.2.2), `Sec-Fetch-Dest` per
  type (ASVS 3.2.1), the Fetch Metadata plug without an allowlist (ASVS
  3.5.8), the fixed content types (ASVS 4.1.1), `content-disposition` with
  the digest (ASVS 5.4.1, 5.4.2), the private cache rule also for a `vsn=`
  query (ASVS 14.2.2), byte ranges, the quoted ETag, and the media CSP with
  `sandbox` on every answer of the route (ASVS 1.3.4, 3.2.1).
  """
  # The tests write delivery files and posters into the shared media store.
  use EspalierWeb.ConnCase, async: false

  import Ecto.Query
  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import Espalier.LearningFixtures, only: [publish_demo!: 0]

  alias Espalier.Accounts.Scope
  alias Espalier.Catalog.Program
  alias Espalier.Media.{Asset, Store}
  alias Espalier.{MediaFixtures, PackFixtures, Repo, Workbench}

  @moduletag :tmp_dir

  @media_csp "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; " <>
               "frame-ancestors 'none'; sandbox"

  @cache "private, max-age=31536000, immutable"

  @svg "media/release-checks.svg"
  @webm "media/assistant-demo.webm"
  @vtt "media/assistant-demo-en.vtt"

  setup %{tmp_dir: tmp_dir} do
    {author_token, _session} = session_fixture(user_with_role_fixture(:author))
    {learner_token, _session} = session_fixture(user_fixture())
    %{author: author_token, learner: learner_token, tmp_dir: tmp_dir}
  end

  describe "the session check of the pipeline :media" do
    test "answers 401 unauthenticated without a session, with the media CSP" do
      conn = get(api_conn(), "/media/#{String.duplicate("0", 64)}.webp")

      assert json_response(conn, 401) == %{"error" => "unauthenticated"}
      assert_media_answer(conn)
    end

    test "answers 401 for a known file without a session" do
      %{svg: svg} = demo_assets!()

      conn = get(api_conn(), media_path(svg))
      assert json_response(conn, 401) == %{"error" => "unauthenticated"}
      assert_media_answer(conn)
    end

    test "answers 403 enrollment_required for an enrollment session, with the media CSP" do
      %{svg: svg} = demo_assets!()

      {token, _session} =
        session_fixture(user_fixture(), strength: :enrollment, auth_methods: [:email_code])

      conn = get(conn_for(token), media_path(svg))
      assert json_response(conn, 403) == %{"error" => "enrollment_required"}
      assert_media_answer(conn)
    end
  end

  describe "the name and the authorization rule" do
    test "answers 404 for a malformed name, an upper-case digest and an unknown extension",
         %{author: author} do
      %{svg: svg} = demo_assets!()
      upper = String.upcase(svg.sha256)

      for file <- [
            "#{svg.sha256}",
            "#{svg.sha256}.",
            "#{String.slice(svg.sha256, 0, 63)}.svg",
            "#{svg.sha256}0.svg",
            "#{upper}.svg",
            "#{svg.sha256}.SVG",
            "#{svg.sha256}.png",
            "#{svg.sha256}.svgz",
            "#{svg.sha256}.svg.webp",
            "x#{svg.sha256}.svg",
            "readme.txt",
            "..%2F..%2Fconfig%2Fconfig.exs"
          ] do
        conn = get(conn_for(author), "/media/" <> file)
        assert json_response(conn, 404) == %{"error" => "not_found"}, file
        assert_media_answer(conn)
      end
    end

    test "answers 404 for a path below the file name", %{author: author} do
      %{svg: svg} = demo_assets!()
      <<aa::binary-size(2), bb::binary-size(2), _rest::binary>> = svg.sha256

      conn = get(conn_for(author), "/media/#{aa}/#{bb}/#{svg.sha256}.svg")
      assert conn.status == 404
      refute conn.resp_body == File.read!(Store.path(svg.sha256, "svg"))
    end

    test "answers 404 for a digest with the extension of another type", %{author: author} do
      %{svg: svg, webm: webm, vtt: vtt} = demo_assets!()

      for {asset, ext} <- [
            {svg, "webp"},
            {svg, "webm"},
            {webm, "svg"},
            {webm, "webp"},
            {vtt, "webm"}
          ] do
        conn = get(conn_for(author), "/media/#{asset.sha256}.#{ext}")
        assert json_response(conn, 404) == %{"error" => "not_found"}, "#{asset.ext} as #{ext}"
        assert_media_answer(conn)
      end
    end

    test "answers 404 for an unknown digest", %{author: author} do
      conn = get(conn_for(author), "/media/#{MediaFixtures.random_sha256()}.svg")
      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert_media_answer(conn)
    end

    test "answers 404 for an asset that is not ready, also to an author", %{
      author: author,
      tmp_dir: tmp_dir
    } do
      asset = own_svg!(tmp_dir, "#0f766e")

      for status <- [:queued, :processing, :failed] do
        set_status!(asset, status)

        conn = get(conn_for(author), media_path(asset))
        assert json_response(conn, 404) == %{"error" => "not_found"}, Atom.to_string(status)
        assert_media_answer(conn)
      end

      set_status!(asset, :ready)
      assert get(conn_for(author), media_path(asset)).status == 200
    end

    test "answers 404 for a ready asset whose file is missing in the store", %{author: author} do
      sha256 = MediaFixtures.random_sha256()

      Repo.insert!(%Asset{
        kind: :svg,
        status: :ready,
        title: "missing",
        source_sha256: MediaFixtures.random_sha256(),
        sha256: sha256,
        ext: "svg",
        bytes: 10,
        origin: :upload
      })

      conn = get(conn_for(author), "/media/#{sha256}.svg")
      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert_media_answer(conn)
    end

    test "answers 404 to a learner when no published program uses the asset, 200 to an author",
         %{author: author, learner: learner, tmp_dir: tmp_dir} do
      demo_assets!()
      asset = own_svg!(tmp_dir, "#1d4ed8")

      conn = get(conn_for(learner), media_path(asset))
      assert json_response(conn, 404) == %{"error" => "not_found"}
      assert_media_answer(conn)

      conn = get(conn_for(author), media_path(asset))
      assert conn.status == 200
      assert conn.resp_body == File.read!(Store.path(asset.sha256, "svg"))
    end

    test "answers 404 to a learner for the files of a program that is not published", %{
      learner: learner
    } do
      %{program: program, svg: svg, webm: webm} = demo_assets!()

      Repo.update_all(
        from(p in Program, where: p.id == ^program.id),
        set: [status: :archived]
      )

      for asset <- [svg, webm] do
        conn = get(conn_for(learner), media_path(asset))
        assert json_response(conn, 404) == %{"error" => "not_found"}
        assert_media_answer(conn)
      end
    end

    test "answers 404 to a learner for an asset that only a draft uses", %{
      learner: learner,
      tmp_dir: tmp_dir
    } do
      asset = own_svg!(tmp_dir, "#7c3aed")
      author = user_with_role_fixture(:author)
      scope = %{Scope.for_user(author) | roles: [:learner, :author]}
      {:ok, draft} = Workbench.create_empty(scope, "Draft with media")

      {:ok, _draft} =
        Workbench.attach_media(
          scope,
          draft.id,
          %{media_asset_id: asset.id, path: "media/diagram.svg"},
          draft.lock_version
        )

      conn = get(conn_for(learner), media_path(asset))
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end
  end

  describe "serving" do
    test "serves every type with its headers to an author", %{
      author: author,
      tmp_dir: tmp_dir
    } do
      %{svg: svg, webm: webm, vtt: vtt} = assets = demo_assets!()
      poster = put_poster!(assets.webm, tmp_dir)

      for {sha256, ext, type} <- [
            {svg.sha256, "svg", "image/svg+xml; charset=utf-8"},
            {webm.sha256, "webm", "video/webm"},
            {vtt.sha256, "vtt", "text/vtt; charset=utf-8"},
            {poster, "webp", "image/webp"}
          ] do
        conn = get(conn_for(author), "/media/#{sha256}.#{ext}")
        assert_served(conn, sha256, ext, type)
      end
    end

    test "serves the files of a published program to a learner", %{
      learner: learner,
      tmp_dir: tmp_dir
    } do
      %{svg: svg, webm: webm, vtt: vtt} = assets = demo_assets!()
      poster = put_poster!(assets.webm, tmp_dir)

      for {sha256, ext, type} <- [
            {svg.sha256, "svg", "image/svg+xml; charset=utf-8"},
            {webm.sha256, "webm", "video/webm"},
            {vtt.sha256, "vtt", "text/vtt; charset=utf-8"},
            {poster, "webp", "image/webp"}
          ] do
        conn = get(conn_for(learner), "/media/#{sha256}.#{ext}")
        assert_served(conn, sha256, ext, type)
      end
    end

    test "keeps the private cache rule and the ETag with ?vsn=1", %{author: author} do
      %{svg: svg, webm: webm} = demo_assets!()

      for asset <- [svg, webm] do
        conn = get(conn_for(author), media_path(asset) <> "?vsn=1")
        assert conn.status == 200
        assert get_resp_header(conn, "cache-control") == [@cache]
        assert get_resp_header(conn, "etag") == [~s("#{asset.sha256}")]
        assert_media_answer(conn)
      end
    end

    test "answers 206 with content-range for Range: bytes=0-99", %{
      author: author,
      learner: learner
    } do
      %{svg: svg, webm: webm} = demo_assets!()

      for token <- [author, learner], asset <- [svg, webm] do
        file = Store.path(asset.sha256, asset.ext)
        size = File.stat!(file).size

        conn =
          token
          |> conn_for()
          |> put_req_header("range", "bytes=0-99")
          |> get(media_path(asset))

        assert conn.status == 206
        assert get_resp_header(conn, "content-range") == ["bytes 0-99/#{size}"]
        assert conn.resp_body == binary_part(File.read!(file), 0, 100)
        assert get_resp_header(conn, "accept-ranges") == ["bytes"]
        assert get_resp_header(conn, "cache-control") == [@cache]
        assert_media_answer(conn)
      end
    end

    test "answers a later range of the video with 206", %{author: author} do
      %{webm: webm} = demo_assets!()
      file = Store.path(webm.sha256, "webm")
      size = File.stat!(file).size

      conn =
        author
        |> conn_for()
        |> put_req_header("range", "bytes=500000-")
        |> get(media_path(webm))

      assert conn.status == 206
      assert get_resp_header(conn, "content-range") == ["bytes 500000-#{size - 1}/#{size}"]
      assert byte_size(conn.resp_body) == size - 500_000
      assert_media_answer(conn)
    end

    test "answers 416 for an unsatisfiable range", %{author: author} do
      %{svg: svg} = demo_assets!()
      size = File.stat!(Store.path(svg.sha256, "svg")).size

      conn =
        author
        |> conn_for()
        |> put_req_header("range", "bytes=#{size + 10}-")
        |> get(media_path(svg))

      assert conn.status == 416
      assert get_resp_header(conn, "content-range") == ["bytes */#{size}"]
      assert conn.resp_body == ""
      assert_media_answer(conn)
    end

    test "answers 304 for If-None-Match with the quoted ETag", %{
      author: author,
      learner: learner
    } do
      %{svg: svg, vtt: vtt} = demo_assets!()

      for token <- [author, learner], asset <- [svg, vtt] do
        conn =
          token
          |> conn_for()
          |> put_req_header("if-none-match", ~s("#{asset.sha256}"))
          |> get(media_path(asset))

        assert conn.status == 304
        assert conn.resp_body == ""
        assert get_resp_header(conn, "etag") == [~s("#{asset.sha256}")]
        assert get_resp_header(conn, "cache-control") == [@cache]
        assert_media_answer(conn)
      end

      # Another entity tag serves the file.
      conn =
        author
        |> conn_for()
        |> put_req_header("if-none-match", ~s("#{MediaFixtures.random_sha256()}"))
        |> get(media_path(svg))

      assert conn.status == 200
    end

    test "a HEAD request answers like GET without a body", %{author: author} do
      %{svg: svg} = demo_assets!()

      conn = head(conn_for(author), media_path(svg))
      assert conn.status == 200
      assert conn.resp_body == ""
      assert get_resp_header(conn, "content-type") == ["image/svg+xml; charset=utf-8"]
      assert_media_answer(conn)
    end
  end

  describe "Sec-Fetch-Dest and Sec-Fetch-Site" do
    test "passes the destinations that fit the type", %{author: author, tmp_dir: tmp_dir} do
      %{svg: svg, webm: webm, vtt: vtt} = assets = demo_assets!()
      poster = put_poster!(assets.webm, tmp_dir)

      for {path, destinations} <- [
            {media_path(svg), ["image", "document"]},
            {"/media/#{poster}.webp", ["image", "document"]},
            {media_path(webm), ["video", "audio", "document"]},
            {media_path(vtt), ["track", "document"]}
          ],
          dest <- destinations do
        conn = author |> conn_for() |> put_req_header("sec-fetch-dest", dest) |> get(path)
        assert conn.status == 200, "#{path} as #{dest}"
        assert_media_answer(conn)
      end
    end

    test "answers 404 for a destination that does not fit the type", %{
      author: author,
      tmp_dir: tmp_dir
    } do
      %{svg: svg, webm: webm, vtt: vtt} = assets = demo_assets!()
      poster = put_poster!(assets.webm, tmp_dir)

      for {path, destinations} <- [
            {media_path(svg),
             ["script", "iframe", "video", "audio", "track", "object", "embed", "style", "empty"]},
            {"/media/#{poster}.webp", ["script", "iframe", "video", "worker"]},
            {media_path(webm), ["image", "script", "iframe", "track", "empty"]},
            {media_path(vtt), ["script", "image", "video", "style", "empty"]}
          ],
          dest <- destinations do
        conn = author |> conn_for() |> put_req_header("sec-fetch-dest", dest) |> get(path)
        assert json_response(conn, 404) == %{"error" => "not_found"}, "#{path} as #{dest}"
        assert_media_answer(conn)
      end
    end

    test "answers a cross-site request as the Fetch Metadata plug answers", %{
      author: author,
      learner: learner
    } do
      %{svg: svg, webm: webm} = demo_assets!()

      for token <- [author, learner],
          {asset, dest, mode} <- [
            {svg, "image", "no-cors"},
            {webm, "video", "no-cors"},
            {svg, "document", "navigate"}
          ] do
        conn =
          token
          |> conn_for()
          |> put_req_header("sec-fetch-site", "cross-site")
          |> put_req_header("sec-fetch-dest", dest)
          |> put_req_header("sec-fetch-mode", mode)
          |> get(media_path(asset))

        assert json_response(conn, 403) == %{"error" => "cross_site_request"}
        assert_media_answer(conn)
      end

      # Same-site requests pass, as the plug lets them pass.
      conn =
        author
        |> conn_for()
        |> put_req_header("sec-fetch-site", "same-site")
        |> put_req_header("sec-fetch-dest", "image")
        |> get(media_path(svg))

      assert conn.status == 200
    end
  end

  ## Helpers

  # A conn of the browser that holds the session `token`.
  defp conn_for(token) do
    api_conn()
    |> init_test_session(%{})
    |> put_session(:user_token, token)
  end

  # The published demo program and its ready assets.
  defp demo_assets! do
    program = publish_demo!()
    mapping = MediaFixtures.media_for(PackFixtures.demo_path())

    %{
      program: program,
      svg: Repo.get!(Asset, mapping[@svg]),
      webm: Repo.get!(Asset, mapping[@webm]),
      vtt: Repo.get!(Asset, mapping[@vtt])
    }
  end

  defp media_path(%Asset{sha256: sha256, ext: ext}), do: "/media/#{sha256}.#{ext}"

  defp set_status!(%Asset{id: id}, status),
    do: Repo.update_all(from(a in Asset, where: a.id == ^id), set: [status: status])

  # A ready SVG asset of its own, used by no program.
  defp own_svg!(dir, color) do
    file = Path.join(dir, "own.svg")

    File.write!(
      file,
      ~s(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">) <>
        ~s(<rect width="10" height="10" fill="#{color}"/></svg>)
    )

    MediaFixtures.stored_asset!(file, :svg, "svg", %{width: 10, height: 10})
  end

  # Stores a WebP from ffmpeg as the poster of `video` and returns its digest.
  defp put_poster!(%Asset{} = video, dir) do
    file = Path.join(dir, "poster.webp")

    {output, status} =
      System.cmd(
        System.find_executable("ffmpeg"),
        ~w(-nostdin -hide_banner -v error -f lavfi -i color=c=0x334155:s=64x36 -frames:v 1) ++
          ~w(-c:v libwebp -quality 80 -f webp -y) ++ [file],
        stderr_to_stdout: true
      )

    assert status == 0, output

    {sha256, bytes} = Store.digest(file)
    target = Store.path(sha256, "webp")
    File.mkdir_p!(Path.dirname(target))
    unless File.regular?(target), do: File.cp!(file, target)

    video |> Ecto.Changeset.change(poster_sha256: sha256, poster_bytes: bytes) |> Repo.update!()
    sha256
  end

  defp assert_served(conn, sha256, ext, type) do
    file = "#{sha256}.#{ext}"
    assert conn.status == 200, file
    assert conn.resp_body == File.read!(Store.path(sha256, ext)), file
    assert get_resp_header(conn, "content-type") == [type], file
    assert get_resp_header(conn, "content-disposition") == [~s(inline; filename="#{file}")]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cross-origin-resource-policy") == ["same-origin"]
    assert get_resp_header(conn, "cache-control") == [@cache]
    assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    assert get_resp_header(conn, "etag") == [~s("#{sha256}")]
    assert_media_answer(conn)
  end

  # Every answer of the route carries the media CSP, the other security
  # headers, and no no-store.
  defp assert_media_answer(conn) do
    assert get_resp_header(conn, "content-security-policy") == [@media_csp]
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "cross-origin-resource-policy") == ["same-origin"]
    refute Enum.any?(get_resp_header(conn, "cache-control"), &(&1 =~ "no-store"))
  end
end
