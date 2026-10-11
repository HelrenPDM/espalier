defmodule EspalierWeb.Me.RecoveryCodeController do
  @moduledoc """
  Regenerates the recovery codes after a recent second factor (README
  section 6.6). The new codes are shown once, and every earlier code stops
  working.
  """
  use EspalierWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias EspalierWeb.ApiSpec.Responses
  alias EspalierWeb.Schemas.RecoveryCodeList

  # OpenAPI operations of task 0011 (README section 6.12). They describe the
  # route; validation and error bodies stay those of task 0005.
  tags ["Account"]
  security Responses.session_and_csrf()

  alias Espalier.Accounts.{Factors, RecoveryCodes}

  operation :create,
    summary: "Create new recovery codes",
    description:
      "Needs a second factor within the last 10 minutes. Every earlier code stops working.",
    responses:
      Map.merge(
        %{200 => {"The new codes", "application/json", RecoveryCodeList}},
        Responses.errors([
          {401, ["unauthenticated"]},
          {403, ["enrollment_required", "reauth_required", "csrf", "cross_site_request"]}
        ])
      )

  def create(conn, _params) do
    scope = conn.assigns.current_scope
    codes = RecoveryCodes.generate(scope)
    Factors.notify_change(scope.user, :recovery_codes_regenerated, :recovery_code)
    json(conn, %{recovery_codes: codes})
  end
end
