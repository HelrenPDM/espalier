defmodule Espalier.Identity.ConfigError do
  @moduledoc """
  Raised at boot for an invalid provider configuration. The message names
  the environment variable and never contains the value of a secret.
  """
  defexception [:message]
end
