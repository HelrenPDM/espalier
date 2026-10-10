defmodule Espalier.Credentials do
  @moduledoc """
  Requirement evaluation, credentials and attendance (README section 7,
  domain rule 6). This module holds the interface that task 0009 calls;
  task 0013 implements both functions.
  """

  alias Espalier.Accounts.Scope
  alias Espalier.Catalog.Program

  @doc """
  Evaluates the requirements of the program's qualifications for the scope
  user and issues the credentials whose requirements are met. Task 0009 calls
  it after a passed exam attempt and after a module completion; until task
  0013, it issues nothing.
  """
  @spec evaluate(Scope.t(), struct()) :: {:ok, list()}
  def evaluate(%Scope{}, %Program{}), do: {:ok, []}

  @doc """
  Returns the ids of the companion formats of the program for which the
  scope user holds an attendance certificate. Until task 0013 creates
  `attendance_certificates`, it returns `[]`.
  """
  @spec attended_format_ids(Scope.t(), struct()) :: [Ecto.UUID.t()]
  def attended_format_ids(%Scope{}, %Program{}), do: []
end
