defmodule EspalierWeb.FallbackController do
  @moduledoc """
  Translates controller errors into the JSON error body `{"error": code}`
  (README section 6.10). The answers carry a code and no internals.

  Task 0005 adds `authentication_failed` (401) for every failed second
  factor, passkey sign-in, recovery and re-authentication,
  `registration_failed` (422) for a failed passkey registration,
  `invalid_code` (422) for a wrong TOTP confirmation, and the conflicts
  (409) of the factor rules.

  Task 0006 adds `ticket_invalid` (401) for a failed finish step,
  `unknown_provider` (404), `step_up_not_available` (422), and the link
  conflicts `identity_in_use` and `provider_already_linked` (409).

  Task 0007 adds `link_required` (409) for a directory sign-in whose
  e-mail address belongs to another account.

  Task 0009 adds `not_enrolled` (409) for a learning write without an
  enrollment in the program, `validation_failed` (422) with the member
  `answer` (code `invalid`) for an answer that does not fit its item and
  with the member `answers` (codes `incomplete` and `invalid`) for exam
  answers, and `assessments_open` (409) with the open exams of a module.

  Task 0013 adds `validation_failed` (422) for a check of the context, such
  as an attendance date after today (member `held_on`, code `future`) or
  before 2000-01-01 (code `past`).

  Task 0015 adds the codes of the admin area: 409 `user_exists`,
  `not_invitable`, `own_account`, `idp_claim`, `demo_user`,
  `policy_in_use`, `published`, `superseded`, `already_revoked` and
  `not_publishable`, and 422 `identity_verification_required` and
  `secret_env_unset`. The pack controller renders the 409 answer
  `alignment_errors` with its findings and the 422 answer
  `archive_rejected` with its report itself, and
  `EspalierWeb.Plugs.RequireAdminPasskey` answers 403 `passkey_required`.

  Task 0016a adds the codes of the pack workbench: 409 `path_taken`,
  `too_many_files`, `draft_too_large`, `no_payload` and `draft_limit`, which
  names the configured limit in `max_drafts`; 429
  `checks_busy` with `retry-after: 5` when every slot of
  `Espalier.Workbench.CheckLimiter` is taken; and 422 `validation_failed`
  with `fields.path` `["invalid_path"]` and `fields.content` `["too_large"]`,
  `["nul_character"]` or `["invalid_encoding"]`, and with the members of a
  request whose sources do not fit (`required`, `not_allowed`). The draft
  controllers render the 409 answer `stale_draft` with the stored
  `lock_version` themselves.
  """
  use EspalierWeb, :controller

  @statuses %{
    invalid_credentials: :unauthorized,
    authentication_failed: :unauthorized,
    unauthenticated: :unauthorized,
    invalid_token: :bad_request,
    bad_request: :bad_request,
    forbidden: :forbidden,
    not_found: :not_found,
    registration_failed: :unprocessable_entity,
    invalid_code: :unprocessable_entity,
    last_factor: :conflict,
    admin_passkey_required: :conflict,
    totp_already_enabled: :conflict,
    password_required: :conflict,
    ticket_invalid: :unauthorized,
    unknown_provider: :not_found,
    step_up_not_available: :unprocessable_entity,
    identity_in_use: :conflict,
    provider_already_linked: :conflict,
    link_required: :conflict,
    not_enrolled: :conflict,
    user_exists: :conflict,
    not_invitable: :conflict,
    own_account: :conflict,
    identity_verification_required: :unprocessable_entity,
    idp_claim: :conflict,
    demo_user: :conflict,
    policy_in_use: :conflict,
    published: :conflict,
    superseded: :conflict,
    already_revoked: :conflict,
    not_publishable: :conflict,
    secret_env_unset: :unprocessable_entity,
    path_taken: :conflict,
    too_many_files: :conflict,
    draft_too_large: :conflict,
    draft_limit: :conflict,
    no_payload: :conflict,
    checks_busy: :too_many_requests
  }

  # The workbench codes of a path or a content (task 0016a).
  @validation_codes %{
    invalid_path: {"path", "invalid_path"},
    file_too_large: {"content", "too_large"},
    nul_character: {"content", "nul_character"},
    invalid_encoding: {"content", "invalid_encoding"}
  }

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{
      error: "validation_failed",
      fields: EspalierWeb.ChangesetJSON.error_codes(changeset)
    })
  end

  def call(conn, {:error, :invalid_answer}) do
    validation_failed(conn, "answer", "invalid")
  end

  def call(conn, {:error, {:answers, code}}) when code in ["incomplete", "invalid"] do
    validation_failed(conn, "answers", code)
  end

  def call(conn, {:error, {:validation_failed, member, code}})
      when is_binary(member) and is_binary(code) do
    validation_failed(conn, member, code)
  end

  def call(conn, {:error, code}) when is_map_key(@validation_codes, code) do
    {member, reason} = Map.fetch!(@validation_codes, code)
    validation_failed(conn, member, reason)
  end

  def call(conn, {:error, {:fields, fields}}) when is_map(fields) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_failed", fields: fields})
  end

  def call(conn, {:error, :draft_limit}) do
    conn
    |> put_status(:conflict)
    |> json(%{error: "draft_limit", max_drafts: Espalier.Workbench.max_drafts()})
  end

  def call(conn, {:error, :checks_busy}) do
    conn
    |> put_resp_header("retry-after", "5")
    |> render_error(:checks_busy)
  end

  def call(conn, {:error, {:assessments_open, assessments}}) do
    conn
    |> put_status(:conflict)
    |> json(EspalierWeb.LearningJSON.assessments_open(%{assessments: assessments}))
  end

  def call(conn, {:error, code}) when is_map_key(@statuses, code) do
    render_error(conn, code)
  end

  defp validation_failed(conn, member, code) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{error: "validation_failed", fields: %{member => [code]}})
  end

  @doc """
  Renders the error body of `code` on `conn`. Controllers that change the
  session before a failure (WebAuthn ceremonies, the pending second factor)
  call it with their own conn, because the fallback receives the conn that
  entered the action.
  """
  def render_error(conn, code) when is_map_key(@statuses, code) do
    conn
    |> put_status(Map.fetch!(@statuses, code))
    |> json(%{error: Atom.to_string(code)})
  end
end
