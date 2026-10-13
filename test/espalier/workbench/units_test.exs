defmodule Espalier.Workbench.UnitsTest do
  @moduledoc """
  Task 0016a, steps 5 and 7: the functions that the task adds outside the
  Workbench context. `Espalier.Catalog.Pack.Loader.pack_meta_text/1` reads
  `key`, `version` and `title` of the text of a `pack.yaml` with the checks
  of the loader, and `Loader.pack_meta/1` also returns `title`;
  `Espalier.Catalog.Pack.Archive.pack_root/1` finds the pack at the root of
  an extracted archive or in its one top-level directory;
  `Espalier.Interop.PackWriter.slug/1`, `render/1` and `render_program/1`
  give the files of a draft; and `Espalier.Catalog.import_pack/3` merges its
  option `audit:` into the details of `pack.imported`.
  """
  use Espalier.DataCase, async: true

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]
  import Espalier.PackFixtures, only: [copy_pack!: 1, demo_path: 0, replace!: 4]

  alias Espalier.Accounts.Scope
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog
  alias Espalier.Catalog.Pack.{Archive, Loader, Validator}
  alias Espalier.Catalog.Program
  alias Espalier.Interop.PackWriter

  @demo_key "ai-assistant-basics-demo"
  @nil_meta %{key: nil, version: nil, title: nil}

  describe "Loader.pack_meta_text/1" do
    test "returns key, version and title as strings" do
      text = """
      schema: 1
      key: my-pack
      title: My pack
      locale: en
      version: "1.2.0"
      """

      assert Loader.pack_meta_text(text) == %{key: "my-pack", version: "1.2.0", title: "My pack"}
    end

    test "returns nil for a member that is no string or is missing" do
      assert Loader.pack_meta_text("key: 42\nversion: 1.5\ntitle: [a, b]\n") == @nil_meta

      assert Loader.pack_meta_text("key: my-pack\ntitle:\n  en: My pack\nversion: null\n") ==
               %{key: "my-pack", version: nil, title: nil}

      assert Loader.pack_meta_text("title: Only a title\n") ==
               %{key: nil, version: nil, title: "Only a title"}
    end

    test "returns nil for all three members of a text that does not parse to a map" do
      for text <- [
            "key: [unclosed\n",
            "title: Minimal\n  extra: value\n",
            "- key: my-pack\n",
            "just a line of text\n",
            "",
            "# a comment only\n"
          ] do
        assert Loader.pack_meta_text(text) == @nil_meta, "#{inspect(text)} gave a member"
      end
    end

    test "returns nil for all three members of a text above 1 MiB" do
      text = "key: big\ntitle: Big\n# " <> String.duplicate("x", Loader.max_file_bytes())
      assert byte_size(text) > Loader.max_file_bytes()
      assert Loader.pack_meta_text(text) == @nil_meta
    end

    test "returns nil for all three members of a text with a control character or no UTF-8" do
      for text <- [
            "key: my\x01pack\ntitle: My pack\n",
            "# \x07\nkey: my-pack\ntitle: My pack\n",
            "key: my-pack\ntitle: My pack\x7F\n",
            <<"key: my-pack\ntitle: My pack ", 0xFF, "\n">>
          ] do
        assert Loader.pack_meta_text(text) == @nil_meta, "#{inspect(text)} gave a member"
      end

      # Tab, line feed and carriage return pass, as in the loader.
      assert Loader.pack_meta_text("key: my-pack\r\ntitle: My pack\t\r\n") ==
               %{key: "my-pack", version: nil, title: "My pack"}
    end
  end

  describe "Loader.pack_meta/1" do
    test "returns the title besides key and version" do
      assert Loader.pack_meta(copy_pack!("minimal")) == %{
               key: "minimal-pack",
               version: "0.1.0",
               title: "Minimal pack (test fixture)"
             }

      assert %{key: @demo_key, title: "AI assistant basics (demo)"} =
               Loader.pack_meta(demo_path())
    end

    test "returns nil for a title that is no string" do
      pack = copy_pack!("minimal")
      replace!(pack, "pack.yaml", "title: Minimal pack (test fixture)", "title: [a, b]")

      assert Loader.pack_meta(pack) == %{key: "minimal-pack", version: "0.1.0", title: nil}
    end

    @tag :tmp_dir
    test "returns nil for all three members without a pack.yaml", %{tmp_dir: tmp_dir} do
      assert Loader.pack_meta(tmp_dir) == @nil_meta
    end
  end

  describe "Archive.pack_root/1" do
    @describetag :tmp_dir

    test "is the directory itself when it holds pack.yaml", %{tmp_dir: tmp_dir} do
      File.write!(Path.join(tmp_dir, "pack.yaml"), "schema: 1\n")
      File.mkdir_p!(Path.join(tmp_dir, "modules/01-a"))

      assert Archive.pack_root(tmp_dir) == tmp_dir
    end

    test "is the one top-level directory when that holds pack.yaml", %{tmp_dir: tmp_dir} do
      nested = Path.join(tmp_dir, "my-pack")
      File.mkdir_p!(Path.join(nested, "modules"))
      File.write!(Path.join(nested, "pack.yaml"), "schema: 1\n")

      assert Archive.pack_root(tmp_dir) == nested
    end

    test "is the directory itself with two entries at the root", %{tmp_dir: tmp_dir} do
      nested = Path.join(tmp_dir, "my-pack")
      File.mkdir_p!(nested)
      File.write!(Path.join(nested, "pack.yaml"), "schema: 1\n")
      File.write!(Path.join(tmp_dir, "README.md"), "# Notes\n")

      assert Archive.pack_root(tmp_dir) == tmp_dir
    end

    test "is the directory itself when the one top-level entry holds no pack.yaml", %{
      tmp_dir: tmp_dir
    } do
      File.mkdir_p!(Path.join(tmp_dir, "my-pack/modules"))
      assert Archive.pack_root(tmp_dir) == tmp_dir

      File.rm_rf!(Path.join(tmp_dir, "my-pack"))
      File.write!(Path.join(tmp_dir, "pack.zip"), "")
      assert Archive.pack_root(tmp_dir) == tmp_dir
    end
  end

  describe "PackWriter.slug/1" do
    test "drops accents and joins every other run of characters into one hyphen" do
      assert PackWriter.slug("Crème brûlée") == "creme-brulee"
      assert PackWriter.slug("Ärger über Öl") == "arger-uber-ol"
      assert PackWriter.slug("How  language models -- work?") == "how-language-models-work"
      assert PackWriter.slug("Module 2: Checking_the output") == "module-2-checking-the-output"
    end

    test "keeps at most 40 characters and no leading or trailing hyphen" do
      slug = PackWriter.slug(String.duplicate("abcde ", 10))
      assert slug == "abcde-abcde-abcde-abcde-abcde-abcde-abcd"
      assert String.length(slug) == 40

      assert PackWriter.slug("  -- Hello, world! --  ") == "hello-world"

      # The cut after 40 characters ends in a hyphen, which goes as well.
      assert PackWriter.slug(String.duplicate("a", 39) <> " b") == String.duplicate("a", 39)
    end

    test "is empty when no letter or digit remains" do
      for title <- ["", "!?* – …", "---", "日本語"] do
        assert PackWriter.slug(title) == "", "#{inspect(title)} gave a slug"
      end
    end
  end

  describe "PackWriter.render/1" do
    @tag :tmp_dir
    test "returns the files that write_payload/2 writes", %{tmp_dir: tmp_dir} do
      {:ok, loaded} = Loader.load(demo_path())
      %{payload: payload} = Validator.run(loaded)

      files = PackWriter.render(payload)
      paths = Enum.map(files, &elem(&1, 0))
      assert paths == Enum.uniq(paths)
      assert "pack.yaml" in paths

      assert :ok = PackWriter.write_payload(payload, tmp_dir)

      written =
        for path <- Path.wildcard(Path.join(tmp_dir, "**"), match_dot: true),
            File.regular?(path),
            into: %{},
            do: {Path.relative_to(path, tmp_dir), File.read!(path)}

      assert Map.new(files) == written
    end
  end

  describe "PackWriter.render_program/1" do
    test "answers not_published for a program that is not published" do
      for status <- [:draft, :archived] do
        program = %Program{id: Ecto.UUID.generate(), slug: @demo_key, status: status}
        assert PackWriter.render_program(program) == {:error, :not_published}
      end
    end
  end

  describe "Catalog.import_pack/3" do
    setup do
      user = user_with_role_fixture(:author)
      %{scope: %{Scope.for_user(user) | roles: [:learner, :author]}, user: user}
    end

    test "merges the audit map into the details of pack.imported", %{scope: scope, user: user} do
      draft_id = Ecto.UUID.generate()

      assert {:ok, pack_import} =
               Catalog.import_pack(scope, demo_path(), audit: %{pack_draft_id: draft_id})

      event = imported_event!(pack_import.id)
      assert event.actor_id == user.id

      assert event.details == %{
               "pack_key" => @demo_key,
               "status" => "validated",
               "pack_draft_id" => draft_id
             }
    end

    test "writes pack_key and status only without the option", %{scope: scope} do
      assert {:ok, two} = Catalog.import_pack(scope, demo_path())
      assert {:ok, three} = Catalog.import_pack(scope, demo_path(), [])

      for pack_import <- [two, three] do
        assert imported_event!(pack_import.id).details == %{
                 "pack_key" => @demo_key,
                 "status" => "validated"
               }
      end
    end

    test "keeps pack_key and status of the import over members of the audit map", %{
      scope: scope
    } do
      audit = %{pack_key: "forged", status: "published", note: "kept"}
      assert {:ok, pack_import} = Catalog.import_pack(scope, demo_path(), audit: audit)

      assert imported_event!(pack_import.id).details == %{
               "pack_key" => @demo_key,
               "status" => "validated",
               "note" => "kept"
             }
    end
  end

  defp imported_event!(import_id) do
    Repo.one!(
      from e in AuditEvent, where: e.action == "pack.imported" and e.subject_id == ^import_id
    )
  end
end
