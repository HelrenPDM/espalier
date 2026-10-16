defmodule EspalierWeb.Admin.MediaNamesTest do
  @moduledoc """
  The titles and source names of the media library routes (task 0018,
  steps 3, 8 and 15) for names whose characters take more than one code
  point: decomposed letters as macOS writes them (NFD), conjoining Hangul
  jamo, stacked combining marks and emoji sequences. The columns `title`
  and `source_name` are `varchar(255)`, and PostgreSQL counts their length
  in code points. An upload cuts the title and the source name at a
  grapheme boundary within 255 code points and leaves no incoming file
  behind; `PATCH` answers 422 for a title above 255 code points.
  """
  # The upload runs the real ingest, which takes the advisory lock of the
  # quota and writes the media store, and the tests point MEDIA_DIR at a
  # directory of their own.
  use EspalierWeb.ConnCase, async: false

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]

  alias Espalier.Media.{Asset, Store}
  alias Espalier.{MediaFixtures, Repo}

  setup %{conn: conn} do
    MediaFixtures.media_env!()
    %{conn: log_in_user(conn, user_with_role_fixture(:author))}
  end

  defp code_points(text), do: text |> String.codepoints() |> length()

  defp incoming_names do
    case File.ls(Store.incoming_root()) do
      {:ok, names} -> Enum.sort(names)
      {:error, :enoent} -> []
    end
  end

  describe "POST /api/admin/media with a long name" do
    test "cuts the title and the source name at a grapheme within 255 code points and leaves no other incoming file",
         %{conn: conn} do
      nfd_e = "e\u0301"
      hangul = "\u1112\u1161\u11AB"
      stacked = "a\u0300\u0301\u0302"
      family = "\u{1F468}\u200D\u{1F469}\u200D\u{1F467}\u200D\u{1F466}"

      # {grapheme, code points per grapheme, count in the file name,
      # graphemes of the title, graphemes of the source name}
      cases = [
        {nfd_e, 2, 130, 127, 125},
        {hangul, 3, 90, 85, 83},
        {stacked, 4, 70, 63, 62},
        {family, 7, 100, 36, 35}
      ]

      ids =
        for {{grapheme, size, count, in_title, in_source}, n} <- Enum.with_index(cases) do
          name = String.duplicate(grapheme, count) <> ".png"
          assert String.length(name) <= 255
          assert code_points(name) == size * count + 4

          png = MediaFixtures.png(4 + n, 3)
          conn = upload_request(conn, "/api/admin/media", png, filename: name)
          body = json_response(conn, 201)

          assert body["title"] == String.duplicate(grapheme, in_title)
          assert body["source_name"] == String.duplicate(grapheme, in_source) <> ".png"
          assert code_points(body["title"]) <= 255
          assert code_points(body["source_name"]) <= 255

          # One more grapheme would cross the limit.
          assert code_points(body["title"]) + size > 255
          assert code_points(body["source_name"]) + size > 255

          asset = Repo.get!(Asset, body["id"])
          assert asset.title == body["title"]
          assert asset.source_name == body["source_name"]
          body["id"]
        end

      assert incoming_names() == Enum.sort(ids)
    end
  end

  describe "PATCH /api/admin/media/:id with a long title" do
    test "answers 422 above 255 code points, also within 255 graphemes, and 200 at 255", %{
      conn: conn
    } do
      asset = MediaFixtures.insert_asset!(%{title: "Kept"})
      path = "/api/admin/media/#{asset.id}"

      for title <- [
            String.duplicate("e\u0301", 200),
            String.duplicate("e\u0301", 128),
            String.duplicate("\u{1F468}\u200D\u{1F469}\u200D\u{1F467}", 100)
          ] do
        assert String.length(title) <= 255
        conn = json_request(conn, :patch, path, %{title: title})

        assert json_response(conn, 422) == %{
                 "error" => "validation_failed",
                 "fields" => %{"title" => ["length"]}
               }
      end

      assert Repo.get!(Asset, asset.id).title == "Kept"

      title = String.duplicate("e\u0301", 127) <> "a"
      assert code_points(title) == 255
      conn = json_request(conn, :patch, path, %{title: title})
      assert json_response(conn, 200)["title"] == title
      assert Repo.get!(Asset, asset.id).title == title
    end
  end
end
