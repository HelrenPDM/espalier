defmodule EspalierWeb.Me.RecoveryCodeController do
  @moduledoc """
  Regenerates the recovery codes after a recent second factor (README
  section 6.6). The new codes are shown once, and every earlier code stops
  working.
  """
  use EspalierWeb, :controller

  alias Espalier.Accounts.{Factors, RecoveryCodes}

  def create(conn, _params) do
    scope = conn.assigns.current_scope
    codes = RecoveryCodes.generate(scope)
    Factors.notify_change(scope.user, :recovery_codes_regenerated, :recovery_code)
    json(conn, %{recovery_codes: codes})
  end
end
