defmodule EspalierWeb.Admin.CredentialAdminControllerTest do
  @moduledoc """
  The revocation of a credential by an admin (task 0015, steps 6 and 19;
  README sections 8 and 10): an unknown id answers 404, a revocation sets
  `revoked`, answers the qualification code, enqueues one
  `credential.revoked` job per active webhook subscribed to that event and
  writes `credential.revoked` with actor and subject, and a second
  revocation answers 409 `already_revoked`.
  """
  use EspalierWeb.ConnCase, async: true

  import Ecto.Query
  import Espalier.CredentialsFixtures
  import Espalier.LearningFixtures, only: [publish_demo!: 0]
  import OpenApiSpex.TestAssertions

  alias Espalier.Audit.AuditEvent
  alias Espalier.Credentials.{Credential, WebhookWorker}
  alias Espalier.Repo
  alias EspalierWeb.ApiSpec

  setup %{conn: conn} do
    program = publish_demo!()
    admin = user_with_role_fixture(:admin)
    {_authenticator, _passkey} = passkey_fixture(admin)
    credential = credential_fixture(user_fixture(), qualification!(program, "basics"))

    %{
      admin: admin,
      conn: log_in_user(conn, admin),
      credential: credential,
      spec: ApiSpec.spec()
    }
  end

  defp revoke(conn, id), do: json_request(conn, :post, "/api/admin/credentials/#{id}/revoke")

  defp revocation_events(credential) do
    Repo.all(
      from e in AuditEvent,
        where: e.action == "credential.revoked" and e.subject_id == ^credential.id
    )
  end

  test "answers 404 not_found for an unknown id", %{conn: conn} do
    assert conn |> revoke(Ecto.UUID.generate()) |> json_response(404) == %{"error" => "not_found"}
  end

  test "answers 422 validation_failed for a malformed id", %{conn: conn} do
    assert json_response(revoke(conn, "not-a-uuid"), 422)["error"] == "validation_failed"
  end

  test "revokes the credential, answers its qualification code and enqueues the webhook job",
       %{conn: conn, admin: admin, credential: credential, spec: spec} do
    webhook = webhook_fixture()
    _issued_only = webhook_fixture(%{events: ["credential.issued"]})
    _inactive = webhook_fixture(%{active: false})

    conn = revoke(conn, credential.id)

    body = json_response(conn, 200)
    assert_schema(body, "AdminRevokedCredential", spec)

    assert body == %{
             "id" => credential.id,
             "qualification_code" => "basics",
             "status" => "revoked"
           }

    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert Repo.get!(Credential, credential.id).status == :revoked

    assert [%Oban.Job{args: args}] = all_enqueued(worker: WebhookWorker)

    assert %{
             "webhook_id" => webhook_id,
             "event" => "credential.revoked",
             "credential_id" => credential_id
           } = args

    assert webhook_id == webhook.id
    assert credential_id == credential.id

    assert [%AuditEvent{} = event] = revocation_events(credential)
    assert event.actor_id == admin.id
    assert event.subject_type == "Credential"
    assert event.details == %{"previous_status" => "active"}
  end

  test "a second revocation answers 409 already_revoked and changes nothing",
       %{conn: conn, credential: credential} do
    webhook_fixture()

    assert json_response(revoke(conn, credential.id), 200)["status"] == "revoked"
    assert json_response(revoke(conn, credential.id), 409) == %{"error" => "already_revoked"}

    assert length(all_enqueued(worker: WebhookWorker)) == 1
    assert length(revocation_events(credential)) == 1
  end

  test "revokes a credential in refresh_due", %{conn: conn, credential: credential} do
    put_credential!(credential, status: :refresh_due, refresh_due_at: DateTime.utc_now(:second))

    assert json_response(revoke(conn, credential.id), 200)["status"] == "revoked"
    assert [%AuditEvent{details: details}] = revocation_events(credential)
    assert details == %{"previous_status" => "refresh_due"}
  end
end
