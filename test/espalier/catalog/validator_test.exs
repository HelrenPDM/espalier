defmodule Espalier.Catalog.ValidatorTest do
  use ExUnit.Case, async: true

  import Espalier.PackFixtures

  alias Espalier.Catalog.Pack.{Loader, Spdx, Validator}

  @module1 "modules/01-basics/module.yaml"
  @module2 "modules/02-checking/module.yaml"
  @objectives1 "modules/01-basics/objectives.yaml"
  @objectives2 "modules/02-checking/objectives.yaml"
  @rules1 "modules/01-basics/rules.yaml"
  @items1 "modules/01-basics/items.yaml"
  @items2 "modules/02-checking/items.yaml"
  @assessment1 "modules/01-basics/assessment.yaml"
  @intro "modules/01-basics/lessons/01-intro.md"
  @practice "modules/01-basics/lessons/02-practice.md"

  defp license_message,
    do:
      "`license` must be an SPDX license expression such as `CC0-1.0` or " <>
        "`MIT OR Apache-2.0`, with ids of SPDX License List #{Spdx.list_version()}"

  defp run!(pack) do
    assert {:ok, loaded} = Loader.load(pack)
    Validator.run(loaded)
  end

  defp errors(pack),
    do: pack |> run!() |> Map.fetch!(:errors) |> Enum.map(&{&1.file, &1.line, &1.message})

  # The errors of a loaded map that a test built or changed by hand.
  defp loaded_errors(loaded) do
    %{errors: errors} = Validator.run(loaded)
    Enum.map(errors, &{&1.file, &1.line, &1.message})
  end

  # Applies `fun` to the data of the top-level file `file` of a loaded map.
  defp update_data(loaded, file, fun), do: update_in(loaded, [:files, file, :data], fun)

  # Applies `fun` to the first block of the first lesson of the first module.
  defp update_first_block(loaded, fun) do
    update_in(
      loaded,
      [:modules, Access.at(0), :lessons, Access.at(0), :blocks, Access.at(0)],
      fun
    )
  end

  defp warn_mode!(pack),
    do: replace!(pack, "pack.yaml", "version: 0.1.0", "version: 0.1.0\nalignment: warn")

  # Runs `fun` on a copy in strict mode and on a copy in warn mode.
  defp in_both_modes(fun) do
    for mode <- [:strict, :warn] do
      pack = copy_pack!("minimal")
      if mode == :warn, do: warn_mode!(pack)
      fun.(pack)
    end
  end

  describe "a valid pack" do
    test "the minimal pack has no errors and no warnings and gives a payload" do
      pack = copy_pack!("minimal")
      assert %{errors: [], warnings: [], payload: %{"key" => "minimal-pack"}} = run!(pack)

      assert {:ok, loaded} = Loader.load(pack)
      assert Validator.validate(loaded) == {[], []}
    end

    test "the demo pack has no errors and no warnings" do
      assert {:ok, loaded} = Loader.load(demo_path())
      assert Validator.validate(loaded) == {[], []}
    end
  end

  describe "schema" do
    test "rejects schema 2, names the supported versions and reports nothing else" do
      pack = copy_pack!("minimal")
      replace!(pack, "pack.yaml", "schema: 1", "schema: 2")
      replace!(pack, "sources.yaml", "kind: other", "kind: unknown")

      assert %{errors: [error], warnings: [], payload: nil} = run!(pack)

      assert error == %{
               file: "pack.yaml",
               line: 1,
               message: "unsupported schema version `2`; supported versions: `1`"
             }
    end

    test "rejects a schema that is no integer and names the supported versions" do
      for {value, shown} <- [
            {~s("1"), ~s("1")},
            {"1.0", "1.0"},
            {"[1]", "[1]"},
            {"true", "true"},
            {"2147483648", "2147483648"}
          ] do
        pack = copy_pack!("minimal")
        replace!(pack, "pack.yaml", "schema: 1", "schema: #{value}")
        replace!(pack, "sources.yaml", "kind: other", "kind: unknown")

        assert errors(pack) == [
                 {"pack.yaml", 1,
                  "unsupported schema version `#{shown}`; supported versions: `1`"}
               ]
      end
    end

    test "rejects an unknown field" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "glossary.yaml",
        "  label: Writing assistant",
        "  label: Writing assistant\n  colour: blue"
      )

      assert errors(pack) == [{"glossary.yaml", 3, "unknown field `colour`"}]
    end

    test "rejects a missing required field at the line of the entry" do
      pack = copy_pack!("minimal")
      replace!(pack, "sources.yaml", "  publisher: Fictional Publisher (invented)\n", "")
      assert errors(pack) == [{"sources.yaml", 1, "missing field `publisher`"}]
    end

    test "rejects a field without a value" do
      pack = copy_pack!("minimal")
      replace!(pack, "segments.yaml", "  label: Everyone", "  label:")
      assert errors(pack) == [{"segments.yaml", 2, "`label` has no value"}]
    end

    test "rejects values of the wrong type without converting them" do
      pack = copy_pack!("minimal")
      replace!(pack, @module1, "number: 1", ~s(number: "1"))

      replace!(
        pack,
        @items1,
        "  core: false\n  phase: orient",
        ~s(  core: "false"\n  phase: orient)
      )

      replace!(pack, "segments.yaml", "default_path: short", "default_path: medium")
      replace!(pack, @module2, "phases: [apply, update]", "phases: [apply, later]")

      assert errors(pack) == [
               {@items1, line_of!(pack, @items1, ~s(core: "false")),
                "`core` must be `true` or `false`"},
               {@module1, 1, "`number` must be an integer"},
               {@module2, 4,
                "entries of `phases` must be one of `orient`, `understand`, `apply`, `anchor`, `update`"},
               {"segments.yaml", 4, "`default_path` must be one of `short`, `full`"}
             ]
    end

    test "rejects keys outside the key format" do
      pack = copy_pack!("minimal")
      replace!(pack, "glossary.yaml", "- slug: assistant", "- slug: Assistant")

      assert errors(pack) == [
               {"glossary.yaml", 1,
                "`slug` value `Assistant` does not match the key format `^[a-z0-9][a-z0-9-]*$`"}
             ]
    end

    test "rejects a key, a list entry, a target, a cite, a locale and a license with a trailing newline" do
      pack = copy_pack!("minimal")
      replace!(pack, "pack.yaml", "key: minimal-pack", ~s(key: "minimal-pack\\n"))
      replace!(pack, "pack.yaml", "locale: en", ~s(locale: "en\\n"))
      replace!(pack, "pack.yaml", "license: CC0-1.0", ~s(license: "CC0-1.0\\n"))
      replace!(pack, @items1, "- key: m1-choice", ~s(- key: "m1-choice\\n"))
      replace!(pack, @items1, "  reveals: [01-intro]", ~s(  reveals: ["01-intro\\n"]))

      replace!(
        pack,
        @items1,
        ~s(  cite: ["fictional-guide#Section 1"]),
        ~s(  cite: ["fictional-guide#Section 1\\n"])
      )

      replace!(pack, "qualifications.yaml", "target: usage-policy", ~s(target: "usage-policy\\n"))

      assert errors(pack) == [
               {@items1, 1,
                ~s(`key` value `"m1-choice\\n"` does not match the key format `^[a-z0-9][a-z0-9-]*$`)},
               {@items1, 10,
                ~s(`reveals` value `"01-intro\\n"` does not match the key format `^[a-z0-9][a-z0-9-]*$`)},
               {@items1, 11,
                ~s(`cite` entry `"fictional-guide#Section 1\\n"` does not have the form `source-key#locator`)},
               {"pack.yaml", 2,
                ~s(`key` value `"minimal-pack\\n"` does not match the key format `^[a-z0-9][a-z0-9-]*$`)},
               {"pack.yaml", 4, "`locale` must be a language tag such as `en` or `de-DE`"},
               {"pack.yaml", 5, license_message()},
               {"qualifications.yaml", 17,
                "the `target` of a `policy_acknowledged` requirement must be a string in the key format"}
             ]
    end

    test "rejects dates with a sign and dates that do not exist" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "sources.yaml",
        ~s(edition_date: "2026-01-15"),
        ~s(edition_date: "+2026-03-01")
      )

      replace!(
        pack,
        "sources.yaml",
        ~s(retrieved_on: "2026-05-30"),
        ~s(retrieved_on: "2026-02-30")
      )

      assert errors(pack) == [
               {"sources.yaml", 5,
                "`edition_date` must be a date in the form `YYYY-MM-DD`, got `+2026-03-01`"},
               {"sources.yaml", 6,
                "`retrieved_on` must be a date in the form `YYYY-MM-DD`, got `2026-02-30`"}
             ]

      newline = copy_pack!("minimal")

      replace!(
        newline,
        "sources.yaml",
        ~s(edition_date: "2026-01-15"),
        ~s(edition_date: "2026-01-15\\n")
      )

      assert errors(newline) == [
               {"sources.yaml", 5,
                ~s(`edition_date` must be a date in the form `YYYY-MM-DD`, got `"2026-01-15\\n"`)}
             ]
    end

    test "rejects a NUL character in any string that reaches the validator" do
      assert {:ok, loaded} = Loader.load(copy_pack!("minimal"))

      loaded =
        loaded
        |> update_data("pack.yaml", &Map.put(&1, "title", "Minimal\0pack"))
        |> update_data("qualifications.yaml", fn [first | rest] ->
          [Map.put(first, "unlocks", ["Draft\0notes"]) | rest]
        end)
        |> update_data("stations.yaml", fn [first | rest] ->
          config = %{"question" => "How\0often?", "na\0me" => "x"}
          [Map.put(first, "config", config) | rest]
        end)
        |> update_first_block(&Map.put(&1, :body, "A text\0with a NUL."))

      assert loaded_errors(loaded) == [
               {@intro, 6, "`body` must not contain a NUL character"},
               {"pack.yaml", 3, "`title` must not contain a NUL character"},
               {"qualifications.yaml", 5,
                "entries of `unlocks` must not contain a NUL character"},
               {"stations.yaml", 3, "`config` must not contain a NUL character"},
               {"stations.yaml", 4, "`config` must not contain a NUL character"}
             ]
    end

    test "rejects a lesson key over 255 characters" do
      assert {:ok, loaded} = Loader.load(copy_pack!("minimal"))
      path = [:modules, Access.at(0), :lessons, Access.at(0), :key]

      # A key of 255 characters passes the schema stage; the cross-file checks
      # then report the references to the old key `01-intro` only.
      at_bound = loaded |> put_in(path, String.duplicate("a", 255)) |> loaded_errors()
      assert at_bound != []

      assert Enum.all?(at_bound, fn {_file, _line, message} ->
               message =~ "unknown lesson `01-intro`"
             end)

      assert loaded |> put_in(path, String.duplicate("a", 256)) |> loaded_errors() == [
               {@intro, 1, "the lesson key must have at most 255 characters"}
             ]
    end

    test "rejects a file of the wrong top-level type and an entry that is no map" do
      pack = copy_pack!("minimal")
      write!(pack, "segments.yaml", "key: everyone\n")
      write!(pack, "sources.yaml", "- just a string\n")
      write!(pack, "pack.yaml", "- schema: 1\n")

      assert errors(pack) == [
               {"pack.yaml", 1, "`pack.yaml` must hold a map"},
               {"segments.yaml", 1, "`segments.yaml` must hold a list of entries"},
               {"sources.yaml", 1, "an entry must be a map"}
             ]
    end

    test "rejects an invalid locale and license" do
      pack = copy_pack!("minimal")
      replace!(pack, "pack.yaml", "locale: en", "locale: English")
      replace!(pack, "pack.yaml", "license: CC0-1.0", "license: free for all")

      assert errors(pack) == [
               {"pack.yaml", 4, "`locale` must be a language tag such as `en` or `de-DE`"},
               {"pack.yaml", 5, license_message()}
             ]
    end

    test "rejects a lesson without blocks and a block with an invalid attribute value" do
      pack = copy_pack!("minimal")
      write!(pack, @practice, "---\ntitle: Practice\nposition: 2\n---\n")
      replace!(pack, @intro, "collapsed_on=short", "collapsed_on=never")

      assert errors(pack) == [
               {@intro, 10, "entries of `collapsed_on` must be one of `short`, `full`"},
               {@practice, 1, "the lesson has no blocks"}
             ]
    end

    test "rejects the provenance placeholder on a block of another kind" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @practice,
        ":::example{provenance=invented}",
        ":::example{provenance=placeholder}"
      )

      assert errors(pack) == [
               {@practice, 6, "the provenance `placeholder` belongs to `placeholder` blocks only"}
             ]
    end
  end

  describe "uniqueness" do
    test "a source key is unique in its file" do
      pack = copy_pack!("minimal")
      write!(pack, "sources.yaml", read!(pack, "sources.yaml") <> read!(pack, "sources.yaml"))

      assert errors(pack) == [
               {"sources.yaml", 8,
                "duplicate source key `fictional-guide`, first used in `sources.yaml` at line 1"}
             ]
    end

    test "a format key, a segment key, a glossary slug and a qualification code are unique in their file" do
      pack = copy_pack!("minimal")
      replace!(pack, "formats.yaml", "- key: handbook", "- key: workshop")
      write!(pack, "segments.yaml", read!(pack, "segments.yaml") <> read!(pack, "segments.yaml"))
      write!(pack, "glossary.yaml", read!(pack, "glossary.yaml") <> read!(pack, "glossary.yaml"))
      replace!(pack, "qualifications.yaml", "- code: workshop", "- code: basics")

      errors = errors(pack)

      assert {"formats.yaml", 7,
              "duplicate format key `workshop`, first used in `formats.yaml` at line 1"} in errors

      assert {"segments.yaml", 5,
              "duplicate segment key `everyone`, first used in `segments.yaml` at line 1"} in errors

      assert {"glossary.yaml", 4,
              "duplicate glossary slug `assistant`, first used in `glossary.yaml` at line 1"} in errors

      assert {"qualifications.yaml", 18,
              "duplicate qualification code `basics`, first used in `qualifications.yaml` at line 1"} in errors
    end

    test "an item key is unique in the pack" do
      pack = copy_pack!("minimal")
      replace!(pack, @items2, "- key: m2-drill", "- key: m1-poll")

      assert errors(pack) == [
               {@items2, line_of!(pack, @items2, "key: m1-poll"),
                "duplicate item key `m1-poll`, first used in `#{@items1}` at line #{line_of!(pack, @items1, "key: m1-poll")}"}
             ]
    end

    test "an assessment key is unique in the pack" do
      pack = copy_pack!("minimal")

      write!(pack, "modules/02-checking/assessment.yaml", """
      - key: m1-exam
        title: Practice set
        kind: practice
        counts_for_credential: false
        max_wrong: 0
        core_required: false
        items: [m2-drill]
      """)

      assert {"modules/02-checking/assessment.yaml", 1,
              "duplicate assessment key `m1-exam`, first used in `#{@assessment1}` at line 1"} in errors(
               pack
             )
    end

    test "rule numbers are unique in their module" do
      pack = copy_pack!("minimal")
      replace!(pack, @rules1, "- number: 2", "- number: 1")

      assert {@rules1, 5, "duplicate rule number `1`, first used in `#{@rules1}` at line 1"} in errors(
               pack
             )
    end

    test "lesson positions are unique in their module" do
      pack = copy_pack!("minimal")
      replace!(pack, @practice, "position: 2", "position: 1")

      assert errors(pack) == [
               {@practice, 3,
                "duplicate lesson position `1`, first used in `#{@intro}` at line 3"}
             ]
    end

    test "module numbers are unique in the pack" do
      pack = copy_pack!("minimal")
      replace!(pack, @module2, "number: 2", "number: 1")

      assert {@module2, 1, "duplicate module number `1`, first used in `#{@module1}` at line 1"} in errors(
               pack
             )
    end

    test "slot, category, case, check, question and question option keys are unique in their list" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "            feedback: Too vague.\n",
        """
                    feedback: Too vague.
              - key: task
                label: Task again
                options:
                  - key: x
                    label: X
                    correct: true
                    feedback: Yes.
                  - key: y
                    label: Y
                    correct: false
                    feedback: No.
        """
      )

      replace!(pack, @items2, "      - key: fine\n", "      - key: check\n")
      replace!(pack, @items2, "      - key: greeting\n", "      - key: number\n")
      replace!(pack, @items2, "      - key: tone\n", "      - key: facts\n")
      replace!(pack, "feedback.yaml", "  - key: comment\n", "  - key: rating\n")
      replace!(pack, "feedback.yaml", ~s(      - key: "no"\n), ~s(      - key: "yes"\n))

      assert errors(pack) == [
               {"feedback.yaml", 9, "duplicate key `yes` in `options`"},
               {"feedback.yaml", 14, "duplicate key `rating` in `questions`"},
               {@items1, line_of!(pack, @items1, "- key: task", after: "feedback: Too vague."),
                "duplicate key `task` in `slots`"},
               {@items2, 14, "duplicate key `check` in `categories`"},
               {@items2, 20, "duplicate key `number` in `cases`"},
               {@items2, 40, "duplicate key `facts` in `checks`"}
             ]
    end

    test "lesson keys, lesson positions, rule numbers and option keys may repeat in another scope" do
      pack = copy_pack!("minimal")

      File.rename!(
        path(pack, "modules/02-checking/lessons/01-check.md"),
        path(pack, "modules/02-checking/lessons/01-intro.md")
      )

      replace!(pack, @items2, "lesson: 01-check", "lesson: 01-intro", global: true)
      replace!(pack, @objectives2, "taught_in: [01-check]", "taught_in: [01-intro]", global: true)

      assert %{errors: [], warnings: [], payload: payload} = run!(pack)
      assert [basics, checking] = payload["modules"]

      assert Enum.map(basics["lessons"], &{&1["key"], &1["position"]}) == [
               {"01-intro", 1},
               {"02-practice", 2}
             ]

      assert Enum.map(checking["lessons"], &{&1["key"], &1["position"]}) == [{"01-intro", 1}]
      assert Enum.map(basics["rules"], & &1["number"]) == [1, 2]
      assert Enum.map(checking["rules"], & &1["number"]) == [1]
    end

    test "option keys are unique in their item" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "    - key: b\n      label: Answers are always correct.",
        "    - key: a\n      label: Answers are always correct."
      )

      line = line_of!(pack, @items1, "- key: a", after: "label: Answers can vary.")
      assert errors(pack) == [{@items1, line, "duplicate key `a` in `options`"}]
    end
  end

  describe "references" do
    test "rules and reveals name rules and lessons of the same module, and lesson a lesson of the module" do
      pack = copy_pack!("minimal")
      replace!(pack, @items1, "rules: [2]", "rules: [2, 9]")
      replace!(pack, @items1, "reveals: [01-intro]", "reveals: [01-check]")
      replace!(pack, @items1, "lesson: 02-practice", "lesson: 03-missing")

      assert errors(pack) == [
               {@items1, line_of!(pack, @items1, "reveals: [01-check]"),
                "unknown lesson `01-check` of this module in `reveals`"},
               {@items1, line_of!(pack, @items1, "lesson: 03-missing"),
                "unknown lesson `03-missing` of this module in `lesson`"},
               {@items1, line_of!(pack, @items1, "rules: [2, 9]"),
                "unknown rule `9` of this module in `rules`"}
             ]
    end

    test "rules and lesson of an item resolve in its own module only, in both alignment modes" do
      in_both_modes(fn pack ->
        # Rule 2 and the lesson 01-intro exist in module 1 only.
        replace!(pack, @items2, "  lesson: 01-check\n", "  lesson: 01-intro\n")
        replace!(pack, @items2, "  rules: [1]\n", "  rules: [1, 2]\n")

        assert %{errors: errors, warnings: [], payload: nil} = run!(pack)

        assert Enum.map(errors, &{&1.file, &1.line, &1.message}) == [
                 {@items2, 3, "unknown lesson `01-intro` of this module in `lesson`"},
                 {@items2, 9, "unknown rule `2` of this module in `rules`"}
               ]
      end)
    end

    test "both forms of a glossary reference resolve in a lesson block and in a YAML field" do
      pack = copy_pack!("minimal")
      replace!(pack, @practice, "A prompt names task", "A [[term:prompt]] names task")

      replace!(
        pack,
        @practice,
        "how assistant use is made visible",
        "how [[term:assistant]] use is made visible"
      )

      replace!(
        pack,
        @objectives1,
        "Learners can build a prompt from",
        "Learners can build a [[term:prompt|prompt]] from"
      )

      replace!(
        pack,
        @rules1,
        "Check every generated statement",
        "Check every [[term:assistant|assistant]] statement"
      )

      assert errors(pack) == [
               {@practice, 6, "unknown glossary term `prompt` in `[[term:prompt]]`"},
               {@objectives1, 9, "unknown glossary term `prompt` in `[[term:prompt|prompt]]`"}
             ]
    end

    test "every cite names a source" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @rules1,
        ~s(cite: ["fictional-guide#Section 1"]),
        ~s(cite: ["other-guide#Section 1"])
      )

      replace!(
        pack,
        @items1,
        ~s(cite: ["fictional-guide#Section 1"]),
        ~s(cite: ["fictional-guide#Section 1", "x-guide#2"])
      )

      replace!(
        pack,
        @intro,
        ~s(cite="fictional-guide#Section 2"),
        ~s(cite="missing-guide#Section 2")
      )

      assert errors(pack) == [
               {@items1, line_of!(pack, @items1, "x-guide#2"),
                "unknown source `x-guide` in `cite`"},
               {@intro, 14, "unknown source `missing-guide` in `cite`"},
               {@rules1, 4, "unknown source `other-guide` in `cite`"}
             ]
    end

    test "a cite entry has the form source-key#locator" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @rules1,
        ~s(cite: ["fictional-guide#Section 1"]),
        ~s(cite: ["fictional-guide"])
      )

      assert errors(pack) == [
               {@rules1, 4,
                "`cite` entry `fictional-guide` does not have the form `source-key#locator`"}
             ]
    end

    test "every glossary reference in Markdown and YAML names a glossary slug" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @intro,
        "[[term:assistant|writing assistant]]",
        "[[term:model|writing assistant]]"
      )

      replace!(
        pack,
        @items1,
        "What does a [[term:assistant]] do?",
        "What does a [[term:helper]] do?"
      )

      replace!(
        pack,
        "glossary.yaml",
        "drafts text from a prompt.",
        "drafts text from a [[term:assistant|]] prompt [[term:x"
      )

      assert errors(pack) == [
               {"glossary.yaml", 3, "empty label in `[[term:assistant|]]`"},
               {"glossary.yaml", 3, "malformed glossary reference `[[term:`"},
               {@items1, line_of!(pack, @items1, "[[term:helper]]"),
                "unknown glossary term `helper` in `[[term:helper]]`"},
               {@intro, 6, "unknown glossary term `model` in `[[term:model|writing assistant]]`"}
             ]
    end

    test "a station module names a module" do
      pack = copy_pack!("minimal")
      replace!(pack, "stations.yaml", "  module: 2", "  module: 3")
      assert errors(pack) == [{"stations.yaml", 14, "unknown module `3` in `module`"}]
    end

    test "assessment items name items of the same module" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @assessment1,
        "items: [m1-exam-1, m1-exam-2]",
        "items: [m1-exam-1, m2-drill]"
      )

      assert errors(pack) == [
               {@assessment1, 7, "unknown item `m2-drill` of this module in `items`"},
               {@items1, line_of!(pack, @items1, "key: m1-exam-2"),
                "the item `m1-exam-2` names no `lesson`, and no assessment lists it"}
             ]
    end

    test "requirement targets name a module, an exam, a format whose attendance counts and a qualification" do
      pack = copy_pack!("minimal")
      replace!(pack, "qualifications.yaml", "      target: 1", "      target: 7")
      replace!(pack, "qualifications.yaml", "      target: basics", "      target: missing")
      replace!(pack, "qualifications.yaml", "      target: workshop", "      target: handbook")
      replace!(pack, "qualifications.yaml", "      target: m1-exam", "      target: m1-missing")

      assert errors(pack) == [
               {"qualifications.yaml", 13, "unknown module `7` in `target`"},
               {"qualifications.yaml", 15, "unknown assessment `m1-missing` in `target`"},
               {"qualifications.yaml", 28, "unknown qualification `missing` in `target`"},
               {"qualifications.yaml", 30,
                "the format `handbook` in `target` has `attendance_counts: false`"}
             ]
    end

    test "an attendance target names a format of the pack" do
      pack = copy_pack!("minimal")
      replace!(pack, "qualifications.yaml", "      target: workshop", "      target: seminar")

      assert errors(pack) == [
               {"qualifications.yaml", 30, "unknown format `seminar` in `target`"}
             ]
    end

    test "a module_completed target is a module number" do
      pack = copy_pack!("minimal")
      replace!(pack, "qualifications.yaml", "      target: 1", ~s(      target: "1"))

      assert errors(pack) == [
               {"qualifications.yaml", 13,
                "the `target` of a `module_completed` requirement must be a module number"}
             ]
    end

    test "an assessment_passed target names an exam" do
      pack = copy_pack!("minimal")
      replace!(pack, @assessment1, "kind: exam", "kind: practice")

      assert errors(pack) == [
               {"qualifications.yaml", 15, "the assessment `m1-exam` in `target` is no exam"}
             ]
    end

    test "qualification_held requirements form no cycle" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "qualifications.yaml",
        "      target: usage-policy",
        "      target: usage-policy\n    - kind: qualification_held\n      target: workshop"
      )

      assert errors(pack) == [
               {"qualifications.yaml", 19,
                "the `qualification_held` requirements of `basics` and `workshop` form a cycle"},
               {"qualifications.yaml", 30,
                "the `qualification_held` requirements of `workshop` and `basics` form a cycle"}
             ]
    end

    test "qualification_held requirements form no cycle over three qualifications" do
      pack = copy_pack!("minimal")

      write!(pack, "qualifications.yaml", """
      #{read!(pack, "qualifications.yaml")}- code: coach
        title: Coach
        audience: Workshop graduates.
        unlocks:
          - Train colleagues
        add_on: true
        validity_kind: none
        phases: [anchor]
        requirements:
          - kind: qualification_held
            target: workshop
      """)

      # coach holds workshop, which holds basics: a chain without a cycle.
      assert errors(pack) == []

      replace!(
        pack,
        "qualifications.yaml",
        "      target: usage-policy",
        "      target: usage-policy\n    - kind: qualification_held\n      target: coach"
      )

      assert errors(pack) == [
               {"qualifications.yaml", line_of!(pack, "qualifications.yaml", "target: coach"),
                "the `qualification_held` requirements of `basics` and `coach` form a cycle"},
               {"qualifications.yaml", line_of!(pack, "qualifications.yaml", "target: basics"),
                "the `qualification_held` requirements of `workshop` and `basics` form a cycle"},
               {"qualifications.yaml",
                line_of!(pack, "qualifications.yaml", "target: workshop", after: "code: coach"),
                "the `qualification_held` requirements of `coach` and `workshop` form a cycle"}
             ]
    end

    test "a qualification that holds itself forms a cycle" do
      pack = copy_pack!("minimal")
      replace!(pack, "qualifications.yaml", "      target: basics", "      target: workshop")

      assert errors(pack) == [
               {"qualifications.yaml", 28,
                "the `qualification_held` requirements of `workshop` and `workshop` form a cycle"}
             ]
    end
  end

  describe "objective references, each an error in both alignment modes" do
    test "an item that names an unknown objective key" do
      in_both_modes(fn pack ->
        replace!(
          pack,
          @items1,
          "objectives: [m1-method-build-prompt]",
          "objectives: [m1-method-missing]"
        )

        assert %{errors: errors, warnings: []} = run!(pack)

        assert Enum.map(errors, &{&1.file, &1.line, &1.message}) == [
                 {@items1, line_of!(pack, @items1, "[m1-method-missing]"),
                  "unknown objective `m1-method-missing` in `objectives`"}
               ]
      end)
    end

    test "a format that names an unknown objective key" do
      in_both_modes(fn pack ->
        replace!(pack, "formats.yaml", "m1-social-agree-team]", "m9-unknown]")

        assert errors(pack) == [
                 {"formats.yaml", 6, "unknown objective `m9-unknown` in `objectives`"}
               ]
      end)
    end

    test "a taught_in entry with a lesson of another module" do
      in_both_modes(fn pack ->
        replace!(pack, @objectives1, "taught_in: [01-intro]", "taught_in: [01-check]")

        assert errors(pack) == [
                 {@objectives1, line_of!(pack, @objectives1, "[01-check]"),
                  "unknown lesson `01-check` of this module in `taught_in`"}
               ]
      end)
    end

    test "a domain outside the module's domains" do
      in_both_modes(fn pack ->
        replace!(pack, @objectives1, "domain: drafting", "domain: research")

        assert errors(pack) == [
                 {@objectives1, line_of!(pack, @objectives1, "domain: research"),
                  "`domain` `research` is not one of the module's `domains`"}
               ]
      end)
    end

    test "an objective key used in two modules" do
      in_both_modes(fn pack ->
        replace!(
          pack,
          @objectives2,
          "key: m2-method-release-check",
          "key: m1-method-build-prompt"
        )

        replace!(
          pack,
          @items2,
          "objectives: [m2-method-release-check]",
          "objectives: [m1-method-build-prompt]"
        )

        first = line_of!(pack, @objectives1, "key: m1-method-build-prompt")

        assert errors(pack) == [
                 {@objectives2, line_of!(pack, @objectives2, "key: m1-method-build-prompt"),
                  "duplicate objective key `m1-method-build-prompt`, first used in `#{@objectives1}` at line #{first}"}
               ]
      end)
    end

    test "an item that names an objective of another module passes" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items2,
        "objectives: [m2-method-release-check]",
        "objectives: [m2-method-release-check, m1-method-build-prompt]"
      )

      assert %{errors: [], warnings: []} = run!(pack)
    end
  end

  describe "areas_elsewhere" do
    test "an unknown area key" do
      pack = copy_pack!("minimal")

      write!(
        pack,
        @module2,
        read!(pack, @module2) <> "  teamwork:\n    where: format:workshop\n    reason: Teams.\n"
      )

      assert errors(pack) == [
               {@module2, 14, "unknown competence area `teamwork` in `areas_elsewhere`"}
             ]
    end

    test "an empty reason" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @module2,
        "    reason: The workshop practises judging which tasks an assistant may support.",
        ~s(    reason: " ")
      )

      assert errors(pack) == [{@module2, 10, "`reason` must not be empty"}]
    end

    test "a where of another form" do
      pack = copy_pack!("minimal")
      replace!(pack, @module2, "where: format:workshop", "where: workshop")

      assert errors(pack) == [
               {@module2, 9,
                "`where` must have the form `format:<format key>` or `module:<module number>`"}
             ]
    end

    test "module: with the number 0 or a leading zero is a where of another form" do
      for where <- ["module:0", "module:01"] do
        pack = copy_pack!("minimal")
        replace!(pack, @module2, "where: module:1", "where: #{where}")

        assert errors(pack) == [
                 {@module2, 12,
                  "`where` must have the form `format:<format key>` or `module:<module number>`"}
               ]
      end
    end

    test "a where with a trailing newline is a where of another form" do
      for {from, to, line} <- [
            {"where: module:1", ~s(where: "module:1\\n"), 12},
            {"where: module:1", "where: |\n      module:1", 12},
            {"where: format:workshop", ~s(where: "format:workshop\\n"), 9}
          ] do
        pack = copy_pack!("minimal")
        replace!(pack, @module2, from, to)

        assert errors(pack) == [
                 {@module2, line,
                  "`where` must have the form `format:<format key>` or `module:<module number>`"}
               ]
      end
    end

    test "format: with an unknown format key" do
      pack = copy_pack!("minimal")
      replace!(pack, @module2, "where: format:workshop", "where: format:seminar")
      assert errors(pack) == [{@module2, 9, "unknown format `seminar` in `where`"}]
    end

    test "module: with an unknown number" do
      pack = copy_pack!("minimal")
      replace!(pack, @module2, "where: module:1", "where: module:5")
      assert errors(pack) == [{@module2, 12, "unknown module `5` in `where`"}]
    end

    test "module: with the module's own number" do
      pack = copy_pack!("minimal")
      replace!(pack, @module2, "where: module:1", "where: module:2")
      assert errors(pack) == [{@module2, 12, "`where` names the module's own number `2`"}]
    end
  end

  describe "placeholder keys and policy targets" do
    test "a placeholder key matches the key format" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @intro,
        ":::placeholder{key=usage-policy}",
        ~s(:::placeholder{key="Usage Policy"})
      )

      assert errors(pack) == [
               {@intro, 18,
                "`placeholder_key` value `Usage Policy` does not match the key format `^[a-z0-9][a-z0-9-]*$`"}
             ]
    end

    test "placeholder keys and policy_acknowledged targets in the key format pass without a policy to resolve" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @intro,
        ":::placeholder{key=usage-policy}",
        ":::placeholder{key=input-rules}"
      )

      replace!(pack, "qualifications.yaml", "target: usage-policy", "target: any-other-policy")

      assert %{errors: [], warnings: [], payload: payload} = run!(pack)

      assert %{"kind" => "policy_acknowledged", "target" => "any-other-policy"} in hd(
               payload["qualifications"]
             )["requirements"]

      [basics | _] = payload["modules"]
      intro = Enum.find(basics["lessons"], &(&1["key"] == "01-intro"))
      assert List.last(intro["blocks"])["placeholder_key"] == "input-rules"
    end

    test "a blank policy_acknowledged target is an error and no crash" do
      for blank <- [~S(""), ~S(" "), ~s("\u00A0")] do
        pack = copy_pack!("minimal")
        replace!(pack, "qualifications.yaml", "target: usage-policy", "target: " <> blank)

        assert errors(pack) == [
                 {"qualifications.yaml", 17,
                  "the `target` of a `policy_acknowledged` requirement must be a string in the key format"}
               ]
      end
    end

    test "two equal requirements with a map or a list target give the target errors and no crash" do
      for target <- ["{key: usage-policy}", "[-1]"] do
        pack = copy_pack!("minimal")

        replace!(
          pack,
          "qualifications.yaml",
          "    - kind: policy_acknowledged\n      target: usage-policy",
          "    - kind: policy_acknowledged\n      target: #{target}\n" <>
            "    - kind: policy_acknowledged\n      target: #{target}"
        )

        message =
          "the `target` of a `policy_acknowledged` requirement must be a string in the key format"

        assert errors(pack) == [
                 {"qualifications.yaml", 17, message},
                 {"qualifications.yaml", 19, message}
               ]
      end
    end

    test "a blank target of the other requirement kinds is an error and no crash" do
      for target <- ["target: m1-exam", "target: basics", "target: workshop"] do
        pack = copy_pack!("minimal")
        replace!(pack, "qualifications.yaml", target, ~S(target: ""))
        assert [{"qualifications.yaml", _line, _message}] = errors(pack)
      end
    end

    test "a policy_acknowledged target matches the key format" do
      pack = copy_pack!("minimal")
      replace!(pack, "qualifications.yaml", "target: usage-policy", "target: Usage Policy")

      assert errors(pack) == [
               {"qualifications.yaml", 17,
                "the `target` of a `policy_acknowledged` requirement must be a string in the key format"}
             ]
    end
  end

  describe "item kinds" do
    test "a single_choice item has exactly one correct option" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "      label: It looks up facts.\n      correct: false",
        "      label: It looks up facts.\n      correct: true"
      )

      line = line_of!(pack, @items1, "options:")

      assert errors(pack) == [
               {@items1, line, "a `single_choice` item has exactly one correct option, found 2"}
             ]
    end

    test "a choice item has at least two options" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "    - key: b\n      label: Images\n      correct: false\n      feedback: No.\n",
        ""
      )

      line = line_of!(pack, @items1, "options:", after: "key: m1-exam-1")

      assert errors(pack) == [
               {@items1, line, "a `single_choice` item needs at least two options"}
             ]
    end

    test "a single_choice item without a correct option" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "      label: Text\n      correct: true",
        "      label: Text\n      correct: false"
      )

      line = line_of!(pack, @items1, "options:", after: "key: m1-exam-1")

      assert errors(pack) == [
               {@items1, line, "a `single_choice` item has exactly one correct option, found 0"}
             ]
    end

    test "a multiple_choice item has at least two options" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "    - key: b\n      label: Answers are always correct.\n      correct: false\n      feedback: No.\n",
        ""
      )

      line = line_of!(pack, @items1, "options:", after: "key: m1-multi")

      assert errors(pack) == [
               {@items1, line, "a `multiple_choice` item needs at least two options"}
             ]
    end

    test "a poll has at least two options" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "    - key: rarely\n      label: Rarely\n      correct: false\n      feedback: Thanks.\n",
        ""
      )

      line = line_of!(pack, @items1, "options:", after: "key: m1-poll")
      assert errors(pack) == [{@items1, line, "a `poll` item needs at least two options"}]
    end

    test "a slot of a slot_builder item has at least two options" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "          - key: something\n            label: Do something\n            correct: false\n            feedback: Too vague.\n",
        ""
      )

      line = line_of!(pack, @items1, "options:", after: "key: task")
      assert errors(pack) == [{@items1, line, "a slot needs at least two options"}]
    end

    test "a multiple_choice item has at least one correct option" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "      label: Answers can vary.\n      correct: true",
        "      label: Answers can vary.\n      correct: false"
      )

      line = line_of!(pack, @items1, "options:", after: "key: m1-multi")

      assert errors(pack) == [
               {@items1, line, "a `multiple_choice` item has at least one correct option"}
             ]
    end

    test "a poll has no correct option" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "      label: Often\n      correct: false",
        "      label: Often\n      correct: true"
      )

      line = line_of!(pack, @items1, "options:", after: "key: m1-poll")
      assert errors(pack) == [{@items1, line, "a `poll` item has no correct option"}]
    end

    test "every slot of a slot_builder item has at least two options and a correct one" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items1,
        "            label: Write a summary\n            correct: true",
        "            label: Write a summary\n            correct: false"
      )

      line = line_of!(pack, @items1, "options:", after: "key: task")
      assert errors(pack) == [{@items1, line, "a slot needs at least one correct option"}]
    end

    test "a classification item maps every case to a known category" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items2,
        "      number: check\n      greeting: fine",
        "      greeting: wrong\n      other: fine"
      )

      expected = line_of!(pack, @items2, "expected:")

      assert errors(pack) == [
               {@items2, expected, "`expected` maps no category for the case `number`"},
               {@items2, expected + 1,
                "`expected` maps the case `greeting` to an unknown category"},
               {@items2, expected + 2, "`expected` names the unknown case `other`"}
             ]
    end

    test "a checklist_drill item has at least one required check" do
      pack = copy_pack!("minimal")
      replace!(pack, @items2, "required: true", "required: false")

      assert errors(pack) == [
               {@items2, line_of!(pack, @items2, "checks:"),
                "a `checklist_drill` item needs at least one required check"}
             ]
    end

    test "options and config follow the kind" do
      pack = copy_pack!("minimal")
      replace!(pack, @items2, "  kind: checklist_drill", "  kind: poll")
      replace!(pack, @items1, "  kind: slot_builder", "  kind: classification")

      config = line_of!(pack, @items1, "config:")

      assert errors(pack) == [
               {@items1, config, "missing field `cases`"},
               {@items1, config, "missing field `categories`"},
               {@items1, config, "missing field `expected`"},
               {@items1, config + 1, "unknown field `slots`"},
               {@items2, line_of!(pack, @items2, "key: m2-drill"),
                "a `poll` item needs at least two options"},
               {@items2, line_of!(pack, @items2, "config:", after: "key: m2-drill"),
                "`config` is not allowed for kind `poll`"}
             ]
    end

    test "a config kind needs config" do
      pack = copy_pack!("minimal")

      update_yaml!(pack, @items2, fn [classify, drill] ->
        [classify, Map.delete(drill, "config")]
      end)

      # The entry starts at its first key; write_yaml! sorts the keys.
      assert errors(pack) == [
               {@items2, line_of!(pack, @items2, ~s(- "core"), after: ~s("key": "m2-classify")),
                "a `checklist_drill` item needs `config`"}
             ]
    end
  end

  describe "items and assessments" do
    test "every item names a lesson or is listed by an assessment" do
      pack = copy_pack!("minimal")
      replace!(pack, @items1, "  lesson: 01-intro\n  stem: How often", "  stem: How often")

      assert errors(pack) == [
               {@items1, line_of!(pack, @items1, "key: m1-poll"),
                "the item `m1-poll` names no `lesson`, and no assessment lists it"}
             ]
    end

    test "an item listed by an exam names no lesson" do
      pack = copy_pack!("minimal")
      replace!(pack, @items1, "- key: m1-exam-1\n", "- key: m1-exam-1\n  lesson: 01-intro\n")

      assert errors(pack) == [
               {@items1, line_of!(pack, @items1, "lesson: 01-intro", after: "key: m1-exam-1"),
                "the item `m1-exam-1` of the exam `m1-exam` must not name a `lesson`"}
             ]
    end

    test "an item without a lesson passes when a practice assessment lists it" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @items2,
        "  lesson: 01-check\n  stem: Release the text.",
        "  stem: Release the text."
      )

      write!(pack, "modules/02-checking/assessment.yaml", """
      - key: m2-practice
        title: Practice set
        kind: practice
        counts_for_credential: false
        max_wrong: 0
        core_required: false
        items: [m2-classify, m2-drill]
      """)

      assert %{errors: [], warnings: [], payload: %{"modules" => [_basics, checking]}} =
               run!(pack)

      assert Enum.map(checking["items"], &{&1["key"], &1["lesson"]}) == [
               {"m2-classify", "01-check"},
               {"m2-drill", nil}
             ]
    end

    test "an exam has at least one item" do
      pack = copy_pack!("minimal")
      replace!(pack, @assessment1, "items: [m1-exam-1, m1-exam-2]", "items: []")
      assert errors(pack) == [{@assessment1, 7, "`items` needs at least one item"}]
    end

    test "an exam allows at most its number of items minus one wrong answers" do
      pack = copy_pack!("minimal")
      replace!(pack, @assessment1, "max_wrong: 1", "max_wrong: 2")

      assert errors(pack) == [
               {@assessment1, 5, "`max_wrong` of an exam with 2 items must be between 0 and 1"}
             ]
    end

    test "an exam has a max_wrong of at least 0" do
      pack = copy_pack!("minimal")
      replace!(pack, @assessment1, "max_wrong: 1", "max_wrong: -1")
      assert errors(pack) == [{@assessment1, 5, "`max_wrong` must be at least 0"}]
    end

    test "an exam with core_required has a core item" do
      pack = copy_pack!("minimal")
      replace!(pack, @items1, "  core: true", "  core: false")

      assert errors(pack) == [
               {@assessment1, 6, "the exam `m1-exam` has `core_required: true` and no core item"}
             ]
    end
  end

  describe "sources and quotes" do
    test "every source has edition_date and retrieved_on as dates" do
      pack = copy_pack!("minimal")
      replace!(pack, "sources.yaml", ~s(  edition_date: "2026-01-15"\n), "")
      replace!(pack, "sources.yaml", "2026-05-30", "2026-13-01")

      assert errors(pack) == [
               {"sources.yaml", 1, "missing field `edition_date`"},
               {"sources.yaml", 5,
                "`retrieved_on` must be a date in the form `YYYY-MM-DD`, got `2026-13-01`"}
             ]
    end

    test "every source has retrieved_on and an edition_date in ISO 8601 form" do
      pack = copy_pack!("minimal")
      replace!(pack, "sources.yaml", ~s(  retrieved_on: "2026-05-30"\n), "")

      replace!(
        pack,
        "sources.yaml",
        ~s(edition_date: "2026-01-15"),
        ~s(edition_date: "15.01.2026")
      )

      assert errors(pack) == [
               {"sources.yaml", 1, "missing field `retrieved_on`"},
               {"sources.yaml", 5,
                "`edition_date` must be a date in the form `YYYY-MM-DD`, got `15.01.2026`"}
             ]
    end

    test "a source url is an absolute http or https URL" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "sources.yaml",
        "url: https://example.org/fictional-guide",
        "url: javascript:alert(1)"
      )

      assert errors(pack) == [
               {"sources.yaml", 4, "`url` must be an absolute `http` or `https` URL"}
             ]
    end

    test "every quote block cites a source" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @intro,
        ~s(:::quote{provenance=sourced cite="fictional-guide#Section 2"}),
        ":::quote{provenance=invented}"
      )

      assert errors(pack) == [{@intro, 14, "a `quote` block cites at least one source"}]
    end
  end

  describe "validity" do
    test "validity_kind months needs validity_months above 0" do
      pack = copy_pack!("minimal")
      replace!(pack, "qualifications.yaml", "validity_months: 12", "validity_months: 0")

      assert errors(pack) == [
               {"qualifications.yaml", 8,
                "`validity_kind: months` needs `validity_months` above 0"}
             ]

      replace!(pack, "qualifications.yaml", "  validity_months: 0\n", "")

      assert errors(pack) == [
               {"qualifications.yaml", 1,
                "`validity_kind: months` needs `validity_months` above 0"}
             ]
    end

    test "months and event need a refresher_mode, and none takes neither validity_months nor refresher_mode" do
      pack = copy_pack!("minimal")
      replace!(pack, "qualifications.yaml", "  refresher_mode: update_unit\n", "")

      replace!(
        pack,
        "qualifications.yaml",
        "validity_kind: none",
        "validity_kind: none\n  validity_months: 6\n  refresher_mode: full_run"
      )

      assert errors(pack) == [
               {"qualifications.yaml", 1, "`validity_kind: months` needs a `refresher_mode`"},
               {"qualifications.yaml", 24,
                "`validity_months` is allowed with `validity_kind: months` only"},
               {"qualifications.yaml", 25,
                "`refresher_mode` is allowed with `validity_kind` `months` or `event` only"}
             ]

      pack = copy_pack!("minimal")
      replace!(pack, "qualifications.yaml", "validity_kind: none", "validity_kind: event")

      assert errors(pack) == [
               {"qualifications.yaml", 18, "`validity_kind: event` needs a `refresher_mode`"}
             ]
    end

    test "update_unit needs a module with refresher_unit true" do
      pack = copy_pack!("minimal")
      replace!(pack, @module2, "refresher_unit: true", "refresher_unit: false")

      assert errors(pack) == [
               {"qualifications.yaml", 9,
                "`refresher_mode: update_unit` needs a module with `refresher_unit: true`"}
             ]
    end
  end

  describe "stations" do
    test "the pack has a self_assessment station when segments.yaml has entries" do
      pack = copy_pack!("minimal")
      update_yaml!(pack, "stations.yaml", &tl/1)

      assert errors(pack) == [
               {"stations.yaml", 1,
                "the pack needs a `self_assessment` station, because `segments.yaml` has entries"}
             ]
    end

    test "the pack has one self_assessment station only" do
      pack = copy_pack!("minimal")

      write!(
        pack,
        "stations.yaml",
        read!(pack, "stations.yaml") <>
          "- kind: self_assessment\n  title: Again\n  config:\n    question: Again?\n"
      )

      assert errors(pack) == [
               {"stations.yaml", 25, "the pack has one `self_assessment` station only"}
             ]
    end

    test "a self_assessment station needs entries in segments.yaml" do
      pack = copy_pack!("minimal")
      remove!(pack, "segments.yaml")

      assert errors(pack) == [
               {"stations.yaml", 1,
                "a `self_assessment` station needs entries in `segments.yaml`"}
             ]
    end

    test "the pack has one feedback station when feedback.yaml exists, and none without it" do
      pack = copy_pack!("minimal")
      replace!(pack, "stations.yaml", "- kind: feedback\n  title: Feedback\n", "")

      assert errors(pack) == [
               {"stations.yaml", 1,
                "the pack needs a `feedback` station, because `feedback.yaml` exists"}
             ]

      pack = copy_pack!("minimal")
      remove!(pack, "feedback.yaml")
      assert errors(pack) == [{"stations.yaml", 23, "a `feedback` station needs `feedback.yaml`"}]
    end

    test "the pack has one feedback station only" do
      pack = copy_pack!("minimal")

      write!(
        pack,
        "stations.yaml",
        read!(pack, "stations.yaml") <> "- kind: feedback\n  title: Feedback again\n"
      )

      assert errors(pack) == [{"stations.yaml", 25, "the pack has one `feedback` station only"}]
    end

    test "a pack without segments and feedback passes without self_assessment and feedback stations" do
      pack = copy_pack!("minimal")
      remove!(pack, "segments.yaml")
      remove!(pack, "feedback.yaml")

      update_yaml!(pack, "stations.yaml", fn stations ->
        Enum.reject(stations, &(&1["kind"] in ["self_assessment", "feedback"]))
      end)

      assert %{errors: [], warnings: [], payload: payload} = run!(pack)

      assert Enum.map(payload["stations"], & &1["kind"]) ==
               ~w(overview module module credential companion_formats)
    end

    test "station configs hold their texts and JSON values only" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "stations.yaml",
        "    question: How often do you use a writing assistant?",
        "    prompt: How often?"
      )

      replace!(
        pack,
        "stations.yaml",
        "  title: Feedback",
        "  title: Feedback\n  config:\n    intro: Own intro."
      )

      replace!(
        pack,
        "stations.yaml",
        "    intro: Two short modules.",
        "    intro: Two short modules.\n    ratio: .nan"
      )

      replace!(pack, "stations.yaml", "  module: 1", "  module: 1\n  config: {}")

      replace!(
        pack,
        "stations.yaml",
        "- kind: credential\n  title: Credential",
        "- kind: credential\n  title: Credential\n  module: 1"
      )

      assert errors(pack) == [
               {"stations.yaml", 3,
                "a `self_assessment` station needs the text `question` in `config`"},
               {"stations.yaml", 9, "`config` holds a value that is not a JSON value"},
               {"stations.yaml", 19, "`module` is allowed on stations of kind `module` only"},
               {"stations.yaml", 29, "the `feedback` station takes `intro` from `feedback.yaml`"}
             ]
    end

    test "a station config holds no float" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "stations.yaml",
        "    intro: Two short modules.",
        "    intro: Two short modules.\n    weight: 1e3\n    parts: [1, 0.5]\n    count: 3"
      )

      message =
        "`config` holds a number with a fraction or an exponent; use an integer or a quoted string"

      assert errors(pack) == [{"stations.yaml", 9, message}, {"stations.yaml", 10, message}]
    end

    test "feedback questions follow their kind" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "feedback.yaml",
        "    label: How do you rate the course?",
        "    label: How do you rate the course?\n    options:\n      - key: a\n        label: A"
      )

      assert errors(pack) == [{"feedback.yaml", 14, "a `scale` question has no options"}]
    end
  end

  describe "storage bounds" do
    test "a station config holds integers within the exact range of a JavaScript number" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        "stations.yaml",
        "    intro: Two short modules.",
        "    intro: Two short modules.\n    limit: 9007199254740991\n    big: 9007199254740992\n    small: -9007199254740992"
      )

      message =
        "`config` holds an integer beyond 9007199254740991 or below -9007199254740991"

      assert errors(pack) == [{"stations.yaml", 10, message}, {"stations.yaml", 11, message}]
    end

    test "strings that land in a varchar(255) column have at most 255 characters" do
      pack = copy_pack!("minimal")
      # 128 letters with a combining accent: 128 graphemes, 256 code points.
      accented = String.duplicate("e" <> <<0x0301::utf8>>, 128)
      replace!(pack, "pack.yaml", "title: Minimal pack (test fixture)", "title: #{accented}")
      replace!(pack, "pack.yaml", "version: 0.1.0", "version: 0.1.#{String.duplicate("1", 252)}")
      replace!(pack, @items1, "- key: m1-choice", "- key: m1-#{String.duplicate("k", 253)}")
      replace!(pack, @module1, "domains: [drafting]", "domains: [#{String.duplicate("d", 256)}]")

      replace!(
        pack,
        @rules1,
        "fictional-guide#Section 1",
        "fictional-guide##{String.duplicate("s", 256)}"
      )

      replace!(
        pack,
        "qualifications.yaml",
        "    - Draft internal notes with an assistant",
        "    - #{String.duplicate("u", 256)}"
      )

      replace!(
        pack,
        "sources.yaml",
        "url: https://example.org/fictional-guide",
        "url: https://example.org/#{String.duplicate("a", 236)}"
      )

      assert errors(pack) == [
               {@items1, 1, "`key` must have at most 255 characters"},
               {@module1, 5, "entries of `domains` must have at most 255 characters"},
               {@rules1, 4, "the locator of a `cite` entry must have at most 255 characters"},
               {"pack.yaml", 3, "`title` must have at most 255 characters"},
               {"pack.yaml", 6, "`version` must have at most 255 characters"},
               {"qualifications.yaml", 5,
                "entries of `unlocks` must have at most 255 characters"},
               {"sources.yaml", 4, "`url` must have at most 255 characters"}
             ]
    end

    test "integers that land in an integer column are at most 2147483647" do
      pack = copy_pack!("minimal")
      too_big = "2147483648"
      replace!(pack, @module1, "number: 1", "number: #{too_big}")
      replace!(pack, @intro, "position: 1", "position: #{too_big}")
      replace!(pack, @rules1, "- number: 1", "- number: #{too_big}")
      replace!(pack, @items1, "  rules: [1]", "  rules: [#{too_big}]")
      replace!(pack, @assessment1, "max_wrong: 1", "max_wrong: #{too_big}")
      replace!(pack, "stations.yaml", "module: 1", "module: #{too_big}")
      replace!(pack, "qualifications.yaml", "validity_months: 12", "validity_months: #{too_big}")
      replace!(pack, "qualifications.yaml", "target: 1", "target: #{too_big}")

      assert errors(pack) == [
               {@assessment1, 5, "`max_wrong` must be at most 2147483647"},
               {@items1, 9, "entries of `rules` must be at most 2147483647"},
               {@intro, 3, "`position` must be at most 2147483647"},
               {@module1, 1, "`number` must be at most 2147483647"},
               {@rules1, 1, "`number` must be at most 2147483647"},
               {"qualifications.yaml", 8, "`validity_months` must be at most 2147483647"},
               {"qualifications.yaml", 13, "`target` must be at most 2147483647"},
               {"stations.yaml", 11, "`module` must be at most 2147483647"}
             ]
    end

    test "values at the bounds pass" do
      pack = copy_pack!("minimal")
      # 127 letters with a combining accent and one plain letter: 255 code points.
      accented = String.duplicate("e" <> <<0x0301::utf8>>, 127) <> "e"
      replace!(pack, "pack.yaml", "key: minimal-pack", "key: #{String.duplicate("k", 255)}")
      replace!(pack, "pack.yaml", "title: Minimal pack (test fixture)", "title: #{accented}")
      replace!(pack, @module2, "number: 2", "number: 2147483647")
      replace!(pack, "stations.yaml", "module: 2", "module: 2147483647")
      replace!(pack, "qualifications.yaml", "validity_months: 12", "validity_months: 2147483647")

      replace!(
        pack,
        @rules1,
        "fictional-guide#Section 1",
        "fictional-guide##{String.duplicate("s", 255)}"
      )

      assert %{errors: [], warnings: [], payload: payload} = run!(pack)
      assert payload["title"] == accented
      assert [_, %{"number" => 2_147_483_647}] = payload["modules"]
    end
  end

  describe "the normalized payload" do
    test "holds every field, with nil, [] and %{} for absent values" do
      pack = copy_pack!("minimal")
      replace!(pack, "sources.yaml", "  url: https://example.org/fictional-guide\n", "")
      assert %{payload: payload} = run!(pack)

      assert payload["alignment"] == "strict"

      assert [%{"url" => nil, "edition_date" => "2026-01-15", "kind" => "other"}] =
               payload["sources"]

      assert [basics, checking] = payload["modules"]

      assert basics["areas_elsewhere"] == %{}

      assert checking["areas_elsewhere"] == %{
               "self" => %{
                 "where" => "format:workshop",
                 "reason" =>
                   "The workshop practises judging which tasks an assistant may support."
               },
               "social" => %{
                 "where" => "module:1",
                 "reason" =>
                   "Module 1 covers agreeing in a team how assistant use is made visible."
               }
             }

      assert Enum.map(checking["objectives"], & &1["domain"]) == [nil, nil]
      assert checking["domains"] == []
      assert checking["assessments"] == []

      items = Map.new(basics["items"], &{&1["key"], &1})
      assert items["m1-exam-1"]["lesson"] == nil
      assert items["m1-poll"]["objectives"] == []
      assert items["m1-choice"]["config"] == %{}
      assert items["m1-slots"]["options"] == []
      assert items["m1-multi"]["cite"] == []

      assert %{
               "slots" => [
                 %{"key" => "task", "options" => [%{"key" => "summary", "correct" => true} | _]}
               ]
             } =
               items["m1-slots"]["config"]

      [classify, drill] = checking["items"]
      assert classify["config"]["expected"] == %{"number" => "check", "greeting" => "fine"}

      assert drill["config"]["checks"] |> hd() |> Map.keys() |> Enum.sort() == [
               "key",
               "label",
               "required"
             ]
    end

    test "turns enums, dates and requirement targets into strings and sorts requirements by kind and target" do
      pack = copy_pack!("minimal")
      assert %{payload: payload} = run!(pack)

      [basics_q, workshop_q] = payload["qualifications"]
      assert basics_q["validity_kind"] == "months"
      assert basics_q["phases"] == ["orient", "understand", "apply"]

      assert basics_q["requirements"] == [
               %{"kind" => "assessment_passed", "target" => "m1-exam"},
               %{"kind" => "module_completed", "target" => "1"},
               %{"kind" => "policy_acknowledged", "target" => "usage-policy"}
             ]

      assert workshop_q["validity_months"] == nil
      assert workshop_q["refresher_mode"] == nil
    end

    test "places the feedback questions in the config of the feedback station" do
      pack = copy_pack!("minimal")
      assert %{payload: %{"stations" => stations}} = run!(pack)

      assert Enum.map(stations, &{&1["kind"], &1["module"]}) == [
               {"self_assessment", nil},
               {"overview", nil},
               {"module", 1},
               {"module", 2},
               {"credential", nil},
               {"companion_formats", nil},
               {"feedback", nil}
             ]

      assert %{"intro" => "Tell us what you think.", "questions" => [single, scale, free]} =
               List.last(stations)["config"]

      assert single["options"] == [
               %{"key" => "yes", "label" => "Yes"},
               %{"key" => "no", "label" => "No"}
             ]

      assert {scale["kind"], scale["options"]} == {"scale", []}
      assert {free["kind"], free["options"]} == {"free_text", []}

      assert hd(stations)["config"] == %{
               "question" => "How often do you use a writing assistant?"
             }
    end

    test "orders lessons by position and keeps blocks in file order" do
      pack = copy_pack!("minimal")
      replace!(pack, @intro, "position: 1", "position: 3")
      assert %{payload: %{"modules" => [basics, _]}} = run!(pack)

      assert Enum.map(basics["lessons"], &{&1["key"], &1["position"]}) == [
               {"02-practice", 2},
               {"01-intro", 3}
             ]

      assert Enum.map(List.last(basics["lessons"])["blocks"], & &1["kind"]) ==
               ~w(text explanation quote placeholder)

      [_, _, _, placeholder] = List.last(basics["lessons"])["blocks"]

      assert placeholder == %{
               "kind" => "placeholder",
               "body" => "Your organization adds its rules for inputs here.",
               "provenance" => "placeholder",
               "collapsed_on" => [],
               "placeholder_key" => "usage-policy",
               "cite" => []
             }

      callout = basics["lessons"] |> hd() |> Map.fetch!("blocks") |> List.last()
      assert callout["collapsed_on"] == ["short", "full"]
    end

    test "is equal for packs that list the sorted lists in another order" do
      pack = copy_pack!("minimal")
      reordered = copy_pack!("minimal")

      replace!(reordered, @items1, "rules: [2]", "rules: [2, 1]")
      replace!(pack, @items1, "rules: [2]", "rules: [1, 2]")

      replace!(
        reordered,
        "formats.yaml",
        "[m1-self-judge-tasks, m1-social-agree-team]",
        "[m1-social-agree-team, m1-self-judge-tasks]"
      )

      replace!(
        reordered,
        @intro,
        ~s(cite="fictional-guide#Section 2"),
        ~s(cite="fictional-guide#Section 2,fictional-guide#Section 1")
      )

      replace!(
        pack,
        @intro,
        ~s(cite="fictional-guide#Section 2"),
        ~s(cite="fictional-guide#Section 1,fictional-guide#Section 2")
      )

      update_yaml!(reordered, "qualifications.yaml", &Enum.reverse/1)

      update_yaml!(reordered, "qualifications.yaml", fn qualifications ->
        Enum.map(
          qualifications,
          &Map.update!(&1, "requirements", fn requirements -> Enum.reverse(requirements) end)
        )
      end)

      write!(
        pack,
        "glossary.yaml",
        read!(pack, "glossary.yaml") <> "- slug: zeta\n  label: Zeta\n  short_text: Last.\n"
      )

      write!(
        reordered,
        "glossary.yaml",
        "- slug: zeta\n  label: Zeta\n  short_text: Last.\n" <> read!(reordered, "glossary.yaml")
      )

      assert %{errors: [], payload: payload} = run!(pack)
      assert %{errors: [], payload: ^payload} = run!(reordered)
      assert Enum.map(payload["glossary"], & &1["slug"]) == ["assistant", "zeta"]
    end

    test "holds JSON values only" do
      pack = copy_pack!("minimal")
      assert %{payload: payload} = run!(pack)
      assert payload |> JSON.encode!() |> JSON.decode!() == payload
    end
  end

  describe "alignment_entries/2" do
    setup do
      pack = copy_pack!("minimal")
      assert {:ok, loaded} = Loader.load(pack)
      %{pack: pack, loaded: loaded}
    end

    test "places a finding on an objective or an item at the line of its entry", %{
      pack: pack,
      loaded: loaded
    } do
      findings = [
        %{
          check: 1,
          module: 2,
          file: "objectives.yaml",
          key: "m2-method-release-check",
          message: "no evidence"
        },
        %{check: 2, module: 1, file: "items.yaml", key: "m1-exam-2", message: "no objective"}
      ]

      assert Validator.alignment_entries(loaded, findings) == [
               %{
                 file: @objectives2,
                 line: line_of!(pack, @objectives2, "key: m2-method-release-check"),
                 message: "no evidence",
                 check: 1,
                 module: 2,
                 key: "m2-method-release-check"
               },
               %{
                 file: @items1,
                 line: line_of!(pack, @items1, "key: m1-exam-2"),
                 message: "no objective",
                 check: 2,
                 module: 1,
                 key: "m1-exam-2"
               }
             ]
    end

    test "places a finding on a module area at the area in areas_elsewhere, or at line 1", %{
      loaded: loaded
    } do
      findings = [
        %{
          check: 3,
          module: 2,
          file: "module.yaml",
          key: "social",
          message: "social is not covered"
        },
        %{check: 3, module: 1, file: "module.yaml", key: "self", message: "self is not covered"}
      ]

      assert [
               %{
                 file: @module2,
                 line: 11,
                 check: 3,
                 module: 2,
                 key: "social",
                 message: "social is not covered"
               },
               %{
                 file: @module1,
                 line: 1,
                 check: 3,
                 module: 1,
                 key: "self",
                 message: "self is not covered"
               }
             ] = Validator.alignment_entries(loaded, findings)
    end
  end

  describe "report bounds" do
    test "a file keeps its first 100 errors and a closing entry for the rest" do
      pack = copy_pack!("minimal")
      write!(pack, @items1, String.duplicate("- 1\n", 300))

      assert %{errors: errors, warnings: [], payload: nil} = run!(pack)
      assert length(errors) == 101

      assert Enum.take(errors, 100) ==
               Enum.map(1..100, &%{file: @items1, line: &1, message: "an entry must be a map"})

      assert List.last(errors) == %{
               file: @items1,
               line: 100,
               message: "and 200 further errors in this file",
               omitted: 200
             }
    end

    test "a text of many openings `[[term:` validates in linear time" do
      pack = copy_pack!("minimal")

      # About 460 KB; the scan of a pattern without bounds took longer than
      # 5 seconds for the first 280 KB alone.
      openings =
        String.duplicate("[[term:", 40_000) <> String.duplicate("[[term:a|", 20_000) <> "] ]"

      replace!(pack, @intro, "A [[term:assistant|writing assistant]] continues text.", openings)

      {micros, result} = :timer.tc(fn -> run!(pack) end)

      assert result.errors == [
               %{file: @intro, line: 6, message: "malformed glossary reference `[[term:`"}
             ]

      assert micros < 5_000_000
    end

    test "a slug of more than 255 characters or a label of more than 1,000 is malformed" do
      pack = copy_pack!("minimal")

      replace!(
        pack,
        @intro,
        "[[term:assistant|writing assistant]]",
        "[[term:assistant|#{String.duplicate("l", 1_000)}]] [[term:#{String.duplicate("s", 255)}]]"
      )

      assert errors(pack) == [
               {@intro, 6,
                "unknown glossary term `#{String.duplicate("s", 255)}` in " <>
                  "`[[term:#{String.duplicate("s", 255)}]]`"}
             ]

      replace!(pack, @intro, "[[term:assistant|", "[[term:assistant|l")
      replace!(pack, @intro, "[[term:s", "[[term:ss")

      assert errors(pack) == [{@intro, 6, "malformed glossary reference `[[term:`"}]
    end

    test "the bounds of a glossary reference count characters, not bytes" do
      pack = copy_pack!("minimal")
      label = String.duplicate("ä", 1_000)

      replace!(
        pack,
        @intro,
        "[[term:assistant|writing assistant]]",
        "[[term:assistant|#{label}]]"
      )

      assert errors(pack) == []

      replace!(pack, @intro, "[[term:assistant|", "[[term:assistant|ä")
      assert errors(pack) == [{@intro, 6, "malformed glossary reference `[[term:`"}]
    end

    test "a key and a glossary reference with a raw line break give messages of one line" do
      pack = copy_pack!("minimal")
      write!(pack, "pack.yaml", read!(pack, "pack.yaml") <> ~s("x\\ny": 1\n))

      assert errors(pack) == [{"pack.yaml", 7, "unknown field `x\\x0Ay`"}]

      pack = copy_pack!("minimal")
      replace!(pack, @intro, "[[term:assistant|writing assistant]]", "[[term:no-\nsuch]]")

      assert errors(pack) == [
               {@intro, 6, "unknown glossary term `no-\\x0Asuch` in `[[term:no-\\x0Asuch]]`"}
             ]
    end
  end
end
