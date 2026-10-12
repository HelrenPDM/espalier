import { Dialog, DialogPanel, DialogTitle } from "@headlessui/react";
import { useId, useState, type FormEvent, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { useSearchParams } from "react-router";
import { ConfirmDialog } from "../../app/ConfirmDialog";
import { formatDate } from "../../app/format";
import { AlertRegion, Button, StatusRegion, TextField } from "../../app/forms";
import { FOCUS_RING } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useErrorText } from "../../app/useErrorText";
import { localToday } from "../../api/admin/attendance";
import { fieldCodes, isApiError } from "../../api/admin/fieldErrors";
import {
  isDraft,
  isSuperseded,
  useAdminPolicies,
  useCreateDraft,
  useCreatePolicy,
  useDeletePolicy,
  usePolicyVersion,
  usePolicyVersions,
  usePublishDraft,
  useUpdateDraft,
  useUpdatePolicy,
  type AdminPolicy,
  type AdminPolicyFields,
  type AdminPolicyVersionSummary,
} from "../../api/admin/policies";
import { RECENT_AUTH_ERROR_CODE } from "../../api/errors";
import { formatDay } from "../../player/format";
import { Markdown } from "../../player/Markdown";

const KEY_PATTERN = /^[a-z0-9][a-z0-9-]*$/;
const TEXT_MAX = 255;
const BODY_MAX = 200_000;

const CELL =
  "border-b border-gray-200 px-3 py-2 align-top text-gray-800 dark:border-gray-700 dark:text-gray-200";
const COLUMN_HEADER =
  "border-b border-gray-200 bg-gray-50 px-3 py-2 align-bottom font-semibold text-gray-900 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100";
const ROW_HEADER =
  "border-b border-gray-200 px-3 py-2 align-top font-medium text-gray-900 dark:border-gray-700 dark:text-gray-100";
const TABLE = "min-w-full border-collapse text-left text-sm";
const SCROLL_REGION = `overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700 ${FOCUS_RING}`;
const TEXTAREA = `mt-1 block w-full rounded-md border border-gray-500 bg-white px-3 py-2 font-mono text-sm text-gray-900 aria-[invalid=true]:border-red-700 dark:bg-gray-900 dark:text-gray-100 dark:aria-[invalid=true]:border-red-400 ${FOCUS_RING}`;
const FIELD_ERROR = "mt-1 text-sm text-red-700 dark:text-red-300";
const MUTED = "text-gray-700 dark:text-gray-300";

type PolicyErrors = Partial<Record<"key" | "title", string>>;

/**
 * The messages of the policy fields: the client checks, and the answers
 * of the server (422 `unique` on `key`, 409 `policy_in_use` for a changed
 * key of a policy with a published version).
 */
function usePolicyFieldErrors() {
  const { t } = useTranslation();
  const failureText = useFailureText();

  const validate = (fields: AdminPolicyFields): PolicyErrors => {
    const errors: PolicyErrors = {};
    if (fields.key === "") errors.key = t("admin.policies.errors.required");
    else if (fields.key.length > TEXT_MAX)
      errors.key = t("admin.policies.errors.tooLong", { max: TEXT_MAX });
    else if (!KEY_PATTERN.test(fields.key))
      errors.key = t("admin.policies.errors.keyFormat");
    if (fields.title === "") errors.title = t("admin.policies.errors.required");
    else if (fields.title.length > TEXT_MAX)
      errors.title = t("admin.policies.errors.tooLong", { max: TEXT_MAX });
    return errors;
  };

  const fromFailure = (
    failure: unknown,
  ): { fields: PolicyErrors; form: string | null } => {
    if (isApiError(failure, 409, "policy_in_use"))
      return {
        fields: { key: t("admin.policies.errors.keyInUse") },
        form: null,
      };
    if (isApiError(failure, 422)) {
      if (fieldCodes(failure, "key").includes("unique"))
        return {
          fields: { key: t("admin.policies.errors.keyTaken") },
          form: null,
        };
      return { fields: {}, form: t("admin.policies.errors.rejected") };
    }
    return { fields: {}, form: failureText(failure) };
  };

  return { validate, fromFailure };
}

