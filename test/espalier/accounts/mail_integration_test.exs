defmodule Espalier.Accounts.MailIntegrationTest do
  # Needs Mailpit from compose.dev.yaml: make services-up, make test-integration.
  use Espalier.DataCase, async: false

  @moduletag :mail

  alias Espalier.Accounts.UserNotifier

  test "an invitation reaches Mailpit with the link in the fragment" do
    address = "mail-#{System.unique_integer([:positive])}@example.org"
    token = "integration-token"
    email = UserNotifier.invitation_email(%{email: address, display_name: "Ada"}, token)

    assert {:ok, _} =
             Espalier.Mailer.deliver(email,
               adapter: Swoosh.Adapters.SMTP,
               relay: "localhost",
               port: 1025,
               tls: :never,
               auth: :never,
               ssl: false
             )

    assert %{status: 200, body: %{"messages" => [message | _]}} =
             Req.get!("http://localhost:8025/api/v1/search", params: [query: "to:#{address}"])

    assert message["Subject"] == "Your invitation to Espalier"

    assert %{status: 200, body: body} =
             Req.get!("http://localhost:8025/api/v1/message/#{message["ID"]}")

    assert body["Text"] =~ "/invite#token=#{token}"
  end
end
