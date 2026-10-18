defmodule Espalier.Docs.PackModuledocsTest do
  @moduledoc """
  The `yaml` examples in the moduledocs of the content pack format modules
  are valid input for the changeset of their own module.

  A pack author copies these blocks into a pack file, so each block passes
  through the call that `Espalier.Catalog.Pack.Validator` makes for an entry
  of the file: `module.changeset(struct(module), data)`, where `data` is the
  parsed YAML with string keys. A YAML list holds one entry per element, and
  a mapping is one entry. The file-level checks across entries, such as
  unique keys, are outside this test.
  """
  use ExUnit.Case, async: true

  alias Espalier.Catalog.Pack.Schema.Cast

  @schema_prefix "Elixir.Espalier.Catalog.Pack.Schema."

  # The modules of the files of a pack, each of which shows at least one
  # example that an author puts into its file.
  @file_modules ~w(Pack Source GlossaryTerm Segment Feedback Station Qualification Format
                   PackModule Objective Rule Assessment Item)

  describe "the schema modules" do
    test "every file module shows at least one yaml example" do
      for name <- @file_modules do
        module = Module.concat(Espalier.Catalog.Pack.Schema, name)

        assert [_ | _] = yaml_blocks(module),
               "#{inspect(module)} has no yaml example in its moduledoc"
      end
    end

    test "every yaml block parses" do
      for module <- schema_modules(), {block, index} <- Enum.with_index(yaml_blocks(module), 1) do
        assert {:ok, _data} = YamlElixir.read_from_string(block),
               "#{inspect(module)}, yaml block #{index} does not parse:\n#{block}"
      end
    end

    test "every yaml block is valid input for the changeset of its module" do
      for module <- schema_modules(),
          {block, index} <- Enum.with_index(yaml_blocks(module), 1),
          entry <- entries(YamlElixir.read_from_string!(block)) do
        changeset = module.changeset(struct(module), entry)

        assert changeset.valid?,
               "#{inspect(module)}, yaml block #{index} is not valid input: " <>
                 "#{inspect(Enum.map(Cast.errors(changeset), &elem(&1, 1)))}\n#{block}"
      end
    end
  end

  describe "the pack module" do
    test "Espalier.Catalog.Pack has a moduledoc" do
      assert {:docs_v1, _anno, _lang, _format, %{"en" => doc}, _meta, _docs} =
               Code.fetch_docs(Espalier.Catalog.Pack)

      assert String.trim(doc) != ""
    end

    test "the yaml blocks of its moduledoc parse" do
      for {block, index} <- Enum.with_index(yaml_blocks(Espalier.Catalog.Pack), 1) do
        assert {:ok, _data} = YamlElixir.read_from_string(block),
               "Espalier.Catalog.Pack, yaml block #{index} does not parse:\n#{block}"
      end
    end

    test "the yaml blocks of Espalier.Catalog.Pack.Directives parse" do
      for {block, index} <- Enum.with_index(yaml_blocks(Espalier.Catalog.Pack.Directives), 1) do
        assert {:ok, _data} = YamlElixir.read_from_string(block),
               "Espalier.Catalog.Pack.Directives, yaml block #{index} does not parse:\n#{block}"
      end
    end
  end

  # Every module under Espalier.Catalog.Pack.Schema that exports changeset/2.
  defp schema_modules do
    {:ok, modules} = :application.get_key(:espalier, :modules)

    modules
    |> Enum.filter(fn module ->
      String.starts_with?(Atom.to_string(module), @schema_prefix) and
        Code.ensure_loaded?(module) and function_exported?(module, :changeset, 2)
    end)
    |> Enum.sort()
  end

  # A YAML list is cast element by element, a mapping as one entry.
  defp entries(data) when is_list(data), do: data
  defp entries(data), do: [data]

  defp yaml_blocks(module) do
    case Code.fetch_docs(module) do
      {:docs_v1, _anno, _lang, _format, %{"en" => doc}, _meta, _docs} ->
        ~r/^```yaml\n(.*?)^```$/ms
        |> Regex.scan(doc, capture: :all_but_first)
        |> Enum.map(fn [block] -> block end)

      _ ->
        []
    end
  end
end
