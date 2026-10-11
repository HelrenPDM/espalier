defmodule Espalier.Credentials.Webhook do
  @moduledoc """
  A receiver of credential events (README section 11). The secret that
  signs its requests lives in the environment variable named in
  `secret_env`; neither the database nor the repository holds it (ASVS
  13.3.1).

  The changeset admits a URL only for a host and port that the operator
  lists in `WEBHOOK_ALLOWED_HOSTS` (ASVS 1.3.6), and only with `https`
  unless `config :espalier, :webhook_allow_http` is true, which only
  `config/dev.exs` and `config/test.exs` set.
  `Espalier.Credentials.WebhookWorker` repeats the check with
  `url_allowed?/1` before each delivery.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @events ~w(credential.issued credential.refresh_due credential.expired credential.revoked)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "webhooks" do
    field :url, :string
    field :events, {:array, :string}, default: []
    field :secret_env, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc "The events a webhook can subscribe to."
  def events, do: @events

  @doc false
  def changeset(webhook, attrs) do
    webhook
    |> cast(attrs, [:url, :events, :secret_env, :active])
    |> validate_required([:url, :events, :secret_env, :active])
    |> validate_length(:url, max: 255)
    |> validate_subset(:events, @events)
    |> validate_events_present()
    |> validate_format(:secret_env, ~r/\AWEBHOOK_SECRET_[A-Z0-9_]+\z/)
    |> validate_length(:secret_env, max: 255)
    |> validate_change(:url, fn :url, url ->
      case check_url(url) do
        :ok -> []
        {:error, code} -> [url: {"is not admitted", validation: code}]
      end
    end)
  end

  # The empty list equals the default of the field, so cast/3 records no
  # change for it and validate_length/3 would not run.
  defp validate_events_present(changeset) do
    case get_field(changeset, :events) do
      [_event | _rest] -> changeset
      _empty -> add_error(changeset, :events, "should have at least 1 item", validation: :length)
    end
  end

  @doc """
  True when `url` uses an admitted scheme and names a host and port of
  `WEBHOOK_ALLOWED_HOSTS`.
  """
  @spec url_allowed?(String.t()) :: boolean()
  def url_allowed?(url) when is_binary(url), do: check_url(url) == :ok
  def url_allowed?(_url), do: false

  # The host is compared lower-case. An entry without a port stands for the
  # default port of the URL's scheme, and an empty list admits no URL.
  defp check_url(url) do
    case URI.new(url) do
      {:ok, %URI{scheme: scheme, host: host, port: port, userinfo: nil}}
      when is_binary(scheme) and is_binary(host) and host != "" ->
        cond do
          scheme not in admitted_schemes() -> {:error, :scheme}
          allowed_host?(String.downcase(host), port, scheme) -> :ok
          true -> {:error, :host_not_allowed}
        end

      _other ->
        {:error, :format}
    end
  end

  defp admitted_schemes do
    if Application.get_env(:espalier, :webhook_allow_http, false),
      do: ["https", "http"],
      else: ["https"]
  end

  defp allowed_host?(host, port, scheme) do
    Enum.any?(Application.get_env(:espalier, :webhook_allowed_hosts, []), fn
      {^host, nil} -> port == URI.default_port(scheme)
      {^host, ^port} -> true
      _entry -> false
    end)
  end
end