/**
 * The message of a failure that no field explains. A 403
 * `reauth_required` reaches the page only after a closed step-up dialog.
 */
function useFailureText(): (failure: unknown) => string {
  const { t } = useTranslation();
  const errorText = useErrorText();
  return (failure) =>
    isApiError(failure, 403, RECENT_AUTH_ERROR_CODE)
      ? t("account.stepUp.text")
      : errorText(failure);
}

/** Key and title of a policy, for the new policy and for a change. */
function PolicyForm({
  initial,
  submitLabel,
  pending,
  onSubmit,
}: {
  initial: AdminPolicyFields;
  submitLabel: string;
  pending: boolean;
  /** Sends the fields and returns the field and form messages of a failure. */
  onSubmit: (
    fields: AdminPolicyFields,
  ) => Promise<{ fields: PolicyErrors; form: string | null } | null>;
}) {
  const { t } = useTranslation();
  const { validate } = usePolicyFieldErrors();
  const [fields, setFields] = useState(initial);
  const [errors, setErrors] = useState<PolicyErrors>({});
  const [formError, setFormError] = useState<string | null>(null);

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const trimmed = { key: fields.key.trim(), title: fields.title.trim() };
    const found = validate(trimmed);
    setErrors(found);
    setFormError(null);
    if (Object.keys(found).length > 0) return;
    const failure = await onSubmit(trimmed);
    if (failure === null) return;
    setErrors(failure.fields);
    setFormError(failure.form);
  };

  return (
    <form
      noValidate
      onSubmit={(event) => void submit(event)}
      className="mt-4 grid max-w-2xl gap-4 sm:grid-cols-2"
    >
      <TextField
        label={t("admin.policies.fields.title")}
        errors={errors.title === undefined ? [] : [errors.title]}
        value={fields.title}
        onChange={(event) =>
          setFields({ ...fields, title: event.target.value })
        }
        maxLength={TEXT_MAX}
        required
      />
      <TextField
        label={t("admin.policies.fields.key")}
        hint={t("admin.policies.fields.keyHint")}
        errors={errors.key === undefined ? [] : [errors.key]}
        value={fields.key}
        onChange={(event) => setFields({ ...fields, key: event.target.value })}
        maxLength={TEXT_MAX}
        autoComplete="off"
        spellCheck={false}
        autoCapitalize="off"
        required
      />
      <div className="space-y-2 sm:col-span-2">
        <AlertRegion>{formError}</AlertRegion>
        <Button type="submit" disabled={pending}>
          {submitLabel}
        </Button>
      </div>
    </form>
  );
}

/** The state of a version: published with its date, draft, or superseded draft. */
function VersionState({
  version,
  versions,
}: {
  version: AdminPolicyVersionSummary;
  versions: readonly AdminPolicyVersionSummary[];
}) {
  const { t, i18n } = useTranslation();
  if (version.published_at !== null)
    return (
      <span data-state="published">
        {t("admin.policies.versions.published", {
          date: formatDate(version.published_at, i18n.language),
        })}
      </span>
    );
  if (isSuperseded(version, versions))
    return (
      <span data-state="superseded">
        <span className="inline-flex items-center rounded-full border border-amber-700 bg-amber-50 px-2 py-0.5 text-xs font-medium text-amber-900 dark:border-amber-300 dark:bg-gray-800 dark:text-amber-200">
          {t("admin.policies.versions.superseded")}
        </span>
        <span className="mt-1 block text-xs text-gray-700 dark:text-gray-300">
          {t("admin.policies.versions.supersededHint")}
        </span>
      </span>
    );
  return <span data-state="draft">{t("admin.policies.versions.draft")}</span>;
}

/**
 * The publish dialog of a draft (task 0015, step 13): the effective date,
 * the checkbox `requires_refresher` and `refresh_due_count` of
 * `GET /api/admin/policy-versions/:id`. A superseded draft, and a draft
 * whose publication answers 409 `superseded`, gets the statement that it
 * cannot be published and no confirmation; a 409 `published` gets its
 * own message.
 */
