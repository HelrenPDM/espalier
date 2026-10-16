defmodule Espalier.WorkbenchTest do
  @moduledoc """
  The context of task 0016a (`Espalier.Workbench`), step 14:

    * schemas and limits (steps 2 and 3; ASVS 2.1.3, 2.3.2, 5.2.2 and
      15.3.3): the limit functions, the content rules, the file, byte and
      draft limits, `created_by_id` after the deletion of its user, and the
      deletion of the files with their draft;
    * the reads and the file changes of step 4 with the role check and the
      answers on unknown and malformed ids, the optimistic locking in its
      sequential form (the concurrent form is
      `Espalier.Workbench.ConcurrencyTest`), and the title and pack key that
      follow `pack.yaml`;
    * the starting points of step 5 without the zip upload: the skeleton,
      the published program with the round trip to an import, and the
      import with and without a payload;
    * the download of step 8 at context level;
    * the audit events of step 10 (ASVS 2.3.3): `pack_draft.created` and
      `pack_draft.deleted` with actor, subject and details, and no event for
      a file change;
    * the media of task 0018 (step 16; ASVS 2.3.2 and 2.3.3): the media
      entries with their `lock_version`, path rules and limits, a captions
      asset as a text file, the media of the starting points, the check
      and the import with the mapping of the entries, and the staged
      download with hard links to the store, an asset deleted during the
      download, `download_too_large` and `media_not_ready`.
  """
  # The tests change application settings, which every process reads.
  use Espalier.DataCase, async: false

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import Espalier.PackFixtures, only: [demo_path: 0]

  alias Espalier.Accounts.Scope
  alias Espalier.{AccountsFixtures, Catalog, Media, MediaFixtures, Workbench}
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.Pack.{Loader, Validator}
  alias Espalier.Catalog.{PackImport, Program}
  alias Espalier.Interop.{PackWriter, Payload}
  alias Espalier.Media.{Asset, Store}
  alias Espalier.Workbench.{PackDraft, PackDraftFile, PackDraftMedia}
  alias EspalierWeb.PackMultipart

  # The six files of the skeleton for the name "New pack" (step 5).
  @skeleton %{
    "pack.yaml" => ~S"""
    schema: 1
    key: new-pack
    title: New pack
    locale: en
    license: CC0-1.0
    version: "0.1.0"
    alignment: strict
    """,
    "stations.yaml" => ~S"""
    - kind: overview
      title: Overview
      config:
        intro: Replace this introduction with the purpose of the pack.
    - kind: module
      title: First module
      module: 1
      config: {}
    """,
    "modules/01-first-module/module.yaml" => ~S"""
    number: 1
    title: First module
    summary: Replace this summary with what learners do in the module.
    phases:
      - understand
    domains: []
    single_path: false
    refresher_unit: false
    """,
    "modules/01-first-module/objectives.yaml" => ~S"""
    - key: m1-subject
      statement: Learners can name the subject of this module.
      area: subject
      depth: know
      phase: understand
      taught_in:
        - 01-first-lesson
    - key: m1-method
      statement: Learners can name the method that this module practises.
      area: method
      depth: know
      phase: understand
      taught_in:
        - 01-first-lesson
    - key: m1-self
      statement: Learners can name what this module asks of their own work.
      area: self
      depth: know
      phase: understand
      taught_in:
        - 01-first-lesson
    - key: m1-social
      statement: Learners can name what this module asks of their work with others.
      area: social
      depth: know
      phase: understand
      taught_in:
        - 01-first-lesson
    """,
    "modules/01-first-module/items.yaml" => ~S"""
    - key: m1-first-question
      kind: single_choice
      lesson: 01-first-lesson
      stem: Replace this question with a question on the first lesson.
      core: false
      phase: understand
      provenance: invented
      objectives:
        - m1-method
        - m1-self
        - m1-social
        - m1-subject
      rules: []
      reveals: []
      options:
        - key: a
          label: The correct answer
          correct: true
          feedback: Replace this feedback.
        - key: b
          label: A wrong answer
          correct: false
          feedback: Replace this feedback.
    """,
    "modules/01-first-module/lessons/01-first-lesson.md" => ~S"""
    ---
    title: First lesson
    position: 1
    ---

    :::text{provenance=invented}
    Replace this text with the first lesson.
    :::
    """
  }

  @lesson_dir "modules/01-first-module/lessons/"

  # The media entries of a draft of the demo pack; its captions are a text
  # file (task 0018, step 16).
  @demo_entry_paths ["media/assistant-demo.webm", "media/release-checks.svg"]

  setup do
    author = user_with_role_fixture(:author)
    %{author: author, scope: author_scope(author)}
  end

  defp author_scope(user), do: %{Scope.for_user(user) | roles: [:learner, :author]}

  # Sets an application setting for one test and restores it on exit.
  defp put_setting(key, value) do
    previous = Application.fetch_env(:espalier, key)
    Application.put_env(:espalier, key, value)
    on_exit(fn -> restore_setting(key, previous) end)
  end

  # Removes an application setting for one test, so that its default
  # applies, and restores it on exit.
  defp delete_setting(key) do
    previous = Application.fetch_env(:espalier, key)
    Application.delete_env(:espalier, key)
    on_exit(fn -> restore_setting(key, previous) end)
  end

  defp restore_setting(key, {:ok, value}), do: Application.put_env(:espalier, key, value)
  defp restore_setting(key, :error), do: Application.delete_env(:espalier, key)

  defp draft!(scope, name \\ "New pack") do
    {:ok, %PackDraft{} = draft} = Workbench.create_empty(scope, name)
    draft
  end

  defp file!(draft, path), do: Enum.find(draft.files, &(&1.path == path)) || flunk("no #{path}")

  # The stored files of a draft as a map of path to content.
  defp stored(draft_id) do
    Repo.all(
      from f in PackDraftFile, where: f.pack_draft_id == ^draft_id, select: {f.path, f.content}
    )
    |> Map.new()
  end

  defp lock_version(draft_id), do: Repo.get!(PackDraft, draft_id).lock_version

  defp lesson(name), do: @lesson_dir <> name <> ".md"

  defp audit_events(action) do
    Repo.all(from e in AuditEvent, where: e.action == ^action, order_by: e.inserted_at)
  end

  # The import of the demo pack with the media of MediaFixtures, which needs
  # no ffmpeg (task 0018, step 23).
  defp import_demo!(scope) do
    {:ok, %PackImport{status: :validated} = pack_import} =
      Catalog.import_pack(scope, demo_path(), media: demo_media())

    pack_import
  end

  defp publish_demo!(scope) do
    pack_import = import_demo!(scope)
    {:ok, %PackImport{status: :published}} = Catalog.publish_pack(scope, pack_import)
    %Program{status: :published} = Catalog.get_program_by_slug(pack_import.pack_key)
  end

  defp demo_media, do: MediaFixtures.media_for(demo_path())

  # The captions of the demo pack as {path, content}: a draft of the demo
  # pack holds them as a text file.
  defp demo_captions do
    path = "media/assistant-demo-en.vtt"
    {path, File.read!(Path.join(demo_path(), path))}
  end

  # The media entries that a draft of the demo pack holds, as {path, asset
  # id}.
  defp demo_entries do
    media = demo_media()
    for path <- @demo_entry_paths, do: {path, media[path]}
  end

  defp media_pairs(%PackDraft{media: media}), do: Enum.map(media, &{&1.path, &1.media_asset_id})

  # Downloads the draft and reads the zip in the function of the download,
  # where the controller sends it; the staging directory is gone afterwards.
  defp download!(scope, draft_id) do
    assert {:ok, {name, entries, dir}} =
             Workbench.download(scope, draft_id, fn %{name: name, path: path, dir: dir} ->
               assert Path.dirname(path) == dir
               {:ok, {name, unzip!(path), dir}}
             end)

    refute File.exists?(dir)
    {name, entries}
  end

  # The function of a download that must not build a zip.
  defp no_zip(_zip), do: flunk("the download built a zip")

  defp unzip!(path) do
    {:ok, entries} = :zip.unzip(String.to_charlist(path), [:memory])
    Enum.map(entries, fn {name, content} -> {List.to_string(name), content} end)
  end

  # The directories below MEDIA_DIR/work, among them the staging directories
  # of the downloads.
  defp work_dirs, do: Store.work_root() |> Path.join("*") |> Path.wildcard() |> Enum.sort()

  # A ready asset of `kind` whose delivery file holds `content`, unique per
  # call unless `content` is given.
  defp asset!(kind, content \\ nil) do
    ext = Media.delivery_ext(kind)
    content = content || "#{kind} #{System.unique_integer([:positive])} #{random()}"
    file = Path.join(System.tmp_dir!(), "espalier-asset-#{random()}.#{ext}")
    File.write!(file, content)
    on_exit(fn -> File.rm(file) end)
    MediaFixtures.stored_asset!(file, kind, ext, %{width: 64, height: 48})
  end

  defp queued_asset!(kind) do
    Repo.insert!(%Asset{
      kind: kind,
      status: :queued,
      title: "A queued asset",
      source_sha256: MediaFixtures.random_sha256(),
      incoming_bytes: 1,
      progress: 0,
      origin: :upload
    })
  end

  # Sets the asset to failed with the failure code `failure`.
  defp fail!(%Asset{id: id}, failure) do
    {1, _rows} =
      Repo.update_all(from(a in Asset, where: a.id == ^id),
        set: [status: :failed, failure: failure]
      )
  end

  defp random, do: 8 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  defp attach!(scope, draft, asset, path) do
    assert {:ok, %PackDraft{} = draft} =
             Workbench.attach_media(
               scope,
               draft.id,
               %{media_asset_id: asset.id, path: path},
               draft.lock_version
             )

    draft
  end

  describe "limits" do
    test "the limit functions carry the values of step 3" do
      assert Workbench.max_files() == 2_000
      assert Workbench.max_file_bytes() == 1_048_576
      assert Workbench.max_drafts() == 50
      assert Workbench.max_parallel_checks() == 2
    end

    test "the download limits of task 0018 carry their values" do
      assert Workbench.max_parallel_downloads() == 2
      assert Workbench.download_min_bytes_per_second() == 262_144
      assert Workbench.download_floor_seconds() == 60
    end

    test "max_draft_bytes/0 is five times the upload limit with the default" do
      delete_setting(:pack_upload_max_mb)

      assert Workbench.max_draft_bytes() == 5 * PackMultipart.max_bytes()
      assert Workbench.max_draft_bytes() == 104_857_600
    end

    test "max_draft_bytes/0 is five times the upload limit of 1 MB" do
      put_setting(:pack_upload_max_mb, 1)

      assert Workbench.max_draft_bytes() == 5 * PackMultipart.max_bytes()
      assert Workbench.max_draft_bytes() == 5_242_880
    end

    test "the settings of :pack_drafts raise for a value that is no positive integer" do
      keys = [
        :max_drafts,
        :max_parallel_checks,
        :max_parallel_downloads,
        :download_min_bytes_per_second,
        :download_floor_seconds
      ]

      for value <- [0, -1, "50", nil, 1.5] do
        put_setting(:pack_drafts, Enum.map(keys, &{&1, value}))

        for key <- keys do
          assert_raise ArgumentError, ~r/#{key} must be a positive integer/, fn ->
            apply(Workbench, key, [])
          end
        end
      end
    end

    test "a missing member of the setting takes its default" do
      put_setting(:pack_drafts, [])

      assert Workbench.max_drafts() == 50
      assert Workbench.max_parallel_checks() == 2
      assert Workbench.max_parallel_downloads() == 2
      assert Workbench.download_min_bytes_per_second() == 262_144
      assert Workbench.download_floor_seconds() == 60
    end

    test "a file of max_file_bytes/0 bytes is stored, and one byte more answers file_too_large",
         %{scope: scope} do
      draft = draft!(scope)
      content = String.duplicate("a", Workbench.max_file_bytes())

      assert {:ok, draft} =
               Workbench.create_file(scope, draft.id, %{path: lesson("big"), content: content}, 1)

      assert file!(draft, lesson("big")).bytes == 1_048_576
      assert stored(draft.id)[lesson("big")] == content

      too_large = content <> "a"

      assert Workbench.create_file(
               scope,
               draft.id,
               %{path: lesson("bigger"), content: too_large},
               2
             ) == {:error, :file_too_large}

      file = file!(draft, lesson("big"))

      assert Workbench.update_file(scope, draft.id, file.id, too_large, 2) ==
               {:error, :file_too_large}

      assert lock_version(draft.id) == 2
      assert stored(draft.id)[lesson("big")] == content
      refute Map.has_key?(stored(draft.id), lesson("bigger"))
    end

    test "a file of max_file_bytes/0 bytes in multibyte characters is stored", %{scope: scope} do
      draft = draft!(scope)
      # "ä" takes two bytes.
      content = String.duplicate("ä", div(Workbench.max_file_bytes(), 2))

      assert {:ok, draft} =
               Workbench.create_file(
                 scope,
                 draft.id,
                 %{path: lesson("umlaut"), content: content},
                 1
               )

      assert file!(draft, lesson("umlaut")).bytes == 1_048_576

      assert Workbench.update_file(
               scope,
               draft.id,
               file!(draft, lesson("umlaut")).id,
               content <> "ä",
               2
             ) == {:error, :file_too_large}
    end

    test "a content with U+0000 answers nul_character", %{scope: scope} do
      draft = draft!(scope)
      content = "---\ntitle: A\nposition: 2\n---\n" <> <<0>>

      assert Workbench.create_file(scope, draft.id, %{path: lesson("nul"), content: content}, 1) ==
               {:error, :nul_character}

      file = file!(draft, "pack.yaml")

      assert Workbench.update_file(scope, draft.id, file.id, content, 1) ==
               {:error, :nul_character}

      assert lock_version(draft.id) == 1
      assert stored(draft.id) == @skeleton
    end

    test "a content that is no valid UTF-8 answers invalid_encoding", %{scope: scope} do
      draft = draft!(scope)

      assert Workbench.create_file(
               scope,
               draft.id,
               %{path: lesson("latin"), content: <<0xE4>>},
               1
             ) ==
               {:error, :invalid_encoding}

      assert lock_version(draft.id) == 1
    end

    test "other control characters and an empty content are stored", %{scope: scope} do
      draft = draft!(scope)

      assert {:ok, draft} =
               Workbench.create_file(scope, draft.id, %{path: "sources.yaml", content: ""}, 1)

      assert {:ok, _draft} =
               Workbench.create_file(
                 scope,
                 draft.id,
                 %{path: "glossary.yaml", content: "- term: \u0001\u007F\n"},
                 2
               )

      assert stored(draft.id)["sources.yaml"] == ""
      assert stored(draft.id)["glossary.yaml"] == "- term: \u0001\u007F\n"
    end

    test "an invalid path answers invalid_path", %{scope: scope} do
      draft = draft!(scope)

      for path <- ["../pack.yaml", "README.md", "modules/a/lessons/x.txt", nil] do
        assert Workbench.create_file(scope, draft.id, %{path: path, content: ""}, 1) ==
                 {:error, :invalid_path}
      end

      file = file!(draft, "stations.yaml")

      assert Workbench.rename_file(scope, draft.id, file.id, "/etc/passwd", 1) ==
               {:error, :invalid_path}

      assert lock_version(draft.id) == 1
    end

    test "the 2,001st file answers too_many_files", %{scope: scope} do
      draft = draft!(scope)
      now = DateTime.utc_now(:second)
      # The skeleton holds six files; 1,993 more give 1,999.
      rows =
        for n <- 1..1_993 do
          %{
            id: Ecto.UUID.generate(),
            pack_draft_id: draft.id,
            path: lesson("filler-#{n}"),
            content: "",
            inserted_at: now,
            updated_at: now
          }
        end

      {1_993, nil} = Repo.insert_all(PackDraftFile, rows)

      assert {:ok, %PackDraft{file_count: 2_000, lock_version: 2}} =
               Workbench.create_file(scope, draft.id, %{path: lesson("last"), content: ""}, 1)

      assert Workbench.create_file(scope, draft.id, %{path: lesson("one-more"), content: ""}, 2) ==
               {:error, :too_many_files}

      assert lock_version(draft.id) == 2

      assert Repo.aggregate(from(f in PackDraftFile, where: f.pack_draft_id == ^draft.id), :count) ==
               2_000

      # A change that adds no file still passes at the limit.
      {:ok, draft} = Workbench.get_draft(scope, draft.id)
      file = file!(draft, lesson("last"))

      assert {:ok, %PackDraft{file_count: 2_000}} =
               Workbench.update_file(scope, draft.id, file.id, "---\n", 2)

      assert {:ok, %PackDraft{file_count: 1_999}} =
               Workbench.delete_file(scope, draft.id, file.id, 3)
    end

    test "a content that takes the draft above max_draft_bytes/0 answers draft_too_large",
         %{scope: scope} do
      put_setting(:pack_upload_max_mb, 1)
      max = Workbench.max_draft_bytes()
      assert max == 5 * 1_048_576

      draft = draft!(scope)
      mib = String.duplicate("a", 1_048_576)

      draft =
        Enum.reduce(1..4, draft, fn n, draft ->
          {:ok, draft} =
            Workbench.create_file(
              scope,
              draft.id,
              %{path: lesson("mib-#{n}"), content: mib},
              draft.lock_version
            )

          draft
        end)

      # The draft is filled up to its limit exactly.
      rest = max - draft.bytes
      assert rest in 1..1_048_576

      assert {:ok, %PackDraft{lock_version: 6} = draft} =
               Workbench.create_file(
                 scope,
                 draft.id,
                 %{path: lesson("rest"), content: String.duplicate("a", rest)},
                 5
               )

      assert draft.bytes == max

      assert Workbench.create_file(scope, draft.id, %{path: lesson("one-byte"), content: "a"}, 6) ==
               {:error, :draft_too_large}

      file = file!(draft, lesson("rest"))

      assert Workbench.update_file(scope, draft.id, file.id, String.duplicate("a", rest + 1), 6) ==
               {:error, :draft_too_large}

      assert lock_version(draft.id) == 6
      assert stored(draft.id) |> Map.values() |> Enum.map(&byte_size/1) |> Enum.sum() == max

      # A change that shrinks the draft passes.
      assert {:ok, %PackDraft{lock_version: 7, bytes: bytes}} =
               Workbench.update_file(scope, draft.id, file.id, "", 6)

      assert bytes == max - rest
    end

    test "the 51st draft answers draft_limit", %{scope: scope} do
      now = DateTime.utc_now(:second)

      rows =
        for n <- 1..49 do
          %{
            id: Ecto.UUID.generate(),
            title: "Draft #{n}",
            lock_version: 1,
            inserted_at: now,
            updated_at: now
          }
        end

      {49, nil} = Repo.insert_all(PackDraft, rows)

      assert {:ok, %PackDraft{}} = Workbench.create_empty(scope, "The fiftieth")
      assert Repo.aggregate(PackDraft, :count) == 50

      assert Workbench.create_empty(scope, "The fifty-first") == {:error, :draft_limit}
      assert Repo.aggregate(PackDraft, :count) == 50
      assert Repo.aggregate(PackDraftFile, :count) == 6
      assert [_one] = audit_events("pack_draft.created")
    end

    test "a lowered max_drafts/0 applies to the next creation", %{scope: scope} do
      put_setting(:pack_drafts, max_drafts: 1, max_parallel_checks: 2)

      assert {:ok, _draft} = Workbench.create_empty(scope, "Only")
      assert Workbench.create_empty(scope, "Second") == {:error, :draft_limit}
    end
  end

  describe "schemas" do
    test "a deleted user leaves the draft with created_by_id nil", %{author: author, scope: scope} do
      draft = draft!(scope)
      assert Repo.get!(PackDraft, draft.id).created_by_id == author.id

      assert {:ok, _user} = Repo.delete(author)

      assert %PackDraft{created_by_id: nil} = Repo.get!(PackDraft, draft.id)
      assert map_size(stored(draft.id)) == 6
    end

    test "delete_draft/2 deletes the draft with its files", %{scope: scope} do
      draft = draft!(scope)
      other = draft!(scope, "Other pack")

      assert {:ok, %PackDraft{id: id}} = Workbench.delete_draft(scope, draft.id)
      assert id == draft.id

      assert Repo.get(PackDraft, draft.id) == nil
      assert Repo.all(from f in PackDraftFile, where: f.pack_draft_id == ^draft.id) == []
      assert map_size(stored(other.id)) == 6

      assert Workbench.delete_draft(scope, draft.id) == {:error, :not_found}
    end

    test "the changeset of a file casts path and content only" do
      draft_id = Ecto.UUID.generate()

      changeset =
        PackDraftFile.changeset(%PackDraftFile{}, %{
          "path" => "pack.yaml",
          "content" => "schema: 1\n",
          "pack_draft_id" => draft_id,
          "id" => draft_id
        })

      assert changeset.valid?
      assert Map.keys(changeset.changes) |> Enum.sort() == [:content, :path]
    end
  end

  describe "role and ids" do
    setup %{scope: scope} do
      draft = draft!(scope)
      %{draft: draft, stations: file!(draft, "stations.yaml")}
    end

    test "every public function answers forbidden for a scope without the role author", %{
      draft: draft,
      stations: file,
      scope: scope
    } do
      {:ok, %PackImport{} = pack_import} = Catalog.import_pack(scope, demo_path())
      learner = Scope.for_user(AccountsFixtures.user_fixture())
      admin = %{Scope.for_user(AccountsFixtures.user_fixture()) | roles: [:learner, :admin]}

      for denied <- [learner, admin, Scope.system()] do
        assert Workbench.list_drafts(denied) == {:error, :forbidden}
        assert Workbench.get_draft(denied, draft.id) == {:error, :forbidden}
        assert Workbench.get_file(denied, draft.id, file.id) == {:error, :forbidden}

        assert Workbench.create_file(denied, draft.id, %{path: "sources.yaml", content: ""}, 1) ==
                 {:error, :forbidden}

        assert Workbench.update_file(denied, draft.id, file.id, "[]\n", 1) == {:error, :forbidden}

        assert Workbench.rename_file(denied, draft.id, file.id, "formats.yaml", 1) ==
                 {:error, :forbidden}

        assert Workbench.delete_file(denied, draft.id, file.id, 1) == {:error, :forbidden}
        assert Workbench.delete_draft(denied, draft.id) == {:error, :forbidden}
        assert Workbench.create_empty(denied, "New pack") == {:error, :forbidden}

        assert Workbench.create_from_program(denied, "ai-assistant-basics-demo") ==
                 {:error, :forbidden}

        assert Workbench.create_from_import(denied, pack_import.id) == {:error, :forbidden}

        assert Workbench.create_from_upload(denied, "/nonexistent.zip", "pack.zip", 1_048_576) ==
                 {:error, :forbidden}

        assert Workbench.check_draft(denied, draft.id, nil) == {:error, :forbidden}
        assert Workbench.import_draft(denied, draft.id, 1) == {:error, :forbidden}
        assert Workbench.download(denied, draft.id, &no_zip/1) == {:error, :forbidden}
      end

      assert %PackDraft{lock_version: 1} = Repo.get!(PackDraft, draft.id)
      assert stored(draft.id) == @skeleton
      assert Repo.aggregate(PackDraft, :count) == 1
      assert Repo.aggregate(PackImport, :count) == 1
      assert audit_events("pack_draft.deleted") == []
    end

    test "a malformed id answers not_found", %{draft: draft, stations: file, scope: scope} do
      for bad <- ["not-a-uuid", "", 42, nil, "#{draft.id}x"] do
        assert Workbench.get_draft(scope, bad) == {:error, :not_found}
        assert Workbench.get_file(scope, bad, file.id) == {:error, :not_found}
        assert Workbench.get_file(scope, draft.id, bad) == {:error, :not_found}

        assert Workbench.create_file(scope, bad, %{path: "sources.yaml", content: ""}, 1) ==
                 {:error, :not_found}

        assert Workbench.update_file(scope, bad, file.id, "[]\n", 1) == {:error, :not_found}
        assert Workbench.update_file(scope, draft.id, bad, "[]\n", 1) == {:error, :not_found}

        assert Workbench.rename_file(scope, bad, file.id, "formats.yaml", 1) ==
                 {:error, :not_found}

        assert Workbench.rename_file(scope, draft.id, bad, "formats.yaml", 1) ==
                 {:error, :not_found}

        assert Workbench.delete_file(scope, bad, file.id, 1) == {:error, :not_found}
        assert Workbench.delete_file(scope, draft.id, bad, 1) == {:error, :not_found}
        assert Workbench.delete_draft(scope, bad) == {:error, :not_found}
        assert Workbench.create_from_import(scope, bad) == {:error, :not_found}
        assert Workbench.check_draft(scope, bad, nil) == {:error, :not_found}
        assert Workbench.import_draft(scope, bad, 1) == {:error, :not_found}
        assert Workbench.download(scope, bad, &no_zip/1) == {:error, :not_found}
      end

      assert lock_version(draft.id) == 1
    end

    test "an unknown id answers not_found", %{draft: draft, stations: file, scope: scope} do
      unknown = Ecto.UUID.generate()

      assert Workbench.get_draft(scope, unknown) == {:error, :not_found}
      assert Workbench.get_file(scope, unknown, file.id) == {:error, :not_found}
      assert Workbench.get_file(scope, draft.id, unknown) == {:error, :not_found}

      assert Workbench.create_file(scope, unknown, %{path: "sources.yaml", content: ""}, 1) ==
               {:error, :not_found}

      assert Workbench.update_file(scope, draft.id, unknown, "[]\n", 1) == {:error, :not_found}

      assert Workbench.rename_file(scope, draft.id, unknown, "formats.yaml", 1) ==
               {:error, :not_found}

      assert Workbench.delete_file(scope, draft.id, unknown, 1) == {:error, :not_found}
      assert Workbench.delete_draft(scope, unknown) == {:error, :not_found}
      assert Workbench.check_draft(scope, unknown, nil) == {:error, :not_found}
      assert Workbench.import_draft(scope, unknown, 1) == {:error, :not_found}
      assert Workbench.download(scope, unknown, &no_zip/1) == {:error, :not_found}
      assert lock_version(draft.id) == 1
    end
  end

  describe "reads" do
    test "list_drafts/1 returns the drafts newest updated_at first with file_count and bytes", %{
      scope: scope
    } do
      first = draft!(scope, "First")
      second = draft!(scope, "Second")

      empty =
        Repo.insert!(%PackDraft{title: "Empty", lock_version: 1, created_by_id: nil})

      for {draft, at} <- [
            {first, ~U[2026-03-01 10:00:00Z]},
            {second, ~U[2026-01-01 10:00:00Z]},
            {empty, ~U[2026-02-01 10:00:00Z]}
          ] do
        Repo.update_all(from(d in PackDraft, where: d.id == ^draft.id), set: [updated_at: at])
      end

      {:ok, %PackDraft{} = first} =
        Workbench.create_file(scope, first.id, %{path: "sources.yaml", content: "[]\n"}, 1)

      # The change moves the draft to the top.
      assert {:ok, drafts} = Workbench.list_drafts(scope)
      assert Enum.map(drafts, & &1.id) == [first.id, empty.id, second.id]

      bytes = fn id -> stored(id) |> Map.values() |> Enum.map(&byte_size/1) |> Enum.sum() end

      assert [
               %PackDraft{file_count: 7, bytes: first_bytes, title: "First"},
               %PackDraft{file_count: 0, bytes: 0, title: "Empty"},
               %PackDraft{file_count: 6, bytes: second_bytes, title: "Second"}
             ] = drafts

      assert first_bytes == bytes.(first.id)
      assert second_bytes == bytes.(second.id)
      assert Enum.all?(drafts, &match?(%Ecto.Association.NotLoaded{}, &1.files))
    end

    test "get_draft/2 returns the files ordered by path with bytes and without content", %{
      scope: scope
    } do
      draft = draft!(scope)

      {:ok, _draft} =
        Workbench.create_file(scope, draft.id, %{path: "glossary.yaml", content: "[]\n"}, 1)

      assert {:ok, %PackDraft{} = draft} = Workbench.get_draft(scope, draft.id)

      assert Enum.map(draft.files, & &1.path) == [
               "glossary.yaml",
               "modules/01-first-module/items.yaml",
               "modules/01-first-module/lessons/01-first-lesson.md",
               "modules/01-first-module/module.yaml",
               "modules/01-first-module/objectives.yaml",
               "pack.yaml",
               "stations.yaml"
             ]

      expected = Map.put(@skeleton, "glossary.yaml", "[]\n")

      for file <- draft.files do
        assert file.content == nil
        assert file.bytes == byte_size(expected[file.path])
        assert %DateTime{} = file.updated_at
        assert is_binary(file.id)
      end

      assert draft.file_count == 7
      assert draft.bytes == expected |> Map.values() |> Enum.map(&byte_size/1) |> Enum.sum()
      assert draft.lock_version == 2
      assert draft.title == "New pack"
      assert draft.pack_key == "new-pack"
    end

    test "get_file/3 returns the draft and the file with its content, and not a file of another draft",
         %{scope: scope} do
      draft = draft!(scope)
      other = draft!(scope, "Other pack")
      file = file!(draft, "stations.yaml")

      assert {:ok, %PackDraft{id: draft_id, lock_version: 1}, found} =
               Workbench.get_file(scope, draft.id, file.id)

      assert draft_id == draft.id
      assert found.id == file.id
      assert found.path == "stations.yaml"
      assert found.content == @skeleton["stations.yaml"]
      assert found.bytes == byte_size(@skeleton["stations.yaml"])

      assert Workbench.get_file(scope, other.id, file.id) == {:error, :not_found}
      assert Workbench.update_file(scope, other.id, file.id, "[]\n", 1) == {:error, :not_found}

      assert Workbench.rename_file(scope, other.id, file.id, "formats.yaml", 1) ==
               {:error, :not_found}

      assert Workbench.delete_file(scope, other.id, file.id, 1) == {:error, :not_found}

      assert stored(draft.id) == @skeleton
      assert lock_version(draft.id) == 1
      assert lock_version(other.id) == 1
    end
  end

  describe "optimistic locking" do
    test "two updates with the same lock_version give one change and one stale_draft", %{
      scope: scope
    } do
      draft = draft!(scope)
      file = file!(draft, "stations.yaml")

      assert {:ok, %PackDraft{lock_version: 2}} =
               Workbench.update_file(scope, draft.id, file.id, "first\n", 1)

      assert Workbench.update_file(scope, draft.id, file.id, "second\n", 1) ==
               {:error, {:stale_draft, 2}}

      assert stored(draft.id)["stations.yaml"] == "first\n"
      assert lock_version(draft.id) == 2
    end

    test "every file change answers stale_draft with the stored version", %{scope: scope} do
      draft = draft!(scope)
      file = file!(draft, "stations.yaml")
      {:ok, _draft} = Workbench.update_file(scope, draft.id, file.id, "[]\n", 1)

      assert Workbench.create_file(scope, draft.id, %{path: "sources.yaml", content: ""}, 1) ==
               {:error, {:stale_draft, 2}}

      assert Workbench.rename_file(scope, draft.id, file.id, "formats.yaml", 1) ==
               {:error, {:stale_draft, 2}}

      assert Workbench.delete_file(scope, draft.id, file.id, 1) == {:error, {:stale_draft, 2}}

      assert Workbench.update_file(scope, draft.id, file.id, "x", 3) ==
               {:error, {:stale_draft, 2}}

      assert lock_version(draft.id) == 2
      assert Map.keys(stored(draft.id)) |> Enum.sort() == Map.keys(@skeleton) |> Enum.sort()
    end

    test "each change increments lock_version and sets updated_at", %{scope: scope} do
      draft = draft!(scope)
      old = ~U[2026-01-01 00:00:00Z]
      Repo.update_all(from(d in PackDraft, where: d.id == ^draft.id), set: [updated_at: old])

      assert {:ok, %PackDraft{lock_version: 2} = draft} =
               Workbench.create_file(scope, draft.id, %{path: "sources.yaml", content: ""}, 1)

      assert DateTime.compare(Repo.get!(PackDraft, draft.id).updated_at, old) == :gt
      file = file!(draft, "sources.yaml")

      assert {:ok, %PackDraft{lock_version: 3}} =
               Workbench.update_file(scope, draft.id, file.id, "[]\n", 2)

      assert {:ok, %PackDraft{lock_version: 4} = draft} =
               Workbench.rename_file(scope, draft.id, file.id, "glossary.yaml", 3)

      assert stored(draft.id)["glossary.yaml"] == "[]\n"
      refute Map.has_key?(stored(draft.id), "sources.yaml")

      assert {:ok, %PackDraft{lock_version: 5, file_count: 6}} =
               Workbench.delete_file(scope, draft.id, file.id, 4)

      assert stored(draft.id) == @skeleton
    end

    test "a rename to the path of another file answers path_taken and keeps lock_version", %{
      scope: scope
    } do
      draft = draft!(scope)
      file = file!(draft, "stations.yaml")

      assert Workbench.rename_file(scope, draft.id, file.id, "pack.yaml", 1) ==
               {:error, :path_taken}

      assert lock_version(draft.id) == 1
      assert stored(draft.id) == @skeleton

      assert Workbench.create_file(scope, draft.id, %{path: "stations.yaml", content: ""}, 1) ==
               {:error, :path_taken}

      assert lock_version(draft.id) == 1
      assert stored(draft.id) == @skeleton

      # A rename to its own path is no conflict.
      assert {:ok, %PackDraft{lock_version: 2}} =
               Workbench.rename_file(scope, draft.id, file.id, "stations.yaml", 1)
    end

    test "a save of pack.yaml updates title and pack_key, and its deletion sets pack_key to nil",
         %{
           scope: scope
         } do
      draft = draft!(scope)
      pack = file!(draft, "pack.yaml")

      changed =
        @skeleton["pack.yaml"]
        |> String.replace("key: new-pack", "key: renamed-pack")
        |> String.replace("title: New pack", "title: Renamed pack")

      assert {:ok, %PackDraft{title: "Renamed pack", pack_key: "renamed-pack", lock_version: 2}} =
               Workbench.update_file(scope, draft.id, pack.id, changed, 1)

      assert %PackDraft{title: "Renamed pack", pack_key: "renamed-pack"} =
               Repo.get!(PackDraft, draft.id)

      # A pack.yaml without a usable title keeps the title; without a usable
      # key the pack key is nil.
      assert {:ok, %PackDraft{title: "Renamed pack", pack_key: nil}} =
               Workbench.update_file(scope, draft.id, pack.id, "schema: 1\ntitle: 7\n", 2)

      assert {:ok, %PackDraft{title: "Renamed pack", pack_key: nil}} =
               Workbench.update_file(scope, draft.id, pack.id, "key: [unclosed\n", 3)

      assert {:ok, %PackDraft{pack_key: "renamed-pack"}} =
               Workbench.update_file(scope, draft.id, pack.id, changed, 4)

      assert {:ok, %PackDraft{title: "Renamed pack", pack_key: nil, lock_version: 6}} =
               Workbench.delete_file(scope, draft.id, pack.id, 5)

      assert %PackDraft{title: "Renamed pack", pack_key: nil} = Repo.get!(PackDraft, draft.id)

      # A new pack.yaml sets them again.
      assert {:ok, %PackDraft{title: "New pack", pack_key: "new-pack"}} =
               Workbench.create_file(
                 scope,
                 draft.id,
                 %{path: "pack.yaml", content: @skeleton["pack.yaml"]},
                 6
               )
    end

    test "a save of another file keeps title and pack_key", %{scope: scope} do
      draft = draft!(scope)
      file = file!(draft, "stations.yaml")

      assert {:ok, %PackDraft{title: "New pack", pack_key: "new-pack"}} =
               Workbench.update_file(scope, draft.id, file.id, "title: Other\nkey: other\n", 1)
    end

    test "a rename of pack.yaml away sets pack_key to nil, and a rename back sets it again", %{
      scope: scope
    } do
      draft = draft!(scope)
      pack = file!(draft, "pack.yaml")

      assert {:ok, %PackDraft{pack_key: nil, title: "New pack", lock_version: 2}} =
               Workbench.rename_file(scope, draft.id, pack.id, "sources.yaml", 1)

      assert %PackDraft{pack_key: nil} = Repo.get!(PackDraft, draft.id)

      assert {:ok, %PackDraft{pack_key: "new-pack", title: "New pack", lock_version: 3}} =
               Workbench.rename_file(scope, draft.id, pack.id, "pack.yaml", 2)

      assert %PackDraft{pack_key: "new-pack"} = Repo.get!(PackDraft, draft.id)
      assert stored(draft.id) == @skeleton
    end
  end

  describe "starting points" do
    test "the skeleton for \"New pack\" holds the six files of step 5 byte for byte", %{
      scope: scope
    } do
      assert {:ok, %PackDraft{} = draft} = Workbench.create_empty(scope, "New pack")

      assert draft.title == "New pack"
      assert draft.pack_key == "new-pack"
      assert draft.lock_version == 1
      assert draft.file_count == 6
      assert stored(draft.id) == @skeleton

      for {path, content} <- @skeleton do
        {:ok, _draft, file} = Workbench.get_file(scope, draft.id, file!(draft, path).id)
        assert file.content == content, "#{path} differs"
      end
    end

    test "a name above 255 code points answers max_length, also with few graphemes", %{
      scope: scope
    } do
      name = "a" <> String.duplicate("\u0301", 255)
      assert String.length(name) == 1

      assert Workbench.create_empty(scope, name) ==
               {:error, {:validation_failed, "name", "max_length"}}

      assert {:ok, _draft} = Workbench.create_empty(scope, String.duplicate("a", 255))
    end

    test "a name of symbols only gives the pack key new-pack", %{scope: scope} do
      assert {:ok, %PackDraft{} = draft} = Workbench.create_empty(scope, "!!! ??? ***")

      assert draft.pack_key == "new-pack"
      assert draft.title == "!!! ??? ***"
      assert stored(draft.id)["pack.yaml"] =~ "\nkey: new-pack\n"
    end

    test "a name gives the slug as pack key and the name as title", %{scope: scope} do
      assert {:ok, %PackDraft{} = draft} = Workbench.create_empty(scope, "Prompting: Basics 2")

      assert draft.pack_key == "prompting-basics-2"
      assert draft.title == "Prompting: Basics 2"
    end

    test "the start from the published demo program holds the files of render_program/1, " <>
           "and its import has the payload of the program",
         %{scope: scope} do
      program = publish_demo!(scope)
      assert {:ok, files} = PackWriter.render_program(program)

      assert {:ok, %PackDraft{} = draft} = Workbench.create_from_program(scope, program.slug)

      # The captions become a text file with the content of the store, the
      # other media files media entries (task 0018, step 16).
      assert stored(draft.id) == Map.new([demo_captions() | files])
      assert draft.file_count == length(files) + 1
      assert media_pairs(draft) == demo_entries()
      assert draft.pack_key == program.slug
      assert draft.title == program.title
      assert Map.has_key?(stored(draft.id), "modules/01-how-language-models-work/module.yaml")

      # The import passes the entries as the media mapping; the captions
      # file is ingested and finds the asset of its delivery digest.
      assets = Repo.aggregate(Asset, :count)

      assert {:ok, %PackImport{status: :validated} = pack_import} =
               Workbench.import_draft(scope, draft.id, draft.lock_version)

      assert pack_import.payload == Payload.build(program)
      assert Repo.get!(PackImport, pack_import.id).payload == Payload.build(program)
      assert Enum.sort(pack_import.media_asset_ids) == Enum.sort(Map.values(demo_media()))
      assert Repo.aggregate(Asset, :count) == assets

      # The draft stays after the import.
      assert {:ok, %PackDraft{lock_version: 1}} = Workbench.get_draft(scope, draft.id)
    end

    test "an unknown slug and an unpublished program answer not_found", %{scope: scope} do
      assert Workbench.create_from_program(scope, "no-such-program") == {:error, :not_found}

      program = publish_demo!(scope)
      Repo.update_all(from(p in Program, where: p.id == ^program.id), set: [status: :draft])
      assert Workbench.create_from_program(scope, program.slug) == {:error, :not_found}

      Repo.update_all(from(p in Program, where: p.id == ^program.id), set: [status: :archived])
      assert Workbench.create_from_program(scope, program.slug) == {:error, :not_found}

      assert Repo.aggregate(PackDraft, :count) == 0
      assert audit_events("pack_draft.created") == []
    end

    test "the start from a validated import holds render/1 of its payload", %{scope: scope} do
      pack_import = import_demo!(scope)

      {:ok, %PackImport{payload: %{} = payload}} = Catalog.get_pack_import(scope, pack_import.id)

      assert {:ok, %PackDraft{} = draft} = Workbench.create_from_import(scope, pack_import.id)

      assert stored(draft.id) == Map.new([demo_captions() | PackWriter.render(payload)])
      assert media_pairs(draft) == demo_entries()
      assert draft.pack_key == pack_import.pack_key
      assert draft.title == payload["title"]
    end

    test "the start from a published import holds render/1 of its payload", %{scope: scope} do
      pack_import = import_demo!(scope)
      {:ok, %PackImport{status: :published}} = Catalog.publish_pack(scope, pack_import)

      assert {:ok, %PackDraft{} = draft} = Workbench.create_from_import(scope, pack_import.id)

      assert stored(draft.id) ==
               Map.new([demo_captions() | PackWriter.render(pack_import.payload)])

      assert media_pairs(draft) == demo_entries()
    end

    test "the start from an import whose captions are not ready answers media_not_ready", %{
      scope: scope
    } do
      captions = queued_asset!(:captions)
      media = Map.put(demo_media(), "media/assistant-demo-en.vtt", captions.id)

      {:ok, %PackImport{status: :validated} = pack_import} =
        Catalog.import_pack(scope, demo_path(), media: media)

      assert Workbench.create_from_import(scope, pack_import.id) ==
               {:error,
                {:media_not_ready,
                 [
                   %{
                     "path" => "media/assistant-demo-en.vtt",
                     "status" => "queued",
                     "failure" => nil
                   }
                 ]}}

      # A failed captions asset carries its failure code, as at the publish.
      fail!(captions, :invalid_captions)

      assert Workbench.create_from_import(scope, pack_import.id) ==
               {:error,
                {:media_not_ready,
                 [
                   %{
                     "path" => "media/assistant-demo-en.vtt",
                     "status" => "failed",
                     "failure" => "invalid_captions"
                   }
                 ]}}

      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "the start from a payload without the key media holds no media entry", %{scope: scope} do
      pack_import = import_demo!(scope)
      payload = Map.delete(pack_import.payload, "media")

      Repo.update_all(from(i in PackImport, where: i.id == ^pack_import.id),
        set: [payload: payload]
      )

      assert {:ok, %PackDraft{} = draft} = Workbench.create_from_import(scope, pack_import.id)
      assert stored(draft.id) == Map.new(PackWriter.render(payload))
      assert draft.media == []
    end

    @tag :tmp_dir
    test "the start from a failed import answers no_payload", %{scope: scope, tmp_dir: tmp_dir} do
      {:ok, %PackImport{status: :failed} = pack_import} =
        Catalog.import_pack(scope, Path.join(tmp_dir, "missing-pack"))

      assert Workbench.create_from_import(scope, pack_import.id) == {:error, :no_payload}
      assert Repo.aggregate(PackDraft, :count) == 0
    end

    test "an unknown import answers not_found", %{scope: scope} do
      assert Workbench.create_from_import(scope, Ecto.UUID.generate()) == {:error, :not_found}
      assert Workbench.create_from_import(scope, "not-a-uuid") == {:error, :not_found}
    end
  end

  describe "download/3" do
    test "the zip lists exactly the paths of the files with their contents", %{scope: scope} do
      draft = draft!(scope)

      {:ok, draft} =
        Workbench.create_file(scope, draft.id, %{path: "glossary.yaml", content: "[]\n"}, 1)

      assert {"new-pack-draft.zip", entries} = download!(scope, draft.id)

      assert Map.new(entries) == stored(draft.id)
      assert length(entries) == 7
      assert Enum.map(entries, &elem(&1, 0)) == Enum.map(draft.files, & &1.path)
    end

    test "a draft whose pack.yaml has no usable key downloads as pack-draft.zip", %{scope: scope} do
      draft = draft!(scope)
      pack = file!(draft, "pack.yaml")

      upper = String.replace(@skeleton["pack.yaml"], "key: new-pack", "key: New-Pack")

      assert {:ok, %PackDraft{pack_key: "New-Pack"}} =
               Workbench.update_file(scope, draft.id, pack.id, upper, 1)

      assert {"pack-draft.zip", _entries} = download!(scope, draft.id)

      long = String.replace(@skeleton["pack.yaml"], "new-pack", String.duplicate("k", 201))

      assert {:ok, %PackDraft{}} = Workbench.update_file(scope, draft.id, pack.id, long, 2)
      assert {"pack-draft.zip", _entries} = download!(scope, draft.id)

      at_bound = String.replace(@skeleton["pack.yaml"], "new-pack", String.duplicate("k", 200))
      assert {:ok, %PackDraft{}} = Workbench.update_file(scope, draft.id, pack.id, at_bound, 3)
      expected = String.duplicate("k", 200) <> "-draft.zip"
      assert {^expected, _entries} = download!(scope, draft.id)

      missing = String.replace(@skeleton["pack.yaml"], "key: new-pack\n", "")

      assert {:ok, %PackDraft{pack_key: nil}} =
               Workbench.update_file(scope, draft.id, pack.id, missing, 4)

      assert {"pack-draft.zip", entries} = download!(scope, draft.id)
      assert Map.new(entries) == stored(draft.id)
    end
  end

  describe "media entries (task 0018, step 16)" do
    test "attach, rename and delete take the lock_version, and the asset stays", %{scope: scope} do
      draft = draft!(scope)
      svg = asset!(:svg)

      assert {:ok, %PackDraft{lock_version: 2} = draft} =
               Workbench.attach_media(
                 scope,
                 draft.id,
                 %{media_asset_id: svg.id, path: "media/diagram.svg"},
                 1
               )

      assert [%PackDraftMedia{path: "media/diagram.svg", media_asset: %Asset{id: id}} = entry] =
               draft.media

      assert id == svg.id
      assert draft.file_count == 6
      assert stored(draft.id) == @skeleton

      assert {:ok, %PackDraft{lock_version: 3} = draft} =
               Workbench.rename_media(scope, draft.id, entry.id, "media/diagrams/checks.svg", 2)

      assert media_pairs(draft) == [{"media/diagrams/checks.svg", svg.id}]

      assert {:ok, %PackDraft{lock_version: 4, media: []}} =
               Workbench.delete_media(scope, draft.id, entry.id, 3)

      assert Repo.get!(Asset, svg.id).status == :ready
      assert Workbench.delete_media(scope, draft.id, entry.id, 4) == {:error, :not_found}
      assert lock_version(draft.id) == 4
    end

    test "an old lock_version answers stale_draft and changes nothing", %{scope: scope} do
      draft = draft!(scope)
      draft = attach!(scope, draft, asset!(:svg), "media/a.svg")
      [entry] = draft.media
      other = asset!(:svg)

      assert Workbench.attach_media(
               scope,
               draft.id,
               %{media_asset_id: other.id, path: "media/b.svg"},
               1
             ) == {:error, {:stale_draft, 2}}

      assert Workbench.rename_media(scope, draft.id, entry.id, "media/c.svg", 1) ==
               {:error, {:stale_draft, 2}}

      assert Workbench.delete_media(scope, draft.id, entry.id, 1) == {:error, {:stale_draft, 2}}

      assert {:ok, draft} = Workbench.get_draft(scope, draft.id)
      assert {draft.lock_version, Enum.map(draft.media, & &1.path)} == {2, ["media/a.svg"]}
    end

    test "a path outside media/ or without the delivery extension of the asset answers invalid_path",
         %{scope: scope} do
      draft = draft!(scope)

      for {kind, path} <- [
            {:svg, "media/diagram.webp"},
            {:svg, "diagram.svg"},
            {:image, "media/photo.png"},
            {:image, "media/Photo.webp"},
            {:image, "media/a/b/c/d/photo.webp"},
            {:video, "media/clip.mp4"},
            {:video, "modules/01-first-module/clip.webm"}
          ] do
        assert Workbench.attach_media(
                 scope,
                 draft.id,
                 %{media_asset_id: asset!(kind).id, path: path},
                 1
               ) == {:error, :invalid_path},
               "#{kind} #{path}"
      end

      draft = attach!(scope, draft, asset!(:video), "media/clip.webm")
      [entry] = draft.media

      assert Workbench.rename_media(scope, draft.id, entry.id, "media/clip.webp", 2) ==
               {:error, :invalid_path}

      assert lock_version(draft.id) == 2
    end

    test "a path that a file or another entry holds answers path_taken", %{scope: scope} do
      draft = draft!(scope)
      draft = attach!(scope, draft, asset!(:image), "media/photo.webp")
      draft = attach!(scope, draft, asset!(:image), "media/other.webp")
      [other, photo] = draft.media

      assert Workbench.attach_media(
               scope,
               draft.id,
               %{media_asset_id: asset!(:image).id, path: "media/photo.webp"},
               3
             ) == {:error, :path_taken}

      assert Workbench.rename_media(scope, draft.id, other.id, photo.path, 3) ==
               {:error, :path_taken}

      # A rename to its own path changes nothing but the version.
      assert {:ok, %PackDraft{lock_version: 4}} =
               Workbench.rename_media(scope, draft.id, photo.id, photo.path, 3)

      # A captions file holds its path against a captions asset, and an
      # entry holds its path against a file.
      {:ok, draft} =
        Workbench.create_file(scope, draft.id, %{path: "media/en.vtt", content: "WEBVTT\n"}, 4)

      captions = asset!(:captions, "WEBVTT\n\n00:00.000 --> 00:01.000\nA tone.\n")

      assert Workbench.attach_media(
               scope,
               draft.id,
               %{media_asset_id: captions.id, path: "media/en.vtt"},
               5
             ) == {:error, :path_taken}

      assert Workbench.create_file(
               scope,
               draft.id,
               %{path: "media/photo.webp", content: "x"},
               5
             ) == {:error, :invalid_path}

      assert {draft.lock_version, lock_version(draft.id)} == {5, 5}
    end

    test "the entry beyond max_draft_media answers media_limit", %{scope: scope} do
      put_setting(
        :media,
        Keyword.put(Application.fetch_env!(:espalier, :media), :max_draft_media, 2)
      )

      assert Media.max_draft_media() == 2

      draft = draft!(scope)
      draft = attach!(scope, draft, asset!(:svg), "media/a.svg")
      draft = attach!(scope, draft, asset!(:svg), "media/b.svg")

      assert Workbench.attach_media(
               scope,
               draft.id,
               %{media_asset_id: asset!(:svg).id, path: "media/c.svg"},
               3
             ) == {:error, :media_limit}

      # A captions asset becomes a file and counts no entry.
      captions = asset!(:captions, "WEBVTT\n")
      assert %PackDraft{lock_version: 4} = attach!(scope, draft, captions, "media/en.vtt")

      # A rename adds no entry and passes at the limit.
      [entry | _rest] = draft.media

      assert {:ok, %PackDraft{}} =
               Workbench.rename_media(scope, draft.id, entry.id, "media/z.svg", 4)
    end

    test "max_files counts the files and the entries together", %{scope: scope} do
      draft = draft!(scope)
      now = DateTime.utc_now(:second)

      # The skeleton holds six files; 1,992 more and one entry give 1,999.
      rows =
        for n <- 1..1_992 do
          %{
            id: Ecto.UUID.generate(),
            pack_draft_id: draft.id,
            path: lesson("filler-#{n}"),
            content: "",
            inserted_at: now,
            updated_at: now
          }
        end

      {1_992, nil} = Repo.insert_all(PackDraftFile, rows)
      draft = attach!(scope, draft, asset!(:image), "media/first.webp")
      draft = attach!(scope, draft, asset!(:image), "media/second.webp")
      assert {draft.file_count, length(draft.media)} == {1_998, 2}

      assert Workbench.attach_media(
               scope,
               draft.id,
               %{media_asset_id: asset!(:image).id, path: "media/third.webp"},
               3
             ) == {:error, :too_many_files}

      assert Workbench.create_file(scope, draft.id, %{path: lesson("last"), content: ""}, 3) ==
               {:error, :too_many_files}

      captions = asset!(:captions, "WEBVTT\n")

      assert Workbench.attach_media(
               scope,
               draft.id,
               %{media_asset_id: captions.id, path: "media/en.vtt"},
               3
             ) == {:error, :too_many_files}

      assert lock_version(draft.id) == 3
    end

    test "an unknown asset and an unknown entry answer not_found", %{scope: scope} do
      draft = draft!(scope)

      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        assert Workbench.attach_media(
                 scope,
                 draft.id,
                 %{media_asset_id: id, path: "media/a.svg"},
                 1
               ) ==
                 {:error, :not_found}

        assert Workbench.rename_media(scope, draft.id, id, "media/a.svg", 1) ==
                 {:error, :not_found}

        assert Workbench.delete_media(scope, draft.id, id, 1) == {:error, :not_found}
      end

      assert lock_version(draft.id) == 1
    end

    test "a ready captions asset becomes a text file with the content of the store", %{
      scope: scope
    } do
      draft = draft!(scope)
      {path, content} = demo_captions()
      captions = Repo.get!(Asset, demo_media()[path])
      assert captions.status == :ready

      assert {:ok, %PackDraft{lock_version: 2, media: []} = draft} =
               Workbench.attach_media(
                 scope,
                 draft.id,
                 %{media_asset_id: captions.id, path: "media/captions/demo-en.vtt"},
                 1
               )

      assert stored(draft.id)["media/captions/demo-en.vtt"] == content
      assert draft.file_count == 7

      # Only a .vtt path below media/ takes captions.
      for path <- ["media/captions/demo-en.webm", "captions.vtt", "media/Demo.vtt"] do
        assert Workbench.attach_media(
                 scope,
                 draft.id,
                 %{media_asset_id: captions.id, path: path},
                 2
               ) == {:error, :invalid_path},
               path
      end
    end

    test "a captions asset that is not ready answers not_ready", %{scope: scope} do
      draft = draft!(scope)
      queued = queued_asset!(:captions)

      assert Workbench.attach_media(
               scope,
               draft.id,
               %{media_asset_id: queued.id, path: "media/en.vtt"},
               1
             ) == {:error, {:validation_failed, "media_asset_id", "not_ready"}}

      # An image, SVG or video asset may still be converting.
      assert %PackDraft{lock_version: 2} =
               attach!(scope, draft, queued_asset!(:image), "media/later.webp")
    end

    test "a captions file stays within the bytes of a draft", %{scope: scope} do
      put_setting(:pack_upload_max_mb, 1)
      max = Workbench.max_draft_bytes()
      draft = draft!(scope)
      captions = asset!(:captions, "WEBVTT\n\n00:00.000 --> 00:01.000\nA tone.\n")
      now = DateTime.utc_now(:second)
      used = stored(draft.id) |> Map.values() |> Enum.map(&byte_size/1) |> Enum.sum()

      Repo.insert_all(PackDraftFile, [
        %{
          id: Ecto.UUID.generate(),
          pack_draft_id: draft.id,
          path: lesson("filler"),
          content: String.duplicate("a", max - used - 10),
          inserted_at: now,
          updated_at: now
        }
      ])

      assert Workbench.attach_media(
               scope,
               draft.id,
               %{media_asset_id: captions.id, path: "media/en.vtt"},
               1
             ) == {:error, :draft_too_large}

      assert lock_version(draft.id) == 1
    end

    test "a draft with an entry checks and imports with the mapping of its entries", %{
      scope: scope
    } do
      draft = draft!(scope)
      svg = asset!(:svg)
      draft = attach!(scope, draft, svg, "media/diagram.svg")
      file = file!(draft, lesson("01-first-lesson"))

      content =
        @skeleton[lesson("01-first-lesson")] <>
          """

          :::figure{src=media/diagram.svg alt="A diagram." provenance=invented}
          :::
          """

      {:ok, draft} = Workbench.update_file(scope, draft.id, file.id, content, 2)

      assert {:ok, %{report: %{"errors" => [], "warnings" => []}}} =
               Workbench.check_draft(scope, draft.id, nil)

      assets = Repo.aggregate(Asset, :count)

      assert {:ok, %PackImport{status: :validated} = pack_import} =
               Workbench.import_draft(scope, draft.id, 3)

      assert pack_import.payload["media"] == [
               %{"path" => "media/diagram.svg", "asset_id" => svg.id, "kind" => "svg"}
             ]

      assert pack_import.media_asset_ids == [svg.id]
      assert Repo.aggregate(Asset, :count) == assets
    end
  end

  describe "download/3 with media (task 0018, step 16)" do
    test "stages the text files and hard links of the media files, WebP and WebM uncompressed",
         %{scope: scope} do
      draft = draft!(scope)
      image = asset!(:image, "RIFF a stand-in of a WebP image #{random()}")
      video = asset!(:video, "a stand-in of a WebM video #{random()}")
      svg = asset!(:svg)
      draft = attach!(scope, draft, image, "media/photo.webp")
      draft = attach!(scope, draft, video, "media/clips/clip.webm")
      draft = attach!(scope, draft, svg, "media/diagram.svg")

      assert {:ok, {zip_listing, entries, dir}} =
               Workbench.download(scope, draft.id, fn %{name: name, path: zip, dir: dir} ->
                 assert name == "new-pack-draft.zip"
                 assert Path.dirname(dir) == Store.work_root()

                 # Each media file of the staging directory is a hard link to
                 # its store file, which keeps the bytes when the store file is
                 # removed meanwhile.
                 for {path, asset} <- [
                       {"media/photo.webp", image},
                       {"media/clips/clip.webm", video},
                       {"media/diagram.svg", svg}
                     ] do
                   staged = File.stat!(Path.join([dir, "pack", path]))
                   stored = File.stat!(Store.path(asset.sha256, asset.ext))

                   assert {staged.inode, staged.major_device} ==
                            {stored.inode, stored.major_device},
                          path
                 end

                 {:ok, listing} = :zip.list_dir(String.to_charlist(zip))
                 {:ok, {listing, unzip!(zip), dir}}
               end)

      refute File.exists?(dir)

      media =
        for {path, asset} <- [
              {"media/clips/clip.webm", video},
              {"media/diagram.svg", svg},
              {"media/photo.webp", image}
            ],
            do: {path, File.read!(Store.path(asset.sha256, asset.ext))}

      assert entries == Enum.sort(Map.to_list(stored(draft.id)) ++ media)

      sizes =
        for {:zip_file, name, info, _comment, _offset, compressed} <- zip_listing,
            into: %{},
            do: {List.to_string(name), {compressed, elem(info, 1)}}

      for path <- ["media/photo.webp", "media/clips/clip.webm"] do
        assert {size, size} = sizes[path], path
      end
    end

    test "an asset deleted during the download keeps its bytes in the staging directory and the zip",
         %{scope: scope} do
      content = "a stand-in of a WebM video #{random()}"
      video = asset!(:video, content)
      draft = attach!(scope, draft!(scope), video, "media/clip.webm")
      [entry] = draft.media
      store = Store.path(video.sha256, "webm")

      assert {:ok, entries} =
               Workbench.download(scope, draft.id, fn %{path: zip, dir: dir} ->
                 # The staging is done and the zip not yet sent: the entry
                 # leaves the draft, and the asset goes with its store file.
                 assert {:ok, _draft} =
                          Workbench.delete_media(scope, draft.id, entry.id, draft.lock_version)

                 assert Media.delete_asset(scope, video.id) == :ok
                 refute File.exists?(store)

                 assert File.read!(Path.join([dir, "pack", "media/clip.webm"])) == content
                 {:ok, unzip!(zip)}
               end)

      assert {"media/clip.webm", content} in entries
      assert Repo.get(Asset, video.id) == nil
    end

    test "the zip of a draft from the demo program unzips to a pack that the validator accepts",
         %{scope: scope} do
      tmp_dir = Path.join(System.tmp_dir!(), "espalier-unzip-#{random()}")
      File.mkdir_p!(tmp_dir)
      on_exit(fn -> File.rm_rf!(tmp_dir) end)
      program = publish_demo!(scope)
      {:ok, draft} = Workbench.create_from_program(scope, program.slug)

      assert {:ok, _files} =
               Workbench.download(scope, draft.id, fn %{path: zip} ->
                 :zip.unzip(String.to_charlist(zip), cwd: String.to_charlist(tmp_dir))
               end)

      for path <- MediaFixtures.demo_media_paths() do
        assert File.read!(Path.join(tmp_dir, path)) == File.read!(Path.join(demo_path(), path))
      end

      assert {:ok, loaded} = Loader.load(tmp_dir)

      assert %{errors: [], warnings: [], payload: payload} =
               Validator.run(loaded)

      assert payload == Map.delete(Payload.build(program), "media")
    end

    test "media above export_max_mb answer download_too_large and stage nothing", %{scope: scope} do
      put_setting(
        :media,
        Keyword.put(Application.fetch_env!(:espalier, :media), :export_max_mb, 1)
      )

      draft = draft!(scope)
      draft = attach!(scope, draft, asset!(:video, :binary.copy("v", 600_000)), "media/a.webm")
      draft = attach!(scope, draft, asset!(:video, :binary.copy("w", 600_000)), "media/b.webm")
      staged = work_dirs()

      assert Workbench.download(scope, draft.id, &no_zip/1) == {:error, :download_too_large}
      assert work_dirs() == staged

      # Within the limit, the download passes.
      [first, _second] = draft.media
      {:ok, _draft} = Workbench.delete_media(scope, draft.id, first.id, 3)
      assert {"new-pack-draft.zip", [_ | _]} = download!(scope, draft.id)
    end

    test "an entry whose asset is not ready or whose file is missing answers media_not_ready",
         %{scope: scope} do
      draft = draft!(scope)
      draft = attach!(scope, draft, queued_asset!(:image), "media/later.webp")
      gone = asset!(:svg)
      draft = attach!(scope, draft, gone, "media/gone.svg")
      File.rm!(Store.path(gone.sha256, "svg"))
      broken = queued_asset!(:video)
      draft = attach!(scope, draft, broken, "media/broken.webm")
      fail!(broken, :conversion_failed)
      staged = work_dirs()

      # A failed asset carries its failure code, as at the publish.
      assert Workbench.download(scope, draft.id, &no_zip/1) ==
               {:error,
                {:media_not_ready,
                 [
                   %{
                     "path" => "media/broken.webm",
                     "status" => "failed",
                     "failure" => "conversion_failed"
                   },
                   %{"path" => "media/gone.svg", "status" => "missing", "failure" => nil},
                   %{"path" => "media/later.webp", "status" => "queued", "failure" => nil}
                 ]}}

      assert work_dirs() == staged
      assert draft.lock_version == 4
    end
  end

  describe "audit events" do
    test "pack_draft.created names actor, subject, source, pack key and file count", %{
      author: author,
      scope: scope
    } do
      draft = draft!(scope)

      assert [event] = audit_events("pack_draft.created")
      assert event.actor_id == author.id
      assert event.subject_type == "PackDraft"
      assert event.subject_id == draft.id

      assert event.details == %{"source" => "empty", "pack_key" => "new-pack", "file_count" => 6}
    end

    test "pack_draft.created names the program slug of a draft from a program", %{
      author: author,
      scope: scope
    } do
      program = publish_demo!(scope)
      {:ok, files} = PackWriter.render_program(program)
      {:ok, draft} = Workbench.create_from_program(scope, program.slug)

      assert [event] = audit_events("pack_draft.created")
      assert event.actor_id == author.id
      assert event.subject_id == draft.id

      assert event.details == %{
               "source" => "program",
               "program_slug" => program.slug,
               "pack_key" => program.slug,
               "file_count" => length(files) + 1
             }
    end

    test "pack_draft.created names the import of a draft from an import", %{
      author: author,
      scope: scope
    } do
      pack_import = import_demo!(scope)
      {:ok, draft} = Workbench.create_from_import(scope, pack_import.id)

      assert [event] = audit_events("pack_draft.created")
      assert event.actor_id == author.id
      assert event.subject_id == draft.id

      assert event.details == %{
               "source" => "import",
               "pack_import_id" => pack_import.id,
               "pack_key" => pack_import.pack_key,
               "file_count" => draft.file_count
             }
    end

    test "pack_draft.deleted names actor, subject, pack key and file count", %{
      author: author,
      scope: scope
    } do
      draft = draft!(scope)
      {:ok, _draft} = Workbench.delete_draft(scope, draft.id)

      assert [event] = audit_events("pack_draft.deleted")
      assert event.actor_id == author.id
      assert event.subject_type == "PackDraft"
      assert event.subject_id == draft.id
      assert event.details == %{"pack_key" => "new-pack", "file_count" => 6}
    end

    test "a file save, create, rename and delete write no audit event", %{scope: scope} do
      draft = draft!(scope)
      before = Repo.aggregate(AuditEvent, :count)

      {:ok, draft} =
        Workbench.create_file(scope, draft.id, %{path: "sources.yaml", content: ""}, 1)

      file = file!(draft, "sources.yaml")
      {:ok, _draft} = Workbench.update_file(scope, draft.id, file.id, "[]\n", 2)
      {:ok, _draft} = Workbench.rename_file(scope, draft.id, file.id, "glossary.yaml", 3)
      {:ok, _draft} = Workbench.delete_file(scope, draft.id, file.id, 4)
      {_name, _entries} = download!(scope, draft.id)
      {:ok, _drafts} = Workbench.list_drafts(scope)

      assert lock_version(draft.id) == 5
      assert Repo.aggregate(AuditEvent, :count) == before
    end
  end
end
