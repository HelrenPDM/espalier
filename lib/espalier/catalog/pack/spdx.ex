defmodule Espalier.Catalog.Pack.Spdx do
  @moduledoc """
  Checks the `license` of `pack.yaml` (task 0008, step 5) against the
  license expression grammar of the SPDX specification and the license and
  exception ids of the SPDX License List.

  `priv/spdx/license-ids.txt` and `priv/spdx/exception-ids.txt` hold the ids,
  deprecated ones included. `scripts/spdx-lists.sh` (`make spdx-lists`)
  writes them from the package `spdx-license-list-data` of the nixpkgs
  commit that `shell.nix` pins, and this module reads them at compile time,
  so a release needs no file at run time.

  The grammar, after the annex "SPDX license expressions" of the
  specification:

      expression      = and-expression *("OR" and-expression)
      and-expression  = with-expression *("AND" with-expression)
      with-expression = simple ["WITH" exception] / "(" expression ")"
      simple          = license-id ["+"] / license-ref
      license-ref     = ["DocumentRef-" idstring ":"] "LicenseRef-" idstring
      exception       = exception-id / ["DocumentRef-" idstring ":"] "AdditionRef-" idstring
      idstring        = 1*(ALPHA / DIGIT / "-" / ".")

  License ids and exception ids match without regard to case, as the
  specification asks. The operators `AND`, `OR` and `WITH` are written in
  capitals, and `+` follows a license id without a space.
  """

  @root Path.expand("../../../..", __DIR__)
  @license_file Path.join(@root, "priv/spdx/license-ids.txt")
  @exception_file Path.join(@root, "priv/spdx/exception-ids.txt")
  @external_resource @license_file
  @external_resource @exception_file

  read_ids = fn path ->
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.reject(&String.starts_with?(&1, "#"))
  end

  @list_version @license_file
                |> File.read!()
                |> then(&Regex.run(~r/SPDX License List (\S+)/, &1, capture: :all_but_first))
                |> hd()
  @license_ids @license_file |> read_ids.() |> MapSet.new(&String.downcase/1)
  @exception_ids @exception_file |> read_ids.() |> MapSet.new(&String.downcase/1)

  @syntax ["(", ")", "AND", "OR", "WITH"]
  @idstring "[A-Za-z0-9.-]+"
  @license_ref Regex.compile!("\\A(DocumentRef-#{@idstring}:)?LicenseRef-#{@idstring}\\z")
  @addition_ref Regex.compile!("\\A(DocumentRef-#{@idstring}:)?AdditionRef-#{@idstring}\\z")

  @doc "The version of the SPDX License List that the ids come from, for example `3.28.0`."
  @spec list_version() :: String.t()
  def list_version, do: @list_version

  @doc """
  True when `text` is a license expression of the grammar in the moduledoc
  whose ids are on the SPDX License List.
  """
  @spec expression?(String.t()) :: boolean()
  def expression?(text) when is_binary(text) do
    with true <- Regex.match?(~r/\A[ ()A-Za-z0-9.:+-]+\z/, text),
         tokens = Regex.scan(~r/[()]|[^ ()]+/, text) |> List.flatten(),
         {:ok, []} <- or_expression(tokens) do
      true
    else
      _ -> false
    end
  end

  defp or_expression(tokens) do
    with {:ok, rest} <- and_expression(tokens), do: continue(rest, "OR", &or_expression/1)
  end

  defp and_expression(tokens) do
    with {:ok, rest} <- with_expression(tokens), do: continue(rest, "AND", &and_expression/1)
  end

  defp continue([operator | rest], operator, next), do: next.(rest)
  defp continue(rest, _operator, _next), do: {:ok, rest}

  defp with_expression(["(" | rest]) do
    case or_expression(rest) do
      {:ok, [")" | rest]} -> {:ok, rest}
      _ -> :error
    end
  end

  defp with_expression([word, "WITH", exception | rest]) when word not in @syntax do
    if simple?(word) and exception?(exception), do: {:ok, rest}, else: :error
  end

  defp with_expression([word | rest]) when word not in @syntax do
    if simple?(word), do: {:ok, rest}, else: :error
  end

  defp with_expression(_tokens), do: :error

  defp simple?(word), do: license_id?(word) or Regex.match?(@license_ref, word) or or_later?(word)

  # A license id with `+`. The list holds deprecated ids that end in `+`
  # themselves (`GPL-2.0+`), so a second `+` is refused.
  defp or_later?(word) do
    base = String.slice(word, 0..-2//1)
    String.ends_with?(word, "+") and not String.ends_with?(base, "+") and license_id?(base)
  end

  defp license_id?(word), do: MapSet.member?(@license_ids, String.downcase(word))

  defp exception?(word) when word in @syntax, do: false

  defp exception?(word),
    do: MapSet.member?(@exception_ids, String.downcase(word)) or Regex.match?(@addition_ref, word)
end
