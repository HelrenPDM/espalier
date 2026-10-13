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
      a file change.
  """
  # The tests change application settings, which every process reads.
  use Espalier.DataCase, async: false

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import Espalier.PackFixtures, only: [demo_path: 0]

  alias Espalier.Accounts.Scope
  alias Espalier.{AccountsFixtures, Catalog, Workbench}
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.{PackImport, Program}
  alias Espalier.Interop.{PackWriter, Payload}
  alias Espalier.Workbench.{PackDraft, PackDraftFile}
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

  defp publish_demo!(scope) do
    {:ok, %PackImport{status: :validated} = pack_import} = Catalog.import_pack(scope, demo_path())
    {:ok, %PackImport{status: :published}} = Catalog.publish_pack(scope, pack_import)
    %Program{status: :published} = Catalog.get_program_by_slug(pack_import.pack_key)
  end

  defp unzip!(zip) do
    {:ok, entries} = :zip.unzip(zip, [:memory])
    Enum.map(entries, fn {name, content} -> {List.to_string(name), content} end)
  end

  describe "limits" do
    test "the limit functions carry the values of step 3" do
      assert Workbench.max_files() == 2_000
      assert Workbench.max_file_bytes() == 1_048_576
      assert Workbench.max_drafts() == 50
      assert Workbench.max_parallel_checks() == 2
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

    test "max_drafts/0 and max_parallel_checks/0 raise for a value that is no positive integer" do
      for value <- [0, -1, "50", nil, 1.5] do
        put_setting(:pack_drafts, max_drafts: value, max_parallel_checks: value)

        assert_raise ArgumentError, ~r/max_drafts must be a positive integer/, fn ->
          Workbench.max_drafts()
        end

        assert_raise ArgumentError, ~r/max_parallel_checks must be a positive integer/, fn ->
          Workbench.max_parallel_checks()
        end
      end
    end

    test "a missing member of the setting takes its default" do
      put_setting(:pack_drafts, [])

      assert Workbench.max_drafts() == 50
      assert Workbench.max_parallel_checks() == 2
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
        assert Workbench.download(denied, draft.id) == {:error, :forbidden}
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
        assert Workbench.download(scope, bad) == {:error, :not_found}
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
      assert Workbench.download(scope, unknown) == {:error, :not_found}
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

      assert stored(draft.id) == Map.new(files)
      assert draft.file_count == length(files)
      assert draft.pack_key == program.slug
      assert draft.title == program.title
      assert Map.has_key?(stored(draft.id), "modules/01-how-language-models-work/module.yaml")

      assert {:ok, %PackImport{status: :validated} = pack_import} =
               Workbench.import_draft(scope, draft.id, draft.lock_version)

      assert pack_import.payload == Payload.build(program)
      assert Repo.get!(PackImport, pack_import.id).payload == Payload.build(program)

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
      {:ok, %PackImport{status: :validated} = pack_import} =
        Catalog.import_pack(scope, demo_path())

      {:ok, %PackImport{payload: %{} = payload}} = Catalog.get_pack_import(scope, pack_import.id)

      assert {:ok, %PackDraft{} = draft} = Workbench.create_from_import(scope, pack_import.id)

      assert stored(draft.id) == Map.new(PackWriter.render(payload))
      assert draft.pack_key == pack_import.pack_key
      assert draft.title == payload["title"]
    end

    test "the start from a published import holds render/1 of its payload", %{scope: scope} do
      {:ok, pack_import} = Catalog.import_pack(scope, demo_path())
      {:ok, %PackImport{status: :published}} = Catalog.publish_pack(scope, pack_import)

      assert {:ok, %PackDraft{} = draft} = Workbench.create_from_import(scope, pack_import.id)
      assert stored(draft.id) == Map.new(PackWriter.render(pack_import.payload))
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

  describe "download/2" do
    test "the zip lists exactly the paths of the files with their contents", %{scope: scope} do
      draft = draft!(scope)

      {:ok, draft} =
        Workbench.create_file(scope, draft.id, %{path: "glossary.yaml", content: "[]\n"}, 1)

      assert {:ok, %{name: "new-pack-draft.zip", zip: zip}} = Workbench.download(scope, draft.id)

      entries = unzip!(zip)
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

      assert {:ok, %{name: "pack-draft.zip"}} = Workbench.download(scope, draft.id)

      long = String.replace(@skeleton["pack.yaml"], "new-pack", String.duplicate("k", 201))

      assert {:ok, %PackDraft{}} = Workbench.update_file(scope, draft.id, pack.id, long, 2)
      assert {:ok, %{name: "pack-draft.zip"}} = Workbench.download(scope, draft.id)

      at_bound = String.replace(@skeleton["pack.yaml"], "new-pack", String.duplicate("k", 200))
      assert {:ok, %PackDraft{}} = Workbench.update_file(scope, draft.id, pack.id, at_bound, 3)
      expected = String.duplicate("k", 200) <> "-draft.zip"
      assert {:ok, %{name: ^expected}} = Workbench.download(scope, draft.id)

      missing = String.replace(@skeleton["pack.yaml"], "key: new-pack\n", "")

      assert {:ok, %PackDraft{pack_key: nil}} =
               Workbench.update_file(scope, draft.id, pack.id, missing, 4)

      assert {:ok, %{name: "pack-draft.zip", zip: zip}} = Workbench.download(scope, draft.id)
      assert Map.new(unzip!(zip)) == stored(draft.id)
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
               "file_count" => length(files)
             }
    end

    test "pack_draft.created names the import of a draft from an import", %{
      author: author,
      scope: scope
    } do
      {:ok, pack_import} = Catalog.import_pack(scope, demo_path())
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
      {:ok, _zip} = Workbench.download(scope, draft.id)
      {:ok, _drafts} = Workbench.list_drafts(scope)

      assert lock_version(draft.id) == 5
      assert Repo.aggregate(AuditEvent, :count) == before
    end
  end
end
