defmodule Espalier.Credentials.WebhookTest do
  @moduledoc """
  Task 0013, steps 6 and 24 (ASVS 1.3.6 and 13.3.1): the
  `Espalier.Credentials.Webhook` changeset admits only the four credential
  events, a `secret_env` with the prefix `WEBHOOK_SECRET_`, an `https` URL
  unless `:webhook_allow_http` is set, and a host and port listed in
  `:webhook_allowed_hosts`, compared lower-case; an entry without a port
  stands for the default port of the scheme, and an empty list admits no
  URL. `Webhook.url_allowed?/1`, which the worker calls before each
  delivery, gives the same answer. The URL has at most 255 characters, the
  size of the column.
  """
  # Application.put_env/3 changes the allowlist for the node.
  use ExUnit.Case, async: false

  alias Espalier.Credentials.Webhook
  alias Espalier.Repo
  alias EspalierWeb.ChangesetJSON

  @valid %{
    url: "https://hooks.example.org/espalier",
    events: ["credential.issued"],
    secret_env: "WEBHOOK_SECRET_TEST",
    active: true
  }

  setup do
    put_env!(:webhook_allow_http, false)
    put_env!(:webhook_allowed_hosts, [{"hooks.example.org", nil}, {"api.example.net", 8443}])
    :ok
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

  defp changeset(attrs), do: Webhook.changeset(%Webhook{}, Map.merge(@valid, attrs))

  # The error codes as EspalierWeb.ChangesetJSON renders them.
  defp codes(attrs), do: attrs |> changeset() |> ChangesetJSON.error_codes()

  defp url_codes(url), do: codes(%{url: url})

  # An https URL on the listed host hooks.example.org with `length` characters.
  defp url_of_length(length) do
    prefix = "https://hooks.example.org/"
    prefix <> String.duplicate("a", length - String.length(prefix))
  end

  test "accepts a listed host, the four credential events and a reserved secret variable" do
    assert changeset(%{events: Webhook.events()}).valid?

    assert Webhook.events() == [
             "credential.issued",
             "credential.refresh_due",
             "credential.expired",
             "credential.revoked"
           ]
  end

  test "rejects an unknown event" do
    assert codes(%{events: ["credential.issued", "credential.viewed"]}) == %{events: ["subset"]}
    assert codes(%{events: ["credential.Issued"]}) == %{events: ["subset"]}
  end

  test "rejects an empty event list" do
    assert codes(%{events: []}) == %{events: ["length"]}
    refute Webhook.changeset(%Webhook{events: ["credential.issued"]}, %{events: []}).valid?
  end

  test "rejects a secret_env without the prefix WEBHOOK_SECRET_" do
    for name <- ["SECRET_KEY_BASE", "CLOAK_KEY_V1", "DATABASE_URL", "webhook_secret_test"] do
      assert codes(%{secret_env: name}) == %{secret_env: ["format"]}, name
    end

    for name <- ["WEBHOOK_SECRET_", "WEBHOOK_SECRET_A-B", "WEBHOOK_SECRET_A\nB"] do
      assert codes(%{secret_env: name}) == %{secret_env: ["format"]}, inspect(name)
    end

    assert changeset(%{secret_env: "WEBHOOK_SECRET_HR_SYSTEM_2"}).valid?
  end

  test "rejects an http URL while :webhook_allow_http is false" do
    assert url_codes("http://hooks.example.org/espalier") == %{url: ["scheme"]}
    refute Webhook.url_allowed?("http://hooks.example.org/espalier")
  end

  test "admits an http URL to a listed host while :webhook_allow_http is true" do
    put_env!(:webhook_allow_http, true)

    assert changeset(%{url: "http://hooks.example.org/espalier"}).valid?
    assert Webhook.url_allowed?("http://hooks.example.org/espalier")
    assert url_codes("http://hooks.example.org:8080/espalier") == %{url: ["host_not_allowed"]}
  end

  test "rejects a host outside the list with host_not_allowed on url" do
    for url <- [
          "https://other.example.org/espalier",
          "https://hooks.example.org.attacker.example/espalier",
          "https://sub.hooks.example.org/espalier",
          "https://127.0.0.1/espalier"
        ] do
      assert url_codes(url) == %{url: ["host_not_allowed"]}, url
      refute Webhook.url_allowed?(url), url
    end
  end

  test "rejects a listed host:port entry with another port" do
    for url <- ["https://api.example.net:9443/hook", "https://api.example.net/hook"] do
      assert url_codes(url) == %{url: ["host_not_allowed"]}, url
      refute Webhook.url_allowed?(url), url
    end
  end

  test "rejects a non-default port for a listed host without port" do
    url = "https://hooks.example.org:8443/espalier"
    assert url_codes(url) == %{url: ["host_not_allowed"]}
    refute Webhook.url_allowed?(url)
  end

  test "rejects every URL while the list is empty" do
    put_env!(:webhook_allowed_hosts, [])

    for url <- [
          "https://hooks.example.org/espalier",
          "https://api.example.net:8443/hook",
          "https://localhost/hook"
        ] do
      assert url_codes(url) == %{url: ["host_not_allowed"]}, url
      refute Webhook.url_allowed?(url), url
    end
  end

  test "accepts a listed host in any letter case and a listed host:port" do
    for url <- [
          "https://hooks.example.org/espalier",
          "https://HOOKS.Example.ORG/espalier",
          "https://hooks.example.org:443/espalier",
          "https://api.example.net:8443/hook",
          "https://API.EXAMPLE.NET:8443/hook"
        ] do
      assert changeset(%{url: url}).valid?, url
      assert Webhook.url_allowed?(url), url
    end
  end

  test "rejects a URL with user information or without a host" do
    for url <- ["https://user:pass@hooks.example.org/espalier", "https:///espalier", "hooks"] do
      refute changeset(%{url: url}).valid?, url
      refute Webhook.url_allowed?(url), url
    end

    refute Webhook.url_allowed?(nil)
  end

  describe "URL length" do
    # Only these tests write to the database.
    setup tags do
      Espalier.DataCase.setup_sandbox(tags)
      :ok
    end

    test "admits a URL of 255 characters on a listed host and stores it" do
      url = url_of_length(255)
      assert String.length(url) == 255

      changeset = changeset(%{url: url})
      assert changeset.valid?
      assert {:ok, %Webhook{url: ^url}} = Repo.insert(changeset)
    end

    test "rejects a URL of 256 characters with the code length on url" do
      url = url_of_length(256)
      assert String.length(url) == 256

      assert url_codes(url) == %{url: ["length"]}
    end
  end
end
