defmodule Espalier.Workbench.Skeleton do
  @moduledoc """
  The empty pack of the workbench (task 0016a, step 5): a normalized map in
  the shape of `Espalier.Catalog.Pack.Normalizer.build/1` with one module,
  one lesson, the four learning objectives of the CORE areas and one item
  that provides evidence for all four. `Espalier.Interop.PackWriter.render/1`
  writes its six files, which pass `mix espalier.validate` and
  `mix espalier.alignment` with no error and no warning.

  The pack `title` is the name of the draft, and the pack `key` is
  `Espalier.Interop.PackWriter.slug/1` of the name, or `new-pack` when the
  slug is empty. The guide `docs/guides/pack-workbench.md` tells the author
  to replace the single item with evidence that fits each objective.
  """

  alias Espalier.Interop.PackWriter

  @lesson "01-first-lesson"

  @objectives [
    {"m1-subject", "subject", "Learners can name the subject of this module."},
    {"m1-method", "method", "Learners can name the method that this module practises."},
    {"m1-self", "self", "Learners can name what this module asks of their own work."},
    {"m1-social", "social", "Learners can name what this module asks of their work with others."}
  ]

  @doc "The normalized map of the empty pack named `name`."
  @spec payload(String.t()) :: map()
  def payload(name) when is_binary(name) do
    %{
      "schema" => 1,
      "key" => key(name),
      "title" => name,
      "locale" => "en",
      "license" => "CC0-1.0",
      "version" => "0.1.0",
      "alignment" => "strict",
      "sources" => [],
      "glossary" => [],
      "segments" => [],
      "stations" => stations(),
      "qualifications" => [],
      "formats" => [],
      "modules" => [first_module()]
    }
  end

  @doc "The pack key of the empty pack named `name`."
  @spec key(String.t()) :: String.t()
  def key(name) when is_binary(name) do
    case PackWriter.slug(name) do
      "" -> "new-pack"
      slug -> slug
    end
  end

  defp stations do
    [
      %{
        "kind" => "overview",
        "title" => "Overview",
        "module" => nil,
        "config" => %{"intro" => "Replace this introduction with the purpose of the pack."}
      },
      %{"kind" => "module", "title" => "First module", "module" => 1, "config" => %{}}
    ]
  end

  defp first_module do
    %{
      "number" => 1,
      "title" => "First module",
      "summary" => "Replace this summary with what learners do in the module.",
      "phases" => ["understand"],
      "domains" => [],
      "single_path" => false,
      "refresher_unit" => false,
      "areas_elsewhere" => %{},
      "lessons" => [lesson()],
      "objectives" => Enum.map(@objectives, &objective/1),
      "rules" => [],
      "items" => [item()],
      "assessments" => []
    }
  end

  defp lesson do
    %{
      "key" => @lesson,
      "title" => "First lesson",
      "position" => 1,
      "blocks" => [
        %{
          "kind" => "text",
          "body" => "Replace this text with the first lesson.",
          "provenance" => "invented",
          "collapsed_on" => [],
          "placeholder_key" => nil,
          "cite" => []
        }
      ]
    }
  end

  defp objective({key, area, statement}) do
    %{
      "key" => key,
      "statement" => statement,
      "area" => area,
      "depth" => "know",
      "phase" => "understand",
      "domain" => nil,
      "taught_in" => [@lesson]
    }
  end

  defp item do
    %{
      "key" => "m1-first-question",
      "kind" => "single_choice",
      "lesson" => @lesson,
      "stem" => "Replace this question with a question on the first lesson.",
      "core" => false,
      "phase" => "understand",
      "provenance" => "invented",
      "objectives" => @objectives |> Enum.map(&elem(&1, 0)) |> Enum.sort(),
      "rules" => [],
      "reveals" => [],
      "cite" => [],
      "options" => [
        option("a", "The correct answer", true),
        option("b", "A wrong answer", false)
      ],
      "config" => %{}
    }
  end

  defp option(key, label, correct) do
    %{
      "key" => key,
      "label" => label,
      "correct" => correct,
      "feedback" => "Replace this feedback."
    }
  end
end