function PublishDialog({
  version,
  versions,
  onClose,
  onPublished,
}: {
  version: AdminPolicyVersionSummary;
  versions: readonly AdminPolicyVersionSummary[];
  onClose: () => void;
  onPublished: (message: string) => void;
}) {
  const { t, i18n } = useTranslation();
  const failureText = useFailureText();
  const checkboxId = useId();
  const hintId = useId();
  const countId = useId();
  const [blocked, setBlocked] = useState<"superseded" | "published" | null>(
    isSuperseded(version, versions) ? "superseded" : null,
  );
  const details = usePolicyVersion(version.id, {
    enabled: blocked === null,
  });
  const publish = usePublishDraft();
  const [requiresRefresher, setRequiresRefresher] = useState(
    version.requires_refresher,
  );
  const [error, setError] = useState<string | null>(null);

  const confirm = async () => {
    setError(null);
    try {
      const published = await publish.mutateAsync({
        version,
        requiresRefresher,
      });
      onPublished(
        t("admin.policies.publish.done", { number: published.number }),
      );
    } catch (failure) {
      if (isApiError(failure, 409, "superseded")) setBlocked("superseded");
      else if (isApiError(failure, 409, "published")) setBlocked("published");
      else setError(failureText(failure));
    }
  };

  let count: ReactNode;
  if (details.isPending)
    count = <LoadingStatus text={t("admin.policies.publish.countLoading")} />;
  else if (details.isError)
    count = <p className={MUTED}>{t("admin.policies.publish.countFailed")}</p>;
  else
    count = (
      <p id={countId} data-refresh-due-count={details.data.refresh_due_count}>
        {t("admin.policies.publish.refreshDue", {
          count: details.data.refresh_due_count,
        })}
      </p>
    );

  return (
    <Dialog open onClose={onClose} className="relative z-50">
      <div className="fixed inset-0 bg-gray-900/40" aria-hidden="true" />
      <div className="fixed inset-0 flex items-center justify-center p-4">
        <DialogPanel className="w-full max-w-lg rounded-lg bg-white p-6 text-gray-900 shadow-xl dark:bg-gray-900 dark:text-gray-100">
          <DialogTitle className="text-lg font-semibold">
            {t("admin.policies.publish.title", {
              number: version.number,
              policy: version.policy_title,
            })}
          </DialogTitle>
          <div className="mt-3 space-y-3 text-sm text-gray-700 dark:text-gray-300">
            {blocked === "superseded" ? (
              <p
                role="alert"
                className="font-medium text-gray-900 dark:text-gray-100"
              >
                {t("admin.policies.publish.superseded")}
              </p>
            ) : blocked === "published" ? (
              <p
                role="alert"
                className="font-medium text-gray-900 dark:text-gray-100"
              >
                {t("admin.policies.publish.published")}
              </p>
            ) : (
              <>
                <p>
                  {t("admin.policies.publish.text", {
                    number: version.number,
                    date: formatDay(version.effective_from, i18n.language),
                  })}
                </p>
                <div className="flex items-start gap-3">
                  <input
                    id={checkboxId}
                    type="checkbox"
                    checked={requiresRefresher}
                    onChange={(event) =>
                      setRequiresRefresher(event.target.checked)
                    }
                    aria-describedby={`${hintId} ${countId}`}
                    className={`mt-0.5 size-4 rounded border-gray-500 text-accent-600 ${FOCUS_RING}`}
                  />
                  <div>
                    <label
                      htmlFor={checkboxId}
                      className="font-medium text-gray-900 dark:text-gray-100"
                    >
                      {t("admin.policies.publish.requiresRefresher")}
                    </label>
                    <p id={hintId}>
                      {t("admin.policies.publish.requiresRefresherHint")}
                    </p>
                  </div>
                </div>
                {count}
                <AlertRegion>{error}</AlertRegion>
              </>
            )}
          </div>
          <div className="mt-6 flex flex-wrap justify-end gap-3">
            {blocked !== null ? (
              <Button variant="secondary" onClick={onClose} data-autofocus>
                {t("admin.policies.publish.close")}
              </Button>
            ) : (
              <>
                <Button variant="secondary" onClick={onClose} data-autofocus>
                  {t("admin.policies.publish.cancel")}
                </Button>
                <Button
                  onClick={() => void confirm()}
                  disabled={publish.isPending}
                >
                  {publish.isPending
                    ? t("admin.policies.publish.publishing")
                    : t("admin.policies.publish.confirm")}
                </Button>
              </>
            )}
          </div>
        </DialogPanel>
      </div>
    </Dialog>
  );
}

