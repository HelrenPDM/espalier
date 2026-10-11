defmodule Espalier.Credentials.WebhookWorkerTest do
  @moduledoc """
  Task 0013, steps 20 and 24 (ASVS 1.2.3, 1.3.6, 11.4.3, 13.3.1, 15.3.2 and
  16.2.5): `Espalier.Credentials.WebhookWorker` against the `Req.Test`
  stub that `config/test.exs` names in `:webhook_req_options`, each job run
  with `perform_job/3` in the test process. The worker posts the body it
  encoded once with `content-type: application/json` and
  `x-espalier-signature: sha256=<HMAC-SHA256 over these bytes>`, follows no
  redirect, returns an error for a status outside 200 to 299, and cancels
  the job for an unset or empty secret variable, an inactive or deleted
  webhook and a URL that `:webhook_allowed_hosts` no longer admits, without
  a request. Its log lines name webhook id, event and status and carry no
  body, secret, signature or address, and its job arguments carry ids, the
  event and the time only.
  """
  # System.put_env/2, Application.put_env/3 and Logger.put_module_level/2
  # change the node.
  use Espalier.DataCase, async: false

  import ExUnit.CaptureLog
  import Espalier.AccountsFixtures
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures

  alias Espalier.Credentials
  alias Espalier.Credentials.WebhookWorker

  @occurred_at "2026-10-11T08:00:00Z"

  setup do
    put_env!(:webhook_allowed_hosts, [{"hooks.example.org", nil}])

    secret_env = "WEBHOOK_SECRET_WORKER_TEST_#{System.unique_integer([:positive])}"
    secret = "whsec-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
    System.put_env(secret_env, secret)
    on_exit(fn -> System.delete_env(secret_env) end)

    program = publish_demo!()
    user = user_fixture()

    credential =
      credential_fixture(user, qualification!(program, "basics"), valid_until: ~D[2027-10-11])

    webhook = webhook_fixture(secret_env: secret_env)

    %{
      secret_env: secret_env,
      secret: secret,
      user: user,
      credential: credential,
      webhook: webhook,
      args: job_args(webhook, credential)
    }
  end

  defp put_env!(key, value) do
    previous = Application.fetch_env(:espalier, key)
    Application.put_env(:espalier, key, value)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:espalier, key, value)
        :error -> Application.delete_env(:espalier, key)
      end
    end)
  end

  defp job_args(webhook, credential, event \\ "credential.issued") do
    %{
      webhook_id: webhook.id,
      event: event,
      credential_id: credential.id,
      occurred_at: @occurred_at
    }
  end

  # Answers every request with `status` and reports path, headers and raw
  # body to the test process.
  defp stub_status(status) do
    test = self()

    Req.Test.stub(WebhookWorker, fn conn ->
      send(test, {:webhook_request, conn.request_path, conn.req_headers, raw_body(conn)})
      Plug.Conn.send_resp(conn, status, ~s({"detail":"receiver body"}))
    end)
  end

  defp raw_body(conn), do: conn |> Req.Test.raw_body() |> IO.iodata_to_binary()

  defp header(headers, name) do
    for {^name, value} <- headers, do: value
  end

  defp signature(secret, raw_body),
    do: "sha256=" <> Base.encode16(:crypto.mac(:hmac, :sha256, secret, raw_body), case: :lower)

  test "signs the raw body with HMAC-SHA256 and posts it as application/json", ctx do
    stub_status(200)

    assert :ok = perform_job(WebhookWorker, ctx.args)

    assert_received {:webhook_request, "/espalier", headers, raw_body}
    refute_received {:webhook_request, _path, _headers, _body}

    assert header(headers, "x-espalier-signature") == [signature(ctx.secret, raw_body)]
    assert header(headers, "content-type") == ["application/json"]

    assert JSON.decode!(raw_body) == %{
             "event" => "credential.issued",
             "credential_id" => ctx.credential.id,
             "user_email" => ctx.user.email,
             "qualification_code" => "basics",
             "status" => "active",
             "valid_until" => "2027-10-11",
             "occurred_at" => @occurred_at
           }
  end

  test "the body carries the event of the job and the current status", ctx do
    stub_status(204)
    credential = put_credential!(ctx.credential, status: :expired)

    assert :ok =
             perform_job(WebhookWorker, job_args(ctx.webhook, credential, "credential.expired"))

    assert_received {:webhook_request, "/espalier", headers, raw_body}
    assert header(headers, "x-espalier-signature") == [signature(ctx.secret, raw_body)]
    assert %{"event" => "credential.expired", "status" => "expired"} = JSON.decode!(raw_body)
  end

  test "an unset or empty secret variable cancels the job, and the log shows neither secret nor signature",
       ctx do
    stub_status(200)

    System.delete_env(ctx.secret_env)

    log =
      capture_log(fn ->
        assert {:cancel, _reason} = perform_job(WebhookWorker, ctx.args)
      end)

    System.put_env(ctx.secret_env, "")

    log =
      log <>
        capture_log(fn ->
          assert {:cancel, _reason} = perform_job(WebhookWorker, ctx.args)
        end)

    refute_received {:webhook_request, _path, _headers, _body}
    assert log =~ ctx.webhook.id
    assert log =~ "credential.issued"
    refute log =~ ctx.secret
    refute log =~ "sha256="
    refute log =~ ctx.user.email
  end

  test "an inactive or deleted webhook cancels the job without a request", ctx do
    stub_status(200)
    inactive = webhook_fixture(secret_env: ctx.secret_env, active: false)

    capture_log(fn ->
      assert {:cancel, _reason} =
               perform_job(WebhookWorker, job_args(inactive, ctx.credential))

      Repo.delete!(ctx.webhook)
      assert {:cancel, _reason} = perform_job(WebhookWorker, ctx.args)
    end)

    refute_received {:webhook_request, _path, _headers, _body}
  end

  test "a URL that the allowlist no longer admits cancels the job without a request", ctx do
    stub_status(200)

    other_port =
      webhook_fixture(secret_env: ctx.secret_env, url: "https://hooks.example.org:8443/x")

    http = webhook_fixture(secret_env: ctx.secret_env, url: "http://hooks.example.org/espalier")

    capture_log(fn ->
      assert {:cancel, _reason} = perform_job(WebhookWorker, job_args(other_port, ctx.credential))

      put_env!(:webhook_allow_http, false)
      assert {:cancel, _reason} = perform_job(WebhookWorker, job_args(http, ctx.credential))

      put_env!(:webhook_allowed_hosts, [{"other.example.org", nil}])
      assert {:cancel, _reason} = perform_job(WebhookWorker, ctx.args)

      put_env!(:webhook_allowed_hosts, [])
      assert {:cancel, _reason} = perform_job(WebhookWorker, ctx.args)
    end)

    refute_received {:webhook_request, _path, _headers, _body}
  end

  test "a redirect is not followed: the job returns an error without a request to the target",
       ctx do
    test = self()

    Req.Test.stub(WebhookWorker, fn
      %Plug.Conn{request_path: "/espalier"} = conn ->
        send(test, {:webhook_request, conn.request_path, conn.req_headers, raw_body(conn)})
        Req.Test.redirect(conn, to: "/elsewhere")

      conn ->
        send(test, {:webhook_request, conn.request_path, conn.req_headers, raw_body(conn)})
        Plug.Conn.send_resp(conn, 200, "")
    end)

    capture_log(fn -> assert {:error, _reason} = perform_job(WebhookWorker, ctx.args) end)

    assert_received {:webhook_request, "/espalier", _headers, _body}
    refute_received {:webhook_request, "/elsewhere", _headers, _body}
  end

  test "a status of 500 returns an error and logs webhook id, event and status only", ctx do
    stub_status(500)

    log =
      capture_log(fn ->
        assert {:error, _reason} = perform_job(WebhookWorker, ctx.args)
      end)

    assert_received {:webhook_request, "/espalier", headers, raw_body}
    [signature] = header(headers, "x-espalier-signature")

    assert log =~ ctx.webhook.id
    assert log =~ "credential.issued"
    assert log =~ "500"
    refute log =~ raw_body
    refute log =~ "receiver body"
    refute log =~ ctx.secret
    refute log =~ signature
    refute log =~ "sha256="
    refute log =~ ctx.user.email
  end

  test "a transport error returns an error", ctx do
    Req.Test.stub(WebhookWorker, &Req.Test.transport_error(&1, :econnrefused))

    log =
      capture_log(fn ->
        assert {:error, _reason} = perform_job(WebhookWorker, ctx.args)
      end)

    assert log =~ ctx.webhook.id
    refute log =~ ctx.secret
    refute log =~ ctx.user.email
  end

  test "a delivery logs webhook id, event and status at info, without body, secret or signature",
       ctx do
    Logger.put_module_level(WebhookWorker, :info)
    on_exit(fn -> Logger.delete_module_level(WebhookWorker) end)
    stub_status(200)

    log =
      capture_log([level: :info], fn ->
        assert :ok = perform_job(WebhookWorker, ctx.args)
      end)

    assert_received {:webhook_request, "/espalier", headers, raw_body}
    [signature] = header(headers, "x-espalier-signature")

    assert log =~ "webhook delivered"
    assert log =~ ctx.webhook.id
    assert log =~ "credential.issued"
    assert log =~ "200"
    refute log =~ raw_body
    refute log =~ ctx.secret
    refute log =~ signature
    refute log =~ ctx.user.email
  end

  test "a webhook job carries ids, the event and the time only", ctx do
    _inactive = webhook_fixture(secret_env: ctx.secret_env, active: false)
    _unsubscribed = webhook_fixture(secret_env: ctx.secret_env, events: ["credential.revoked"])

    assert :ok = Credentials.enqueue_webhooks("credential.issued", ctx.credential)

    assert [job] = all_enqueued(worker: WebhookWorker)
    assert job.queue == "webhooks"
    assert job.max_attempts == 10

    assert job.args |> Map.keys() |> Enum.sort() ==
             ["credential_id", "event", "occurred_at", "webhook_id"]

    assert job.args["webhook_id"] == ctx.webhook.id
    assert job.args["credential_id"] == ctx.credential.id
    assert job.args["event"] == "credential.issued"
    refute Enum.any?(Map.values(job.args), &String.contains?(&1, "@"))
  end
end
