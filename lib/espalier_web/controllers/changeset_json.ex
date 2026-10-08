defmodule EspalierWeb.ChangesetJSON do
  @moduledoc """
  Error codes of a changeset per field: the codes of
  `Espalier.Accounts.PasswordPolicy` on `password` (`too_short`, `too_long`,
  `common`, `context`, `breached`), and Ecto's validation names for the
  other errors (`required`, `format`, `length`, `cast`, `unique`, ...).
  Messages and values are never rendered.
  """

  @doc "Returns `%{field => [code]}`."
  def error_codes(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {_message, opts} ->
      code(opts)
    end)
  end

  defp code(opts) do
    case opts[:validation] || opts[:constraint] do
      :unsafe_unique -> "unique"
      nil -> "invalid"
      code -> to_string(code)
    end
  end
end