/**
 * The Markdown editor of a draft: the effective date, a textarea and a
 * live preview through the Markdown renderer of the player. The text of a
 * policy is written by the organization, so the preview inherits the
 * language of the document.
 */
function DraftEditor({
  policyId,
  version,
  initialBody,
  onDone,
}: {
  policyId: string;
  /** The draft to change, or `null` for a new draft. */
  version: AdminPolicyVersionSummary | null;
  initialBody: string;
  onDone: (message: string | null) => void;
}) {
  const { t } = useTranslation();
  const failureText = useFailureText();
  const create = useCreateDraft();
  const update = useUpdateDraft();
  const headingId = useId();
  const bodyId = useId();
  const bodyHintId = useId();
  const bodyErrorId = useId();
  const previewId = useId();
  const [effectiveFrom, setEffectiveFrom] = useState(
    version?.effective_from ?? localToday(),
  );
  const [body, setBody] = useState(version?.body ?? initialBody);
  const [errors, setErrors] = useState<{ date?: string; body?: string }>({});
  const [formError, setFormError] = useState<string | null>(null);
  const pending = create.isPending || update.isPending;

  const save = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const found: typeof errors = {};
    if (effectiveFrom === "")
      found.date = t("admin.policies.errors.dateRequired");
    if (body.trim() === "")
      found.body = t("admin.policies.errors.bodyRequired");
    setErrors(found);
    setFormError(null);
    if (Object.keys(found).length > 0) return;
    const draft = { body, effective_from: effectiveFrom };
    try {
      const saved =
        version === null
          ? await create.mutateAsync({ policyId, draft })
          : await update.mutateAsync({ version, draft });
      onDone(t("admin.policies.editor.saved", { number: saved.number }));
    } catch (failure) {
      if (isApiError(failure, 409, "published"))
        setFormError(t("admin.policies.errors.draftPublished"));
      else if (isApiError(failure, 422))
        setFormError(t("admin.policies.errors.rejected"));
      else setFormError(failureText(failure));
    }
  };

  return (
    <section
      aria-labelledby={headingId}
      className="mt-6 rounded-lg border border-gray-300 p-4 dark:border-gray-700"
    >
      <h4 id={headingId} className="font-semibold">
        {version === null
          ? t("admin.policies.editor.newTitle")
          : t("admin.policies.editor.editTitle", { number: version.number })}
      </h4>
      <form noValidate onSubmit={(event) => void save(event)} className="mt-4">
        <div className="max-w-xs">
          <TextField
            type="date"
            label={t("admin.policies.editor.effectiveFrom")}
            errors={errors.date === undefined ? [] : [errors.date]}
            value={effectiveFrom}
            onChange={(event) => setEffectiveFrom(event.target.value)}
            required
          />
        </div>
        <div className="mt-4 grid gap-4 lg:grid-cols-2">
          <div>
            <label
              htmlFor={bodyId}
              className="block text-sm font-medium text-gray-900 dark:text-gray-100"
            >
              {t("admin.policies.editor.body")}
            </label>
            <textarea
              id={bodyId}
              value={body}
              onChange={(event) => setBody(event.target.value)}
              rows={16}
              maxLength={BODY_MAX}
              required
              aria-invalid={errors.body !== undefined ? true : undefined}
              aria-describedby={[
                bodyHintId,
                errors.body !== undefined ? bodyErrorId : null,
              ]
                .filter(Boolean)
                .join(" ")}
              className={TEXTAREA}
            />
            <p id={bodyHintId} className={`mt-1 text-sm ${MUTED}`}>
              {t("admin.policies.editor.bodyHint")}
            </p>
            {errors.body !== undefined && (
              <p id={bodyErrorId} className={FIELD_ERROR}>
                {errors.body}
              </p>
            )}
          </div>
          <section aria-labelledby={previewId}>
            <h5
              id={previewId}
              className="text-sm font-medium text-gray-900 dark:text-gray-100"
            >
              {t("admin.policies.editor.preview")}
            </h5>
            <div className="mt-1 min-h-40 rounded-md border border-dashed border-gray-400 p-4 dark:border-gray-600">
              {body.trim() === "" ? (
                <p className={`text-sm ${MUTED}`}>
                  {t("admin.policies.editor.previewEmpty")}
                </p>
              ) : (
                <Markdown lang={null}>{body}</Markdown>
              )}
            </div>
          </section>
        </div>
        <div className="mt-4 space-y-2">
          <AlertRegion>{formError}</AlertRegion>
          <div className="flex flex-wrap gap-3">
            <Button type="submit" disabled={pending}>
              {pending
                ? t("admin.policies.editor.saving")
                : t("admin.policies.editor.save")}
            </Button>
            <Button variant="secondary" onClick={() => onDone(null)}>
              {t("admin.policies.editor.cancel")}
            </Button>
          </div>
        </div>
      </form>
    </section>
  );
}

