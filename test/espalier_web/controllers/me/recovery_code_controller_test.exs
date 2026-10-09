defmodule EspalierWeb.Me.RecoveryCodeControllerTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts.{MailWorker, RecoveryCodes}

  test "regenerates the codes after a recent second factor", %{conn: conn} do
    user = user_fixture()
    totp_fixture(user)
    old = recovery_codes_fixture(user)
    conn = log_in_user(conn, user)

    conn = api_request(conn, :post, "/api/me/recovery-codes")
    assert %{"recovery_codes" => codes} = json_response(conn, 200)
    assert length(codes) == 10
    for code <- old, do: assert(RecoveryCodes.use(user, code) == {:error, :invalid_code})

    assert_enqueued(
      worker: MailWorker,
      args: %{"kind" => "recovery_codes_regenerated", "user_id" => user.id}
    )

    stale = log_in_user(api_conn(), user, mfa_at: DateTime.add(DateTime.utc_now(:second), -660))
    conn = api_request(stale, :post, "/api/me/recovery-codes")
    assert json_response(conn, 403) == %{"error" => "reauth_required"}
  end
end
