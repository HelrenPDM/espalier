defmodule Espalier.Identity.OidcTransportTest do
  # ASVS 12.3.2 and 15.3.2: every request to a provider validates the TLS
  # certificate and follows no redirect.
  use Espalier.OidcCase

  alias Espalier.Identity.{Oidc, OidcProvider}
  alias Espalier.Identity.Oidc.HttpAdapter
  alias Espalier.Test.CountingPlug
  alias EspalierWeb.OidcController
  alias X509.Certificate.Extension

  defp request_opts_safe?(request_opts) do
    not Map.has_key?(request_opts, :ssl) and
      Map.get(request_opts, :http_adapter) == {HttpAdapter, %{}}
  end

  test "no option list carries ssl options or another HTTP adapter" do
    [provider] = setup_providers([provider_env("oidc", "oidc")], wait: false)

    refute Map.has_key?(Oidc.client_context_opts(provider), :request_opts)

    %{start: {_module, _fun, [worker_opts]}} =
      Espalier.Identity.Oidc.Supervisor.child_spec_for(provider)

    assert request_opts_safe?(worker_opts.provider_configuration_opts.request_opts)

    for purpose <- ["sign_in", "link", "step_up"] do
      assert request_opts_safe?(OidcController.authorize_opts(provider, purpose)[:request_opts])
    end

    assert request_opts_safe?(OidcController.callback_opts(provider)[:request_opts])
  end

  test "the worker follows no redirect at discovery" do
    DevOidc.put_switch(:oidc, :discovery_redirect)
    [provider] = setup_providers([provider_env("oidc", "oidc")], wait: false)

    Process.sleep(500)

    assert :oidcc_provider_configuration_worker.get_provider_configuration(provider.worker) ==
             :undefined

    assert Enum.any?(DevOidc.requests(:oidc), &(&1.endpoint == :discovery))
    refute Enum.any?(DevOidc.requests(:oidc), &(&1.endpoint == :moved))
  end

  test "the token request follows no redirect", %{conn: conn} do
    setup_providers([provider_env("oidc", "oidc", %{"PROVISION" => "true"})])
    DevOidc.put_switch(:oidc, :token_redirect)

    {_conn, location} = to_callback(conn, "oidc", "olga")
    assert finish_error(location) == "oidc_failed"

    assert Enum.any?(DevOidc.requests(:oidc), &(&1.endpoint == :token_redirect))
    refute Enum.any?(DevOidc.requests(:oidc), &(&1.path =~ "token-moved"))
  end

  @tag :tmp_dir
  test "discovery and keys need a trusted TLS certificate", %{tmp_dir: dir} do
    key = X509.PrivateKey.new_rsa(2048)

    cert =
      X509.Certificate.self_signed(key, "/CN=localhost",
        template: :server,
        extensions: [subject_alt_name: Extension.subject_alt_name(["localhost"])]
      )

    certfile = Path.join(dir, "server.crt")
    keyfile = Path.join(dir, "server.key")
    File.write!(certfile, X509.Certificate.to_pem(cert))
    File.write!(keyfile, X509.PrivateKey.to_pem(key))

    counter = :counters.new(1, [])

    start_supervised!(
      {Bandit,
       plug: {CountingPlug, counter},
       scheme: :https,
       ip: {127, 0, 0, 1},
       port: 4012,
       certfile: certfile,
       keyfile: keyfile,
       startup_log: false}
    )

    provider = %OidcProvider{
      key: "tls",
      type: "oidc",
      issuer: "https://localhost:4012/oidc",
      client_auth: :client_secret_basic,
      worker: Module.concat(__MODULE__, TlsWorker)
    }

    log =
      capture_log([level: :error], fn ->
        start_supervised!(Espalier.Identity.Oidc.Supervisor.child_spec_for(provider))
        Process.sleep(500)
      end)

    assert :oidcc_provider_configuration_worker.get_provider_configuration(provider.worker) ==
             :undefined

    # The worker connected and the TLS handshake failed before any request.
    assert log =~ "Metadata load failed for issuer https://localhost:4012/oidc"
    assert log =~ "tls_alert"
    assert :counters.get(counter, 1) == 0
  end
end
