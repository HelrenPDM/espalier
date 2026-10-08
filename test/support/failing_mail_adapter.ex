defmodule Espalier.Test.FailingMailAdapter do
  @moduledoc "A mail adapter whose every delivery fails, for the logging tests."
  use Swoosh.Adapter

  @impl Swoosh.Adapter
  def deliver(_email, _config), do: {:error, :test}
end
