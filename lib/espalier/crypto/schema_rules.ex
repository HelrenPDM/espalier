defmodule Espalier.Crypto.SchemaRules do
  @moduledoc """
  Finds schema fields that break the rules for encrypted and hashed columns
  (AGENTS.md, `docs/security/crypto-inventory.md`).

  Cloak types define `embed_as(:self)`, so a Cloak field inside an embedded
  schema is written into the parent's JSON column as plaintext. A Cloak field
  without `redact: true` shows its value, or the plaintext before dump, in
  `inspect/1`. The tests under `test/espalier/crypto/` run these checks on
  every schema of the application.
  """

  @doc "Returns every module of the application that defines an Ecto schema, except test modules."
  @spec app_schemas() :: [module()]
  def app_schemas do
    for module <- Application.spec(:espalier, :modules),
        not test_module?(module),
        Code.ensure_loaded?(module),
        function_exported?(module, :__schema__, 1),
        do: module
  end

  @doc """
  True for an Ecto type that encrypts or hashes through Cloak: a module that
  exports `__cloak__/0`, `Espalier.Hashed.HMAC`, or any module in the `Cloak`
  namespace, also inside arrays, maps and parameterized types.
  """
  @spec cloak_type?(term()) :: boolean()
  def cloak_type?({:array, type}), do: cloak_type?(type)
  def cloak_type?({:map, type}), do: cloak_type?(type)
  def cloak_type?({:parameterized, {module, _params}}), do: cloak_type?(module)
  def cloak_type?(Espalier.Hashed.HMAC), do: true

  def cloak_type?(type) when is_atom(type) do
    String.starts_with?(Atom.to_string(type), "Elixir.Cloak.") or
      (Code.ensure_loaded?(type) and function_exported?(type, :__cloak__, 0))
  end

  def cloak_type?(_type), do: false

  @doc "Returns every `{module, field}` of an embedded schema whose type satisfies `cloak_type?/1`."
  @spec embedded_cloak_fields([module()]) :: [{module(), atom()}]
  def embedded_cloak_fields(modules) do
    for module <- modules,
        is_nil(module.__schema__(:source)),
        field <- cloak_fields(module),
        do: {module, field}
  end

  @doc "Returns every `{module, field}` whose type satisfies `cloak_type?/1` and that lacks `redact: true`."
  @spec unredacted_cloak_fields([module()]) :: [{module(), atom()}]
  def unredacted_cloak_fields(modules) do
    for module <- modules,
        field <- cloak_fields(module),
        field not in module.__schema__(:redact_fields),
        do: {module, field}
  end

  defp cloak_fields(module) do
    Enum.filter(module.__schema__(:fields), &cloak_type?(module.__schema__(:type, &1)))
  end

  defp test_module?(module),
    do: String.starts_with?(Atom.to_string(module), "Elixir.Espalier.Test.")
end
