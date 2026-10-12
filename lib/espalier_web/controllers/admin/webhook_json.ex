defmodule EspalierWeb.Admin.WebhookJSON do
  @moduledoc "The views of `EspalierWeb.Admin.WebhookController` (task 0015), generated with `mix phx.gen.json`."
  alias Espalier.Credentials.Webhook

  @doc """
  Renders a list of webhooks.
  """
  def index(%{webhooks: webhooks}) do
    %{data: for(webhook <- webhooks, do: data(webhook))}
  end

  @doc """
  Renders a single webhook.
  """
  def show(%{webhook: webhook}) do
    %{data: data(webhook)}
  end

  defp data(%Webhook{} = webhook) do
    %{
      id: webhook.id,
      url: webhook.url,
      events: webhook.events,
      secret_env: webhook.secret_env,
      active: webhook.active
    }
  end
end