/** The versions of a policy with their state, the editor and the publish dialog. */
function Versions({
  policy,
  onStatus,
}: {
  policy: AdminPolicy;
  onStatus: (message: string) => void;
}) {
  const { t, i18n } = useTranslation();
  const versions = usePolicyVersions(policy.id);
  const headingId = useId();
  const [editing, setEditing] = useState<{
    version: AdminPolicyVersionSummary | null;
  } | null>(null);
  const [publishing, setPublishing] =
    useState<AdminPolicyVersionSummary | null>(null);

  const list = versions.data ?? [];

  let body: ReactNode;
  if (versions.isPending)
    body = <LoadingStatus text={t("admin.policies.versions.loading")} />;
  else if (versions.isError)
    body = (
      <p role="alert" className={MUTED}>
        {t("admin.policies.versions.loadFailed")}
      </p>
    );
  else if (list.length === 0)
    body = <p className={MUTED}>{t("admin.policies.versions.empty")}</p>;
  else
    body = (
      <div
        role="region"
        aria-labelledby={headingId}
        tabIndex={0}
        className={SCROLL_REGION}
      >
        <table aria-labelledby={headingId} className={TABLE}>
          <thead>
            <tr>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.policies.versions.columns.number")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.policies.versions.columns.state")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.policies.versions.columns.effectiveFrom")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.policies.versions.columns.refresher")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.policies.versions.columns.actions")}
              </th>
            </tr>
          </thead>
          <tbody>
            {list.map((version) => (
              <tr key={version.id}>
                <th scope="row" className={ROW_HEADER}>
                  {t("admin.policies.versions.number", {
                    number: version.number,
                  })}
                </th>
                <td className={CELL}>
                  <VersionState version={version} versions={list} />
                </td>
                <td className={`${CELL} whitespace-nowrap`}>
                  {formatDay(version.effective_from, i18n.language)}
                </td>
                <td className={CELL}>
                  {version.requires_refresher
                    ? t("admin.policies.versions.refresherRequired")
                    : t("admin.policies.versions.refresherNotRequired")}
                </td>
                <td className={CELL}>
                  {isDraft(version) && (
                    <div className="flex flex-wrap gap-2">
                      <Button
                        variant="secondary"
                        onClick={() => setEditing({ version })}
                      >
                        {t("admin.policies.versions.edit")}{" "}
                        <span className="sr-only">
                          {t("admin.policies.versions.number", {
                            number: version.number,
                          })}
                        </span>
                      </Button>
                      <Button onClick={() => setPublishing(version)}>
                        {t("admin.policies.versions.publish")}{" "}
                        <span className="sr-only">
                          {t("admin.policies.versions.number", {
                            number: version.number,
                          })}
                        </span>
                      </Button>
                    </div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    );

  return (
    <section className="mt-8">
      <h3 id={headingId} className="text-lg font-semibold">
        {t("admin.policies.versions.title")}
      </h3>
      <div className="mt-3">{body}</div>
      {editing === null ? (
        <div className="mt-4">
          <Button
            variant="secondary"
            disabled={versions.isPending}
            onClick={() => setEditing({ version: null })}
          >
            {t("admin.policies.versions.newDraft")}
          </Button>
        </div>
      ) : (
        <DraftEditor
          // A new editor for every version, so its fields start afresh.
          key={editing.version?.id ?? "new"}
          policyId={policy.id}
          version={editing.version}
          // A new draft starts from the text of the highest version.
          initialBody={list[0]?.body ?? ""}
          onDone={(message) => {
            setEditing(null);
            if (message !== null) onStatus(message);
          }}
        />
      )}
      {publishing !== null && (
        <PublishDialog
          version={publishing}
          versions={list}
          onClose={() => setPublishing(null)}
          onPublished={(message) => {
            setPublishing(null);
            onStatus(message);
          }}
        />
      )}
    </section>
  );
}

/** One policy: key and title, its deletion and its versions. */
function PolicyDetail({
  policy,
  onDeleted,
}: {
  policy: AdminPolicy;
  onDeleted: (message: string) => void;
}) {
  const { t } = useTranslation();
  const failureText = useFailureText();
  const update = useUpdatePolicy();
  const remove = useDeletePolicy();
  const { fromFailure } = usePolicyFieldErrors();
  const headingId = useId();
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState(false);

  const save = async (fields: AdminPolicyFields) => {
    setStatus(null);
    setError(null);
    const changed: Partial<AdminPolicyFields> = {};
    if (fields.key !== policy.key) changed.key = fields.key;
    if (fields.title !== policy.title) changed.title = fields.title;
    if (Object.keys(changed).length === 0) return null;
    try {
      await update.mutateAsync({ id: policy.id, policy: changed });
      setStatus(t("admin.policies.edit.saved"));
      return null;
    } catch (failure) {
      return fromFailure(failure);
    }
  };

  const confirmDelete = async () => {
    setDeleting(false);
    setStatus(null);
    setError(null);
    try {
      await remove.mutateAsync(policy.id);
      onDeleted(t("admin.policies.delete.deleted", { title: policy.title }));
    } catch (failure) {
      setError(
        isApiError(failure, 409, "policy_in_use")
          ? t("admin.policies.errors.policyInUse")
          : failureText(failure),
      );
    }
  };

  return (
    <section
      aria-labelledby={headingId}
      className="mt-10 rounded-lg border border-gray-200 p-4 sm:p-6 dark:border-gray-700"
    >
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {policy.title}
      </h2>
      <p className={`mt-1 font-mono text-sm ${MUTED}`}>{policy.key}</p>
      <div className="mt-4 space-y-2">
        <AlertRegion>{error}</AlertRegion>
        <StatusRegion>{status}</StatusRegion>
      </div>

      <h3 className="mt-6 text-lg font-semibold">
        {t("admin.policies.edit.title")}
      </h3>
      <PolicyForm
        // The form starts afresh after a saved change.
        key={`${policy.key} ${policy.title}`}
        initial={{ key: policy.key, title: policy.title }}
        submitLabel={t("admin.policies.edit.submit")}
        pending={update.isPending}
        onSubmit={save}
      />

      <Versions policy={policy} onStatus={setStatus} />

      <div className="mt-8 border-t border-gray-200 pt-4 dark:border-gray-700">
        <Button
          variant="danger"
          disabled={remove.isPending}
          onClick={() => setDeleting(true)}
        >
          {t("admin.policies.delete.button")}
        </Button>
      </div>
      <ConfirmDialog
        open={deleting}
        title={t("admin.policies.delete.title")}
        confirmLabel={t("admin.policies.delete.button")}
        confirmVariant="danger"
        onConfirm={() => void confirmDelete()}
        onClose={() => setDeleting(false)}
      >
        <p>{t("admin.policies.delete.text", { title: policy.title })}</p>
      </ConfirmDialog>
    </section>
  );
}

/**
 * `/admin/policies` (task 0015, step 13): the list of policies with
 * create, change and delete (409 `policy_in_use`), and for the open policy
 * its versions with their state, a Markdown editor with a live preview
 * and the publish dialog with `requires_refresher` and
 * `refresh_due_count`. The open policy stays in the query `?policy=<id>`.
 */
export function AdminPoliciesPage() {
  const { t } = useTranslation();
  const policies = useAdminPolicies();
  const create = useCreatePolicy();
  const { fromFailure } = usePolicyFieldErrors();
  const [searchParams, setSearchParams] = useSearchParams();
  const listHeadingId = useId();
  const [status, setStatus] = useState<string | null>(null);
  const [formKey, setFormKey] = useState(0);

  const selectedId = searchParams.get("policy");
  const selected = policies.data?.find((policy) => policy.id === selectedId);
  const open = (id: string | null) =>
    setSearchParams(id === null ? {} : { policy: id });

  const createPolicy = async (fields: AdminPolicyFields) => {
    setStatus(null);
    try {
      const created = await create.mutateAsync(fields);
      setFormKey((current) => current + 1);
      setStatus(t("admin.policies.create.created", { title: created.title }));
      open(created.id);
      return null;
    } catch (failure) {
      return fromFailure(failure);
    }
  };

  let list: ReactNode;
  if (policies.isPending)
    list = <LoadingStatus text={t("admin.policies.list.loading")} />;
  else if (policies.isError)
    list = (
      <p role="alert" className={MUTED}>
        {t("admin.policies.list.loadFailed")}
      </p>
    );
  else if (policies.data.length === 0)
    list = <p className={MUTED}>{t("admin.policies.list.empty")}</p>;
  else
    list = (
      <div
        role="region"
        aria-labelledby={listHeadingId}
        tabIndex={0}
        className={SCROLL_REGION}
      >
        <table aria-labelledby={listHeadingId} className={TABLE}>
          <thead>
            <tr>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.policies.list.columns.title")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.policies.list.columns.key")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.policies.list.columns.actions")}
              </th>
            </tr>
          </thead>
          <tbody>
            {policies.data.map((policy) => {
              const current = policy.id === selected?.id;
              return (
                <tr
                  key={policy.id}
                  className={
                    current ? "bg-accent-50 dark:bg-gray-800" : undefined
                  }
                >
                  <th scope="row" className={ROW_HEADER}>
                    {policy.title}
                  </th>
                  <td className={`${CELL} font-mono`}>{policy.key}</td>
                  <td className={CELL}>
                    <Button
                      variant="secondary"
                      aria-pressed={current}
                      onClick={() => {
                        setStatus(null);
                        open(policy.id);
                      }}
                    >
                      {t("admin.policies.list.open")}{" "}
                      <span className="sr-only">{policy.title}</span>
                    </Button>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    );

  return (
    <section>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.policies.title")}
      </h1>
      <p className="mt-2 max-w-3xl text-gray-700 dark:text-gray-300">
        {t("admin.policies.intro")}
      </p>
      <div className="mt-4">
        <StatusRegion>{status}</StatusRegion>
      </div>

      <section className="mt-6">
        <h2 id={listHeadingId} className="text-xl font-semibold tracking-tight">
          {t("admin.policies.list.title")}
        </h2>
        <div className="mt-3">{list}</div>
      </section>

      {selected !== undefined && (
        <PolicyDetail
          key={selected.id}
          policy={selected}
          onDeleted={(message) => {
            open(null);
            setStatus(message);
          }}
        />
      )}

      <section aria-labelledby="new-policy" className="mt-10">
        <h2 id="new-policy" className="text-xl font-semibold tracking-tight">
          {t("admin.policies.create.title")}
        </h2>
        <PolicyForm
          key={formKey}
          initial={{ key: "", title: "" }}
          submitLabel={t("admin.policies.create.submit")}
          pending={create.isPending}
          onSubmit={createPolicy}
        />
      </section>
    </section>
  );
}
