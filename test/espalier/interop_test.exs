defmodule Espalier.InteropTest do
  @moduledoc """
  The context functions of task 0016 (steps 8 and 10): the XML escape
  function and the manifest templates (ASVS 1.1.2, 1.2.1 and 1.3.7), the
  request of an export with its job and audit event in one transaction,
  the lookup of an export, and the path and the name of a download (ASVS
  5.3.2 and 5.4.1).
  """
  # A test installs a trigger on audit_events; its table lock would block
  # the inserts of concurrent tests until the sandbox transaction ends.
  use Espalier.DataCase, async: false

  import Espalier.CredentialsFixtures, only: [user_with_role_fixture: 1]

  require Record

  alias Espalier.Accounts.Scope
  alias Espalier.{AccountsFixtures, Interop, LearningFixtures}
  alias Espalier.Audit.AuditEvent
  alias Espalier.Catalog.Module, as: CatalogModule
  alias Espalier.Catalog.Program
  alias Espalier.Interop.{Export, ExportWorker}

  doctest Espalier.Interop

  Record.defrecordp(
    :xml_text,
    :xmlText,
    Record.extract(:xmlText, from_lib: "xmerl/include/xmerl.hrl")
  )

  Record.defrecordp(
    :xml_attribute,
    :xmlAttribute,
    Record.extract(:xmlAttribute, from_lib: "xmerl/include/xmerl.hrl")
  )

  defp author_scope do
    author = user_with_role_fixture(:author)
    %{Scope.for_user(author) | roles: [:learner, :author]}
  end

  defp learner_scope, do: Scope.for_user(AccountsFixtures.user_fixture())

  # xmerl reads the bytes and decodes them by the encoding of the
  # declaration.
  defp parse!(xml) do
    {document, []} = :xmerl_scan.string(:binary.bin_to_list(xml), quiet: true)
    document
  end

  defp texts(document, path) do
    for node <- :xmerl_xpath.string(String.to_charlist(path), document),
        do: node |> xml_text(:value) |> List.to_string()
  end

  defp attributes(document, path) do
    for node <- :xmerl_xpath.string(String.to_charlist(path), document),
        do: node |> xml_attribute(:value) |> List.to_string()
  end

  describe "xml_escape/1" do
    test "encodes &, <, >, \" and ' as their predefined entities" do
      assert Interop.xml_escape("&") == "&amp;"
      assert Interop.xml_escape("<") == "&lt;"
      assert Interop.xml_escape(">") == "&gt;"
      assert Interop.xml_escape("\"") == "&quot;"
      assert Interop.xml_escape("'") == "&apos;"

      # One pass: the ampersand of an entity in the input is encoded once.
      assert Interop.xml_escape("&lt;") == "&amp;lt;"
    end

    test "keeps other text and replaces what XML 1.0 cannot hold with U+FFFD" do
      assert Interop.xml_escape("Wie Sprachmodelle schreiben – 1") ==
               "Wie Sprachmodelle schreiben – 1"

      assert Interop.xml_escape("tab\tline\nreturn\r") == "tab\tline\nreturn\r"
      assert Interop.xml_escape("a\u0001b\u000Bc") == "a�b�c"
      assert Interop.xml_escape(<<"a", 0xFF, "b">>) == "a�b"
    end
  end

  describe "manifest/2" do
    @markup ~s[Models <script>alert("x")</script> & 'you']

    test "escapes the module title and every file path in both templates" do
      for version <- [:scorm12, :scorm2004] do
        xml =
          Interop.manifest(version, %{
            identifier: "espalier-demo-module-1",
            title: @markup,
            files: ["LICENSE", "a&b <c>.txt"]
          })

        refute xml =~ "<script>"

        assert xml =~
                 "Models &lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt; &amp; &apos;you&apos;"

        document = parse!(xml)
        assert texts(document, "//*[local-name()='title']/text()") == [@markup, @markup]

        assert attributes(document, "//*[local-name()='file']/@href") ==
                 ["LICENSE", "a&b <c>.txt"]
      end
    end

    test "carries the schema version, the SCO type and the schema locations of each version" do
      assigns = %{identifier: "espalier-demo-module-1", title: "A module", files: ["LICENSE"]}

      document = parse!(Interop.manifest(:scorm12, assigns))
      assert texts(document, "//*[local-name()='schema']/text()") == ["ADL SCORM"]
      assert texts(document, "//*[local-name()='schemaversion']/text()") == ["1.2"]
      assert attributes(document, "//*[local-name()='resource']/@href") == ["index.html"]
      xml = Interop.manifest(:scorm12, assigns)
      assert xml =~ ~s(adlcp:scormtype="sco")
      assert xml =~ "imscp_rootv1p1p2.xsd"

      document = parse!(Interop.manifest(:scorm2004, assigns))
      assert texts(document, "//*[local-name()='schemaversion']/text()") == ["2004 4th Edition"]
      assert attributes(document, "//*[local-name()='resource']/@href") == ["index.html"]
      xml = Interop.manifest(:scorm2004, assigns)
      assert xml =~ ~s(adlcp:scormType="sco")
      assert xml =~ "imscp_v1p1.xsd"

      # One organization, one item, one resource; no objectives, no sequencing.
      for version <- [:scorm12, :scorm2004] do
        document = parse!(Interop.manifest(version, assigns))

        for element <- ~w(organization item resource) do
          assert [_one] = :xmerl_xpath.string(~c"//*[local-name()='#{element}']", document)
        end

        for element <- ~w(objectives sequencing) do
          assert [] = :xmerl_xpath.string(~c"//*[local-name()='#{element}']", document)
        end
      end
    end
  end

  describe "request_export/3" do
    setup do
      program = LearningFixtures.publish_demo!()
      %{program: program, module: LearningFixtures.module!(program, 1)}
    end

    test "queues the export with its job and the audit event", %{program: program, module: module} do
      scope = author_scope()

      assert {:ok, %Export{} = export} = Interop.request_export(scope, module.id, "scorm2004")
      assert export.status == :queued
      assert export.scorm_version == :scorm2004
      assert export.program_id == program.id
      assert export.module_id == module.id
      assert export.requested_by_id == scope.user.id
      assert export.program.slug == program.slug
      assert export.module.number == 1
      assert export.file_name == nil

      assert_enqueued(worker: ExportWorker, args: %{export_id: export.id}, queue: :exports)
      assert [%Oban.Job{args: args}] = all_enqueued(worker: ExportWorker)
      assert args == %{"export_id" => export.id}

      assert [event] = Repo.all(from e in AuditEvent, where: e.action == "export.requested")
      assert event.actor_id == scope.user.id
      assert event.subject_type == "Export"
      assert event.subject_id == export.id

      assert event.details == %{
               "program_slug" => program.slug,
               "module_number" => 1,
               "scorm_version" => "scorm2004"
             }
    end

    test "requires the role author", %{module: module} do
      assert Interop.request_export(learner_scope(), module.id, "scorm12") == {:error, :forbidden}
      assert Repo.aggregate(Export, :count) == 0
      refute_enqueued(worker: ExportWorker)
    end

    test "answers not_found for an unknown, malformed or archived module and an unpublished program",
         %{program: program, module: module} do
      scope = author_scope()

      for id <- [Ecto.UUID.generate(), "not-a-uuid", nil] do
        assert Interop.request_export(scope, id, "scorm12") == {:error, :not_found}
      end

      module_2 = LearningFixtures.module!(program, 2)
      now = DateTime.utc_now(:second)

      Repo.update_all(from(m in CatalogModule, where: m.id == ^module_2.id),
        set: [archived_at: now]
      )

      assert Interop.request_export(scope, module_2.id, "scorm12") == {:error, :not_found}

      Repo.update_all(from(p in Program, where: p.id == ^program.id), set: [status: :draft])
      assert Interop.request_export(scope, module.id, "scorm12") == {:error, :not_found}

      assert Repo.aggregate(Export, :count) == 0
      refute_enqueued(worker: ExportWorker)
    end

    test "answers a changeset for a version outside the two", %{module: module} do
      assert {:error, %Ecto.Changeset{} = changeset} =
               Interop.request_export(author_scope(), module.id, "scorm3")

      assert errors_on(changeset) == %{scorm_version: ["is invalid"]}
      refute_enqueued(worker: ExportWorker)
    end

    test "writes neither the export nor its job when the audit event fails", %{module: module} do
      fail_on!("audit_events", "INSERT", "NEW.action = 'export.requested'")

      assert_raise Postgrex.Error, ~r/forced failure/, fn ->
        Interop.request_export(author_scope(), module.id, "scorm12")
      end

      assert Repo.aggregate(Export, :count) == 0
      refute_enqueued(worker: ExportWorker)
    end
  end

  describe "get_export/2, package_path/1 and download_name/1" do
    setup do
      program = LearningFixtures.publish_demo!()
      scope = author_scope()
      module = LearningFixtures.module!(program, 1)
      {:ok, export} = Interop.request_export(scope, module.id, "scorm12")
      %{program: program, scope: scope, export: export}
    end

    test "returns the export with its program and module to an author",
         %{scope: scope, export: export, program: program} do
      assert {:ok, found} = Interop.get_export(scope, export.id)
      assert found.id == export.id
      assert found.program.slug == program.slug
      assert found.module.number == 1

      assert Interop.get_export(learner_scope(), export.id) == {:error, :forbidden}
      assert Interop.get_export(scope, Ecto.UUID.generate()) == {:error, :not_found}
      assert Interop.get_export(scope, "not-a-uuid") == {:error, :not_found}
    end

    test "names the download after the program slug, the module number and the version",
         %{scope: scope, export: export, program: program} do
      {:ok, export} = Interop.get_export(scope, export.id)
      assert Interop.download_name(export) == "#{program.slug}-module-1-scorm12.zip"
    end

    test "answers export_not_ready unless the export is done", %{export: export} do
      for status <- [:queued, :running, :failed] do
        assert Interop.package_path(%{export | status: status, file_name: "#{export.id}.zip"}) ==
                 {:error, :export_not_ready}
      end
    end

    test "builds the path from EXPORT_DIR and a plain stored basename only", %{export: export} do
      dir = Interop.export_dir()
      assert Path.type(dir) == :absolute
      name = "#{export.id}.zip"
      path = Path.join(dir, name)
      File.mkdir_p!(dir)
      File.write!(path, "PK")
      on_exit(fn -> File.rm(path) end)

      assert Interop.package_path(%{export | status: :done, file_name: name}) == {:ok, path}

      # The worker always stores a basename; any other value names no file.
      for file_name <- [nil, "", ".", "..", "../#{name}", "sub/#{name}", "/etc/passwd", "a\\b"] do
        assert Interop.package_path(%{export | status: :done, file_name: file_name}) ==
                 {:error, :not_found},
               inspect(file_name)
      end

      # A done export whose file is gone.
      File.rm!(path)

      assert Interop.package_path(%{export | status: :done, file_name: name}) ==
               {:error, :not_found}
    end
  end

  # Makes every row operation `event` on `table` that matches `condition`
  # fail. The rollback of the sandbox transaction removes the trigger.
  defp fail_on!(table, event, condition) do
    Repo.query!("""
    CREATE FUNCTION espalier_test_fail() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN
      RAISE EXCEPTION 'forced failure on %', TG_TABLE_NAME;
    END
    $$
    """)

    Repo.query!("""
    CREATE TRIGGER espalier_test_fail BEFORE #{event} ON #{table}
    FOR EACH ROW WHEN (#{condition}) EXECUTE FUNCTION espalier_test_fail()
    """)
  end
end
