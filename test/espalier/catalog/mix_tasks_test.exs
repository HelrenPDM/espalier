defmodule Espalier.Catalog.MixTasksTest do
  # The tests capture standard error, which is a global device, so the module
  # runs after the asynchronous tests.
  use ExUnit.Case, async: false

  import Espalier.PackFixtures
  import ExUnit.CaptureIO

  alias Mix.Tasks.Espalier.{Alignment, Validate}

  @items1 "modules/01-basics/items.yaml"
  @objectives2 "modules/02-checking/objectives.yaml"

  @columns [:module, :area, :depth, :objectives, :lessons, :evidence, :elsewhere]
  @areas ~w(subject method self social)
  @depths ~w(know apply judge)

  @text_header "module\tarea\tdepth\tobjectives\tlessons\tevidence\telsewhere"
  @csv_header "module,area,depth,objectives,lessons,evidence,elsewhere"

  @orphan_message "item `m1-exam-2` names no objective in `objectives`, " <>
                    "but the assessment `m1-exam` lists it and counts for a credential"

  @depth_message "evidence of objective `m2-method-release-check` has the kinds " <>
                   "`checklist_drill`, none of which fits the depth `know` " <>
                   "(`single_choice` or `multiple_choice`)"

  describe "mix espalier.alignment" do
    test "prints a header, 24 rows and no finding for the demo pack in text" do
      {stdout, stderr} = run_ok(Alignment, [demo_path()])

      assert lines(stdout) == [@text_header | Enum.map(demo_matrix(), &text_line/1)]
      assert length(lines(stdout)) == 25
      assert stderr == ""
    end

    test "separates text fields by tabs, joins lists by commas and marks empty fields with a dash" do
      {stdout, _stderr} = run_ok(Alignment, [demo_path(), "--format", "text"])
      rows = tl(lines(stdout))

      assert ("1\tsubject\tknow\tm1-subject-next-word,m1-subject-varying-answers\t" <>
                "01-first-lesson,02-second-lesson\titem:m1-exam-confident-answer," <>
                "item:m1-exam-next-word,item:m1-exam-varying-answers,item:m1-fluent-figure," <>
                "item:m1-how-models-write,item:m1-why-answers-vary\t-") in rows

      assert "1\tself\tjudge\tm1-self-own-responsibility\t03-third-lesson\tformat:workshop\t-" in rows
      assert "1\tsubject\tapply\t-\t-\t-\t-" in rows
      assert "2\tsocial\tknow\t-\t-\t-\tformat:workshop" in rows
      assert Enum.all?(rows, &(length(String.split(&1, "\t")) == 7))
    end

    test "prints the header of step 13 and 24 records for the demo pack in csv" do
      {stdout, stderr} = run_ok(Alignment, [demo_path(), "--format", "csv"])
      [header | records] = lines(stdout)

      assert header == @csv_header
      assert length(records) == 24
      assert records == Enum.map(demo_matrix(), &csv_line/1)

      assert ("1,subject,know,m1-subject-next-word m1-subject-varying-answers," <>
                "01-first-lesson 02-second-lesson,item:m1-exam-confident-answer " <>
                "item:m1-exam-next-word item:m1-exam-varying-answers item:m1-fluent-figure " <>
                "item:m1-how-models-write item:m1-why-answers-vary,") in records

      assert "1,subject,apply,,,," in records
      assert "2,social,judge,,,,format:workshop" in records

      # No field starts with a character that a spreadsheet reads as a formula.
      for record <- records, field <- String.split(record, ",") do
        refute String.starts_with?(field, ["=", "+", "-", "@", "\t", "\r"])
      end

      assert stderr == ""
    end

    test "prints 24 matrix rows and empty errors and warnings for the demo pack in json" do
      {stdout, stderr} = run_ok(Alignment, [demo_path(), "--format", "json"])
      decoded = JSON.decode!(stdout)

      assert %{"matrix" => matrix, "errors" => [], "warnings" => []} = decoded
      assert length(matrix) == 24
      assert matrix == Enum.map(demo_matrix(), &string_keys/1)
      assert stderr == ""
    end

    test "an orphan exam item exits with status 1 and prints the error with file and line" do
      pack = copy_pack!("minimal") |> orphan_exam_item!()
      line = line_of!(pack, @items1, "key: m1-exam-2")

      {stdout, stderr} = run_exit(Alignment, [pack])
      [header | rest] = lines(stdout)
      {rows, findings} = Enum.split(rest, 24)

      assert header == @text_header
      assert Enum.all?(rows, &String.match?(&1, ~r/^[12]\t/))
      assert findings == ["#{@items1}:#{line}: #{@orphan_message}"]
      assert stderr == ""
    end

    test "an orphan exam item with alignment warn returns and prints the finding as a warning line" do
      pack = copy_pack!("minimal") |> orphan_exam_item!() |> warn_mode!()
      line = line_of!(pack, @items1, "key: m1-exam-2")

      {stdout, stderr} = run_ok(Alignment, [pack])
      [header | rest] = lines(stdout)
      {rows, findings} = Enum.split(rest, 24)

      assert header == @text_header
      assert Enum.all?(rows, &String.match?(&1, ~r/^[12]\t/))
      assert findings == ["#{@items1}:#{line}: warning: #{@orphan_message}"]
      assert stderr == ""
    end

    test "an orphan exam item in csv prints the records to standard output and the error to standard error" do
      pack = copy_pack!("minimal") |> orphan_exam_item!()
      line = line_of!(pack, @items1, "key: m1-exam-2")

      {stdout, stderr} = run_exit(Alignment, [pack, "--format", "csv"])
      [header | records] = lines(stdout)

      assert header == @csv_header
      assert length(records) == 24
      assert lines(stderr) == ["#{@items1}:#{line}: #{@orphan_message}"]
    end

    test "an orphan exam item in json exits with status 1 and holds the error with check, module and key" do
      pack = copy_pack!("minimal") |> orphan_exam_item!()
      line = line_of!(pack, @items1, "key: m1-exam-2")

      {stdout, _stderr} = run_exit(Alignment, [pack, "--format", "json"])

      assert %{"matrix" => matrix, "errors" => [error], "warnings" => []} = JSON.decode!(stdout)
      assert length(matrix) == 24

      assert error == %{
               "check" => 2,
               "module" => 1,
               "key" => "m1-exam-2",
               "file" => @items1,
               "line" => line,
               "message" => @orphan_message
             }
    end

    test "an unknown objective key exits with status 1 and prints the error without a matrix" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "objectives: [m1-method-build-prompt]",
        "objectives: [m1-method-missing]"
      )

      error_line =
        "#{@items1}:#{line_of!(pack, @items1, "[m1-method-missing]")}: " <>
          "unknown objective `m1-method-missing` in `objectives`"

      {stdout, stderr} = run_exit(Alignment, [pack])
      assert lines(stdout) == [error_line]
      refute stdout =~ "module\tarea"
      assert stderr == ""

      {stdout, stderr} = run_exit(Alignment, [pack, "--format", "csv"])
      assert stdout == ""
      assert lines(stderr) == [error_line]

      {stdout, _stderr} = run_exit(Alignment, [pack, "--format", "json"])
      assert lines(stdout) == [error_line]
      refute stdout =~ "matrix"
    end

    test "a loader error exits with status 1 and prints the error without a matrix" do
      pack = copy_pack!("minimal")
      File.ln_s!(path(pack, "sources.yaml"), path(pack, "modules/01-basics/notes.yaml"))

      {stdout, stderr} = run_exit(Alignment, [pack])

      assert lines(stdout) == [
               "modules/01-basics/notes.yaml:1: symbolic links are not allowed in a pack"
             ]

      assert stderr == ""
    end

    test "a check 4 warning alone returns and prints the matrix and the warning line" do
      pack = copy_pack!("minimal") |> depth_mismatch!()
      line = line_of!(pack, @objectives2, "key: m2-method-release-check")

      {stdout, stderr} = run_ok(Alignment, [pack])
      [header | rest] = lines(stdout)
      {rows, findings} = Enum.split(rest, 24)

      assert header == @text_header
      assert "2\tmethod\tknow\tm2-method-release-check\t01-check\titem:m2-drill\t-" in rows
      assert "2\tmethod\tapply\t-\t-\t-\t-" in rows
      assert "2\tsocial\tknow\t-\t-\t-\tmodule:1" in rows
      assert findings == ["#{@objectives2}:#{line}: warning: #{@depth_message}"]
      assert stderr == ""
    end

    test "--format xml exits with status 1 and prints no matrix" do
      {stdout, stderr} = run_exit(Alignment, [demo_path(), "--format", "xml"])

      assert stdout == ""
      assert stderr =~ "xml"
    end
  end

  describe "mix espalier.validate" do
    test "the demo pack prints nothing and returns" do
      assert run_ok(Validate, [demo_path()]) == {"", ""}
    end

    test "a pack with only a check 4 finding prints one warning line and returns, in both modes" do
      for mode <- [:strict, :warn] do
        pack = copy_pack!("minimal") |> depth_mismatch!()
        if mode == :warn, do: warn_mode!(pack)
        line = line_of!(pack, @objectives2, "key: m2-method-release-check")

        {stdout, stderr} = run_ok(Validate, [pack])

        assert lines(stdout) == ["#{@objectives2}:#{line}: warning: #{@depth_message}"]
        assert stderr == ""
      end
    end

    test "an error and a warning print the error line first and exit with status 1" do
      pack = copy_pack!("minimal") |> orphan_exam_item!() |> depth_mismatch!()
      item_line = line_of!(pack, @items1, "key: m1-exam-2")
      objective_line = line_of!(pack, @objectives2, "key: m2-method-release-check")

      {stdout, _stderr} = run_exit(Validate, [pack])

      assert lines(stdout) == [
               "#{@items1}:#{item_line}: #{@orphan_message}",
               "#{@objectives2}:#{objective_line}: warning: #{@depth_message}"
             ]

      warn_mode!(pack)
      {stdout, _stderr} = run_ok(Validate, [pack])

      assert lines(stdout) == [
               "#{@items1}:#{item_line}: warning: #{@orphan_message}",
               "#{@objectives2}:#{objective_line}: warning: #{@depth_message}"
             ]
    end

    test "a key with a raw line break prints one error line and forges no warning line" do
      pack = copy_pack!("minimal")
      forged = ~s("x`\\n#{@items1}:3: warning: checked": 1\n)
      write!(pack, "pack.yaml", read!(pack, "pack.yaml") <> forged)
      expected = ["pack.yaml:7: unknown field `x`\\x0A#{@items1}:3: warning: checked`"]

      {stdout, stderr} = run_exit(Validate, [pack])
      assert lines(stdout) == expected
      assert stderr == ""

      {stdout, _stderr} = run_exit(Alignment, [pack])
      assert lines(stdout) == expected
    end

    test "a glossary reference with a raw line break prints one line" do
      pack = copy_pack!("minimal")
      lesson = "modules/01-basics/lessons/01-intro.md"
      replace!(pack, lesson, "[[term:assistant|writing assistant]]", "[[term:no-\nsuch]]")

      {stdout, _stderr} = run_exit(Validate, [pack])

      assert lines(stdout) == [
               "#{lesson}:6: unknown glossary term `no-\\x0Asuch` in `[[term:no-\\x0Asuch]]`"
             ]
    end

    test "a lesson of many stray lines prints its first 100 errors and a closing line" do
      pack = copy_pack!("minimal")
      lesson = "modules/02-checking/lessons/09-stray.md"

      write!(
        pack,
        lesson,
        "---\ntitle: Stray\nposition: 9\n---\n" <> String.duplicate("x\n", 5_000)
      )

      {stdout, _stderr} = run_exit(Validate, [pack])

      assert lines(stdout) ==
               Enum.map(5..104, &"#{lesson}:#{&1}: text outside a block") ++
                 ["#{lesson}:104: and 4,900 further errors in this file"]
    end
  end

  # Runs a task that returns `:ok` and gives its standard output and standard
  # error.
  defp run_ok(task, args) do
    {{result, stdout}, stderr} = with_io(:stderr, fn -> with_io(fn -> task.run(args) end) end)
    assert result == :ok
    {stdout, stderr}
  end

  # Runs a task that ends with `exit({:shutdown, 1})` and gives its standard
  # output and standard error.
  defp run_exit(task, args) do
    {{reason, stdout}, stderr} =
      with_io(:stderr, fn -> with_io(fn -> catch_exit(task.run(args)) end) end)

    assert reason == {:shutdown, 1}
    {stdout, stderr}
  end

  # The lines of an output that ends with a line break. CSV records end with
  # CRLF (RFC 4180).
  defp lines(output) do
    assert String.ends_with?(output, "\n")
    output |> String.split(~r/\r?\n/) |> Enum.drop(-1)
  end

  # Removes the objectives of the exam item `m1-exam-2` of the minimal pack.
  defp orphan_exam_item!(pack) do
    replace!(
      pack,
      @items1,
      "  objectives: [m1-subject-next-word]\n  rules: [1]\n  options:\n" <>
        "    - key: a\n      label: Compare with a source",
      "  rules: [1]\n  options:\n    - key: a\n      label: Compare with a source"
    )

    pack
  end

  # Gives `m2-method-release-check`, whose only evidence is a checklist
  # drill, the depth `know`.
  defp depth_mismatch!(pack) do
    replace!(pack, @objectives2, "depth: apply", "depth: know")
    pack
  end

  defp warn_mode!(pack) do
    replace!(pack, "pack.yaml", "version: 0.1.0", "version: 0.1.0\nalignment: warn")
    pack
  end

  # The alignment matrix of content/demo as step 12 of the spec describes the
  # pack, in the order of step 13: modules by number, areas subject, method,
  # self, social, and depths know, apply, judge.
  defp demo_matrix do
    filled = %{
      {1, "subject", "know"} =>
        {~w(m1-subject-next-word m1-subject-varying-answers),
         ~w(01-first-lesson 02-second-lesson),
         ~w(item:m1-exam-confident-answer item:m1-exam-next-word item:m1-exam-varying-answers
            item:m1-fluent-figure item:m1-how-models-write item:m1-why-answers-vary)},
      {1, "method", "know"} =>
        {~w(m1-method-check-claims), ~w(03-third-lesson),
         ~w(item:m1-before-use item:m1-exam-check-claims)},
      {1, "self", "judge"} =>
        {~w(m1-self-own-responsibility), ~w(03-third-lesson), ~w(format:workshop)},
      {1, "social", "judge"} =>
        {~w(m1-social-team-transparency), ~w(03-third-lesson), ~w(format:workshop)},
      {2, "subject", "apply"} =>
        {~w(m2-subject-prompt-parts), ~w(01-first-lesson), ~w(item:m2-prompt-builder)},
      {2, "method", "apply"} =>
        {~w(m2-method-release-check), ~w(02-second-lesson), ~w(item:m2-release-drill)},
      {2, "method", "judge"} =>
        {~w(m2-method-judge-output), ~w(02-second-lesson), ~w(item:m2-judge-drafts)}
    }

    # Module 2 has no self and no social objective and names the workshop.
    elsewhere = %{{2, "self"} => "format:workshop", {2, "social"} => "format:workshop"}

    for module <- [1, 2], area <- @areas, depth <- @depths do
      {objectives, lessons, evidence} = Map.get(filled, {module, area, depth}, {[], [], []})

      %{
        module: module,
        area: area,
        depth: depth,
        objectives: objectives,
        lessons: lessons,
        evidence: evidence,
        elsewhere: Map.get(elsewhere, {module, area})
      }
    end
  end

  defp text_line(row) do
    Enum.map_join(@columns, "\t", fn column ->
      case Map.fetch!(row, column) do
        empty when empty in [nil, []] -> "-"
        list when is_list(list) -> Enum.join(list, ",")
        value -> to_string(value)
      end
    end)
  end

  # No field of the demo matrix holds a comma, a quote or a line break, so
  # no field is quoted.
  defp csv_line(row) do
    Enum.map_join(@columns, ",", fn column ->
      case Map.fetch!(row, column) do
        nil -> ""
        list when is_list(list) -> Enum.join(list, " ")
        value -> to_string(value)
      end
    end)
  end

  defp string_keys(row), do: Map.new(row, fn {key, value} -> {Atom.to_string(key), value} end)
end
