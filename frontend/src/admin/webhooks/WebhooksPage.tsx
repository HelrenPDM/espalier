import { useId, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { fieldCodes, isApiError } from "../../api/admin/fieldErrors";
import {
  WEBHOOK_EVENTS,
  useAdminWebhooks,
  useCreateWebhook,
  useDeleteWebhook,
  type AdminWebhook,
  type WebhookEvent,
} from "../../api/admin/webhooks";
import { ConfirmDialog } from "../../app/ConfirmDialog";
import { AlertRegion, Button, StatusRegion, TextField } from "../../app/forms";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useAdminErrorText } from "../adminErrors";
import { CheckboxField, RowAction, TableFrame } from "../adminParts";
import { TABLE_CLASSES } from "../insights/reportFormat";

const EVENT_KEYS = {
  "credential.issued": "admin.webhooks.events.issued",
  "credential.refresh_due": "admin.webhooks.events.refreshDue",
  "credential.expired": "admin.webhooks.events.expired",
  "credential.revoked": "admin.webhooks.events.revoked",
} as const satisfies Record<WebhookEvent, string>;

const URL_MAX_LENGTH = 255;
const SECRET_ENV = /^WEBHOOK_SECRET_[A-Z0-9_]+$/;

type UrlProblem = "urlInvalid" | "urlHttps" | "urlTooLong" | "hostNotAllowed";
type SecretProblem = "secretPrefix" | "secretUnset";

/**
 * The check of the receiver URL before the request, as the `Webhook`
 * changeset of task 0013 checks it: at most 255 characters, no user
 * information, and `https`, or `http` only in a development build, where
 * the server sets `:webhook_allow_http` as well. The host list of
 * `WEBHOOK_ALLOWED_HOSTS` stays on the server.
 */
function urlProblem(value: string): UrlProblem | null {
  if (value.length > URL_MAX_LENGTH) return "urlTooLong";
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return "urlInvalid";
  }
  if (url.hostname === "" || url.username !== "" || url.password !== "")
    return "urlInvalid";
  if (url.protocol === "https:") return null;
  if (url.protocol === "http:" && import.meta.env.DEV) return null;
  return "urlHttps";
}

/** The problem of a 422 answer on `url`, by the codes of the changeset. */
function serverUrlProblem(codes: string[]): UrlProblem | null {
  if (codes.length === 0) return null;
  if (codes.includes("host_not_allowed")) return "hostNotAllowed";
  if (codes.includes("scheme")) return "urlHttps";
  if (codes.includes("length")) return "urlTooLong";
  return "urlInvalid";
}

/**
 * The form of a new webhook (task 0015, step 16). It checks the URL scheme
 * and the prefix `WEBHOOK_SECRET_` of the secret variable before it sends
 * the request, and it shows `host_not_allowed` at the URL field and
 * `secret_env_unset` at the secret field.
 */
function CreateSection() {
  const { t } = useTranslation();
  const errorText = useAdminErrorText();
  const create = useCreateWebhook();
  const headingId = useId();
  const [url, setUrl] = useState("");
  const [events, setEvents] = useState<WebhookEvent[]>([...WEBHOOK_EVENTS]);
  const [secretEnv, setSecretEnv] = useState("");
  const [active, setActive] = useState(true);
  const [checked, setChecked] = useState<{
    url: UrlProblem | null;
    secret: SecretProblem | null;
    events: boolean;
  }>({ url: null, secret: null, events: false });
  const [created, setCreated] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (create.isPending) return;
    setCreated(false);
    create.reset();
    const trimmedUrl = url.trim();
    const trimmedSecret = secretEnv.trim();
    const next = {
      url: urlProblem(trimmedUrl),
      secret: SECRET_ENV.test(trimmedSecret) ? null : ("secretPrefix" as const),
      events: events.length === 0,
    };
    setChecked(next);
    if (next.url !== null || next.secret !== null || next.events) return;
    try {
      await create.mutateAsync({
        url: trimmedUrl,
        events,
        secret_env: trimmedSecret,
        active,
      });
      setUrl("");
      setSecretEnv("");
      setEvents([...WEBHOOK_EVENTS]);
      setActive(true);
      setCreated(true);
    } catch {
      // The form shows the error of the mutation.
    }
  };

  const failure = create.error;
  const urlError = checked.url ?? serverUrlProblem(fieldCodes(failure, "url"));
  const secretError: SecretProblem | null =
    checked.secret ??
    (isApiError(failure, 422, "secret_env_unset")
      ? "secretUnset"
      : fieldCodes(failure, "secret_env").length > 0
        ? "secretPrefix"
        : null);
  const eventsError =
    checked.events || fieldCodes(failure, "events").length > 0;
  const fieldError = urlError !== null || secretError !== null || eventsError;
  const alert = failure !== null && !fieldError ? errorText(failure) : null;

  return (
    <section aria-labelledby={headingId} className="mt-10 space-y-4">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.webhooks.create.title")}
      </h2>
      <form
        onSubmit={(event) => void submit(event)}
        noValidate
        className="max-w-xl space-y-4"
      >
        <AlertRegion>{alert}</AlertRegion>
        <StatusRegion>
          {created ? t("admin.webhooks.created") : null}
        </StatusRegion>
        <TextField
          label={t("admin.webhooks.create.url")}
          hint={t("admin.webhooks.create.urlHint")}
          type="url"
          name="webhook-url"
          inputMode="url"
          autoComplete="off"
          spellCheck={false}
          required
          value={url}
          errors={
            urlError === null ? [] : [t(`admin.webhooks.errors.${urlError}`)]
          }
          onChange={(event) => setUrl(event.target.value)}
        />
        <fieldset className="space-y-2">
          <legend className="text-sm font-medium text-gray-900 dark:text-gray-100">
            {t("admin.webhooks.create.events")}
          </legend>
          {WEBHOOK_EVENTS.map((entry) => (
            <CheckboxField
              key={entry}
              name="events"
              value={entry}
              label={t(EVENT_KEYS[entry])}
              checked={events.includes(entry)}
              onChange={(on) =>
                setEvents((current) =>
                  on
                    ? WEBHOOK_EVENTS.filter(
                        (value) => value === entry || current.includes(value),
                      )
                    : current.filter((value) => value !== entry),
                )
              }
            />
          ))}
          {eventsError && (
            <p className="text-sm text-red-700 dark:text-red-300">
              {t("admin.webhooks.errors.eventsRequired")}
            </p>
          )}
        </fieldset>
        <TextField
          label={t("admin.webhooks.create.secretEnv")}
          hint={t("admin.webhooks.create.secretEnvHint")}
          name="webhook-secret-env"
          autoComplete="off"
          autoCapitalize="characters"
          spellCheck={false}
          maxLength={255}
          required
          value={secretEnv}
          errors={
            secretError === null
              ? []
              : [t(`admin.webhooks.errors.${secretError}`)]
          }
          onChange={(event) => setSecretEnv(event.target.value)}
        />
        <CheckboxField
          label={t("admin.webhooks.create.active")}
          checked={active}
          onChange={setActive}
        />
        <Button type="submit" disabled={create.isPending}>
          {t("admin.webhooks.create.submit")}
        </Button>
      </form>
    </section>
  );
}

