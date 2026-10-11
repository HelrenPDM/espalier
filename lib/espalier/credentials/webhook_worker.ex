defmodule Espalier.Credentials.WebhookWorker do
  @moduledoc """
  Delivers one credential event to one webhook (README section 11).

  The job arguments carry the webhook id, the event, the credential id and
  `occurred_at` only. At delivery the worker reads the webhook, the secret
  from the environment variable named in `secret_env` (ASVS 13.3.1) and the
  credential with its user and qualification. It encodes the body once with
  `JSON.encode!/1` (ASVS 1.2.3), signs exactly these bytes with
  HMAC-SHA256 (ASVS 11.4.3) and posts them with `redirect: false` (ASVS
  15.3.2) and the headers `content-type: application/json` and
  `x-espalier-signature: sha256=<lowercase hex>`.

  The job is cancelled for a deleted or inactive webhook, an unset or empty
  secret variable, a URL that `WEBHOOK_ALLOWED_HOSTS` no longer admits
  (ASVS 1.3.6) and a deleted credential. A transport error or a status
  outside 200 to 299 returns an error, so that Oban retries with its
  default backoff. Log lines name the webhook id, the event and the status
  code; no body, secret, signature or address reaches the log (ASVS
  16.2.5). `config :espalier, :webhook_req_options` is merged into the Req
  options, so that `config/test.exs` routes the requests to a `Req.Test`
  stub.
  """
  use Oban.Worker, queue: :webhooks, max_attempts: 10

  require Logger

  alias Espalier.Credentials.{Credential, Webhook}
  alias Espalier.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{
      "webhook_id" => webhook_id,
      "event" => event,
      "credential_id" => credential_id,
      "occurred_at" => occurred_at
    } = args

    with {:ok, webhook} <- fetch_webhook(webhook_id),
         {:ok, secret} <- fetch_secret(webhook),
         :ok <- check_url(webhook),
         {:ok, credential} <- fetch_credential(credential_id) do
      body = encode(event, credential, occurred_at)
      deliver(webhook, event, body, secret)
    else
      {:cancel, reason} ->
        Logger.warning("webhook cancelled: webhook #{webhook_id}, event #{event}, #{reason}")
        {:cancel, reason}
    end
  end

  defp fetch_webhook(id) do
    case Repo.get(Webhook, id) do
      %Webhook{active: true} = webhook -> {:ok, webhook}
      _missing_or_inactive -> {:cancel, :webhook_inactive}
    end
  end

  defp fetch_secret(%Webhook{secret_env: name}) do
    case System.get_env(name) do
      secret when is_binary(secret) and secret != "" -> {:ok, secret}
      _unset -> {:cancel, :secret_unset}
    end
  end

  defp check_url(%Webhook{url: url}) do
    if Webhook.url_allowed?(url), do: :ok, else: {:cancel, :host_not_allowed}
  end

  defp fetch_credential(id) do
    case Repo.get(Credential, id) |> Repo.preload([:qualification]) do
      %Credential{} = credential -> {:ok, credential}
      nil -> {:cancel, :credential_missing}
    end
  end

  defp encode(event, credential, occurred_at) do
    user = Espalier.Accounts.get_user(credential.user_id)

    JSON.encode!(%{
      event: event,
      credential_id: credential.id,
      user_email: user && user.email,
      qualification_code: credential.qualification.code,
      status: Atom.to_string(credential.status),
      valid_until: credential.valid_until && Date.to_iso8601(credential.valid_until),
      occurred_at: occurred_at
    })
  end

  @doc "The value of `x-espalier-signature` for `body` signed with `secret`."
  @spec signature(String.t(), iodata()) :: String.t()
  def signature(secret, body) do
    "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, secret, body), case: :lower)
  end

  defp deliver(webhook, event, body, secret) do
    options =
      Keyword.merge(
        [
          body: body,
          headers: [
            {"content-type", "application/json"},
            {"x-espalier-signature", signature(secret, body)},
            {"user-agent", "Espalier"}
          ],
          redirect: false,
          retry: false,
          receive_timeout: 10_000
        ],
        Application.get_env(:espalier, :webhook_req_options, [])
      )

    case Req.post(webhook.url, options) do
      {:ok, %Req.Response{status: status}} when status in 200..299 ->
        Logger.info("webhook delivered: webhook #{webhook.id}, event #{event}, status #{status}")
        :ok

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("webhook failed: webhook #{webhook.id}, event #{event}, status #{status}")
        {:error, {:status, status}}

      {:error, exception} ->
        Logger.warning(
          "webhook failed: webhook #{webhook.id}, event #{event}, " <>
            "transport #{inspect(exception.__struct__)}"
        )

        {:error, :transport}
    end
  end
end
