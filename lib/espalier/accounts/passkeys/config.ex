defmodule Espalier.Accounts.Passkeys.Config do
  @moduledoc """
  The relying party of the passkey ceremonies: `rp_id`, `rp_name` and the
  exact list of origins (`config :espalier, :webauthn`). Development and
  tests use `localhost` and the Vite origin; production derives both from
  `PUBLIC_URL` (`config/runtime.exs`).
  """

  @type t :: %{rp_id: String.t(), rp_name: String.t(), origins: [String.t()]}

  @doc "Returns the relying party configuration."
  @spec get() :: t()
  def get do
    config = Application.fetch_env!(:espalier, :webauthn)

    %{
      rp_id: Keyword.fetch!(config, :rp_id),
      rp_name: Keyword.fetch!(config, :rp_name),
      origins: Keyword.fetch!(config, :origins)
    }
  end
end
