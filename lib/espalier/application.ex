defmodule Espalier.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Espalier.Crypto.Keys
  alias Espalier.Telemetry.QueryLog

  @impl true
  def start(_type, _args) do
    Keys.check!()

    if Application.get_env(:espalier, QueryLog, [])[:enabled] do
      QueryLog.attach()
    end

    children = [
      EspalierWeb.Telemetry,
      Espalier.Vault,
      Espalier.Repo,
      {DNSCluster, query: Application.get_env(:espalier, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Espalier.PubSub},
      # Start a worker by calling: Espalier.Worker.start_link(arg)
      # {Espalier.Worker, arg},
      # Start to serve requests, typically the last entry
      EspalierWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Espalier.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    EspalierWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