/** The list of webhooks with "Delete" behind a confirmation. */
function WebhookList() {
  const { t } = useTranslation();
  const errorText = useAdminErrorText();
  const webhooks = useAdminWebhooks();
  const remove = useDeleteWebhook();
  const headingId = useId();
  const [deleting, setDeleting] = useState<AdminWebhook | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const eventName = (value: string) =>
    Object.hasOwn(EVENT_KEYS, value)
      ? t(EVENT_KEYS[value as WebhookEvent])
      : value;

  const confirm = async () => {
    const webhook = deleting;
    setDeleting(null);
    if (webhook === null) return;
    setError(null);
    setStatus(null);
    try {
      await remove.mutateAsync(webhook.id);
      setStatus(t("admin.webhooks.deleted"));
    } catch (failure) {
      setError(errorText(failure));
    }
  };

  let body;
  if (webhooks.isPending) {
    body = <LoadingStatus text={t("admin.webhooks.list.loading")} />;
  } else if (webhooks.isError) {
    body = (
      <p role="alert" className="text-gray-700 dark:text-gray-300">
        {t("admin.common.loadFailed")}
      </p>
    );
  } else if (webhooks.data.length === 0) {
    body = (
      <p className="text-gray-700 dark:text-gray-300">
        {t("admin.webhooks.list.empty")}
      </p>
    );
  } else {
    body = (
      <TableFrame labelledBy={headingId}>
        <thead>
          <tr>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.webhooks.list.url")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.webhooks.list.events")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.webhooks.list.secretEnv")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.webhooks.list.status")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.webhooks.list.actions")}
            </th>
          </tr>
        </thead>
        <tbody>
          {webhooks.data.map((webhook) => (
            <tr key={webhook.id}>
              <th
                scope="row"
                className={`${TABLE_CLASSES.rowHeader} break-all`}
              >
                {webhook.url}
              </th>
              <td className={TABLE_CLASSES.cell}>
                <ul>
                  {webhook.events.map((entry) => (
                    <li key={entry}>{eventName(entry)}</li>
                  ))}
                </ul>
              </td>
              <td className={`${TABLE_CLASSES.cell} font-mono`}>
                {webhook.secret_env}
              </td>
              <td className={TABLE_CLASSES.cell}>
                {webhook.active
                  ? t("admin.webhooks.state.active")
                  : t("admin.webhooks.state.inactive")}
              </td>
              <td className={TABLE_CLASSES.cell}>
                <RowAction
                  subject={webhook.url}
                  danger
                  disabled={remove.isPending}
                  onClick={() => setDeleting(webhook)}
                >
                  {t("admin.webhooks.delete")}
                </RowAction>
              </td>
            </tr>
          ))}
        </tbody>
      </TableFrame>
    );
  }

  return (
    <section className="mt-10 space-y-4">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.webhooks.list.title")}
      </h2>
      <AlertRegion>{error}</AlertRegion>
      <StatusRegion>{status}</StatusRegion>
      {body}
      <ConfirmDialog
        open={deleting !== null}
        title={t("admin.webhooks.deleteDialog.title")}
        confirmLabel={t("admin.webhooks.delete")}
        confirmVariant="danger"
        onConfirm={() => void confirm()}
        onClose={() => setDeleting(null)}
      >
        <p className="break-all">
          {t("admin.webhooks.deleteDialog.text", { url: deleting?.url ?? "" })}
        </p>
      </ConfirmDialog>
    </section>
  );
}

/**
 * `/admin/webhooks` (task 0015, step 16): add a receiver of the four
 * credential events, list the receivers and delete one. The signing secret
 * stays in the environment of the server; the page names its variable.
 */
export function WebhooksPage() {
  const { t } = useTranslation();
  return (
    <section>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.webhooks.title")}
      </h1>
      <p className="mt-2 max-w-3xl text-gray-700 dark:text-gray-300">
        {t("admin.webhooks.intro")}
      </p>
      <CreateSection />
      <WebhookList />
    </section>
  );
}
