defmodule Espalier.Accounts.Passkeys.WaxCall do
  @moduledoc """
  Runs a `wax_` call and rescues its exceptions (`wax_` issue #61, PR #62):
  `wax_` 0.7.0 raises on some malformed input, for example a
  `CaseClauseError` for an unknown `type` in `clientDataJSON`. A rescued
  exception logs `input_validation_fail` with the exception module in the
  attribute `exception` and without the message.
  """

  alias Espalier.SecurityLog

  @doc "Returns the result of `fun`, or `{:error, :wax_exception}` when it raises."
  @spec run((-> term())) :: term()
  def run(fun) when is_function(fun, 0) do
    fun.()
  rescue
    exception ->
      SecurityLog.event(:input_validation_fail, %{
        exception: inspect(exception.__struct__),
        reason: :wax_exception
      })

      {:error, :wax_exception}
  end
end
