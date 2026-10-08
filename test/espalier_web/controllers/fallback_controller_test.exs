defmodule EspalierWeb.FallbackControllerTest do
  use EspalierWeb.ConnCase, async: true

  alias Espalier.Accounts.User
  alias EspalierWeb.FallbackController

  test "maps errors to codes without internals", %{conn: conn} do
    for {error, status, code} <- [
          {:forbidden, 403, "forbidden"},
          {:not_found, 404, "not_found"},
          {:invalid_token, 400, "invalid_token"},
          {:invalid_credentials, 401, "invalid_credentials"},
          {:bad_request, 400, "bad_request"}
        ] do
      conn = FallbackController.call(conn, {:error, error})
      assert json_response(conn, status) == %{"error" => code}
    end
  end

  test "a changeset answers 422 validation_failed with error codes only", %{conn: conn} do
    changeset =
      User.password_changeset(%User{}, %{password: "short"})

    conn = FallbackController.call(conn, {:error, changeset})

    assert json_response(conn, 422) == %{
             "error" => "validation_failed",
             "fields" => %{"password" => ["too_short"]}
           }
  end
end
