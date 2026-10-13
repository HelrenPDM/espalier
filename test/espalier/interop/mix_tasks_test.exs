defmodule Espalier.Interop.MixTasksTest do
  # The tests replace the Mix shell, which the whole node shares, so the
  # module runs after the asynchronous tests.
  use Espalier.DataCase, async: false

  import Espalier.PackFixtures, only: [demo_path: 0]

  alias Espalier.Catalog.Pack.{Importer, Loader, Validator}
  alias Espalier.Catalog.{PackImport, Program}
  alias Espalier.LearningFixtures
  alias Mix.Tasks.Espalier.Export

  setup do
    previous = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(previous) end)
  end

  describe "mix espalier.export" do
    @tag :tmp_dir
    test "writes a published program into a missing directory and into an empty one", %{
      tmp_dir: tmp_dir
    } do
      program = LearningFixtures.publish_demo!()
      out = Path.join(tmp_dir, "new/pack")

      assert :ok = Export.run([program.slug, out])
      assert_received {:mix_shell, :info, [message]}
      assert message == "Wrote ai-assistant-basics-demo 1.0.0 to #{out}"

      assert {:ok, loaded} = Loader.load(out)
      assert %{errors: [], warnings: []} = Validator.run(loaded)

      empty = Path.join(tmp_dir, "empty")
      File.mkdir!(empty)
      assert :ok = Export.run([program.slug, empty])
      assert File.exists?(Path.join(empty, "pack.yaml"))
    end

    @tag :tmp_dir
    test "exits with status 1 for a directory that is not empty", %{tmp_dir: tmp_dir} do
      program = LearningFixtures.publish_demo!()
      File.write!(Path.join(tmp_dir, "notes.txt"), "kept")

      assert catch_exit(Export.run([program.slug, tmp_dir])) == {:shutdown, 1}
      assert_received {:mix_shell, :error, [message]}
      assert message == "The directory #{tmp_dir} is not empty"
      assert File.ls!(tmp_dir) == ["notes.txt"]

      file = Path.join(tmp_dir, "notes.txt")
      assert catch_exit(Export.run([program.slug, file])) == {:shutdown, 1}
      assert_received {:mix_shell, :error, [message]}
      assert message == "#{file} is not a directory"
    end

    @tag :tmp_dir
    test "exits with status 1 for an unknown slug and creates no directory", %{
      tmp_dir: tmp_dir
    } do
      out = Path.join(tmp_dir, "pack")

      assert catch_exit(Export.run(["no-such-program", out])) == {:shutdown, 1}
      assert_received {:mix_shell, :error, [message]}
      assert message == ~s(Unknown program "no-such-program")
      refute File.exists?(out)
    end

    @tag :tmp_dir
    test "exits with status 1 for a slug with a draft import only and for a draft program", %{
      tmp_dir: tmp_dir
    } do
      out = Path.join(tmp_dir, "pack")

      # A draft import creates no program; the publisher does.
      assert {:ok, %PackImport{status: :validated}} = Importer.import(demo_path(), nil)
      assert catch_exit(Export.run([LearningFixtures.demo_slug(), out])) == {:shutdown, 1}
      assert_received {:mix_shell, :error, [message]}
      assert message == ~s(Unknown program "ai-assistant-basics-demo")

      Repo.insert!(%Program{slug: "draft-program", title: "Draft", locale: "en"})
      assert catch_exit(Export.run(["draft-program", out])) == {:shutdown, 1}
      assert_received {:mix_shell, :error, [message]}
      assert message == ~s(The program "draft-program" is not published)
      refute File.exists?(out)
    end

    @tag :tmp_dir
    test "exits with status 1 for an archived program", %{tmp_dir: tmp_dir} do
      program = LearningFixtures.publish_demo!()
      Repo.update!(change(program, status: :archived))

      assert catch_exit(Export.run([program.slug, tmp_dir])) == {:shutdown, 1}
      assert_received {:mix_shell, :error, [message]}
      assert message == ~s(The program "ai-assistant-basics-demo" is not published)
      assert File.ls!(tmp_dir) == []
    end

    test "exits with status 1 for invalid arguments" do
      for args <- [[], ["only-a-slug"], ["a", "b", "c"], ["a", "b", "--force"]] do
        assert catch_exit(Export.run(args)) == {:shutdown, 1}
        assert_received {:mix_shell, :error, ["Usage: mix espalier.export SLUG PATH"]}
      end
    end
  end
end
