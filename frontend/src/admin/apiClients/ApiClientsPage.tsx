import { useId, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import {
  API_CLIENT_SCOPES,
  useAdminApiClients,
  useCreateApiClient,
  useDeleteApiClient,
  type AdminApiClient,
  type AdminApiClientCreated,
  type ApiClientScope,
} from "../../api/admin/apiClients";
import { fieldCodes } from "../../api/admin/fieldErrors";
import { ConfirmDialog } from "../../app/ConfirmDialog";
import { formatDateTime } from "../../app/format";
import {
  AlertRegion,
  Button,
  FocusHeading,
  StatusRegion,
  TextField,
} from "../../app/forms";
import { FOCUS_RING } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useAdminErrorText } from "../adminErrors";
import { CheckboxField, RowAction, TableFrame } from "../adminParts";
import { TABLE_CLASSES } from "../insights/reportFormat";

const SCOPE_KEYS = {
  "credentials:read": "admin.apiClients.scopeNames.credentialsRead",
} as const satisfies Record<ApiClientScope, string>;

/**
 * The token of a new client, shown once with a copy button (task 0015,
 * step 16). It lives in the state of the page only; "Done" removes it and
 * resets the mutation that returned it.
 */
function TokenPanel({
  created,
  onDone,
}: {
  created: AdminApiClientCreated;
  onDone: () => void;
}) {
  const { t } = useTranslation();
  const tokenId = useId();
  const [status, setStatus] = useState<string | null>(null);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(created.token);
      setStatus(t("admin.common.copied"));
    } catch {
      setStatus(t("admin.common.copyFailed"));
    }
  };

  return (
    <section className="mt-6 max-w-2xl space-y-4 rounded-lg border border-accent-600 p-4 dark:border-accent-500">
      <FocusHeading level={2}>
        {t("admin.apiClients.token.title", { name: created.client.name })}
      </FocusHeading>
      <p className="text-sm text-gray-700 dark:text-gray-300">
        {t("admin.apiClients.token.text")}
      </p>
      <div>
        <label
          htmlFor={tokenId}
          className="block text-sm font-medium text-gray-900 dark:text-gray-100"
        >
          {t("admin.apiClients.token.label")}
        </label>
        <input
          id={tokenId}
          readOnly
          value={created.token}
          spellCheck={false}
          autoComplete="off"
          onFocus={(event) => event.target.select()}
          className={`mt-1 block w-full rounded-md border border-gray-500 bg-gray-50 px-3 py-2 font-mono text-sm text-gray-900 dark:bg-gray-800 dark:text-gray-100 ${FOCUS_RING}`}
        />
      </div>
      <div className="flex flex-wrap gap-3">
        <Button variant="secondary" onClick={() => void copy()}>
          {t("admin.apiClients.token.copy")}
        </Button>
        <Button onClick={onDone}>{t("admin.apiClients.token.done")}</Button>
      </div>
      <StatusRegion>{status}</StatusRegion>
    </section>
  );
}

/** The form of a new client: a name and its scopes. */
function CreateSection({
  onCreated,
}: {
  onCreated: (created: AdminApiClientCreated) => void;
}) {
  const { t } = useTranslation();
  const errorText = useAdminErrorText();
  const create = useCreateApiClient();
  const headingId = useId();
  const [name, setName] = useState("");
  const [scopes, setScopes] = useState<ApiClientScope[]>([
    ...API_CLIENT_SCOPES,
  ]);
  const [nameInvalid, setNameInvalid] = useState(false);
  const [scopesInvalid, setScopesInvalid] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (create.isPending) return;
    const trimmed = name.trim();
    const badName = trimmed === "" || trimmed.length > 100;
    setNameInvalid(badName);
    setScopesInvalid(scopes.length === 0);
    if (badName || scopes.length === 0) return;
    try {
      const created = await create.mutateAsync({ name: trimmed, scopes });
      create.reset();
      setName("");
      onCreated(created);
    } catch {
      // The form shows the error of the mutation.
    }
  };

  const failure = create.error;
  const serverNameInvalid = fieldCodes(failure, "name").length > 0;
  const serverScopesInvalid = fieldCodes(failure, "scopes").length > 0;
  const alert =
    failure !== null && !serverNameInvalid && !serverScopesInvalid
      ? errorText(failure)
      : null;

  return (
    <section aria-labelledby={headingId} className="mt-10 space-y-4">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.apiClients.create.title")}
      </h2>
      <form
        onSubmit={(event) => void submit(event)}
        noValidate
        className="max-w-md space-y-4"
      >
        <AlertRegion>{alert}</AlertRegion>
        <TextField
          label={t("admin.apiClients.create.name")}
          hint={t("admin.apiClients.create.nameHint")}
          name="api-client-name"
          autoComplete="off"
          maxLength={100}
          required
          value={name}
          errors={
            nameInvalid || serverNameInvalid
              ? [t("admin.apiClients.create.nameInvalid")]
              : []
          }
          onChange={(event) => setName(event.target.value)}
        />
        <fieldset className="space-y-2">
          <legend className="text-sm font-medium text-gray-900 dark:text-gray-100">
            {t("admin.apiClients.create.scopes")}
          </legend>
          {API_CLIENT_SCOPES.map((scope) => (
            <CheckboxField
              key={scope}
              name="scopes"
              value={scope}
              label={t(SCOPE_KEYS[scope])}
              checked={scopes.includes(scope)}
              onChange={(checked) =>
                setScopes((current) =>
                  checked
                    ? [...current, scope]
                    : current.filter((entry) => entry !== scope),
                )
              }
            />
          ))}
          {(scopesInvalid || serverScopesInvalid) && (
            <p className="text-sm text-red-700 dark:text-red-300">
              {t("admin.apiClients.create.scopeRequired")}
            </p>
          )}
        </fieldset>
        <Button type="submit" disabled={create.isPending}>
          {t("admin.apiClients.create.submit")}
        </Button>
      </form>
    </section>
  );
}

/** The list of clients with "Delete" behind a confirmation. */
function ClientList() {
  const { t, i18n } = useTranslation();
  const errorText = useAdminErrorText();
  const clients = useAdminApiClients();
  const remove = useDeleteApiClient();
  const headingId = useId();
  const [deleting, setDeleting] = useState<AdminApiClient | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const confirm = async () => {
    const client = deleting;
    setDeleting(null);
    if (client === null) return;
    setError(null);
    setStatus(null);
    try {
      await remove.mutateAsync(client.id);
      setStatus(t("admin.apiClients.deleted", { name: client.name }));
    } catch (failure) {
      setError(errorText(failure));
    }
  };

  let body;
  if (clients.isPending) {
    body = <LoadingStatus text={t("admin.apiClients.list.loading")} />;
  } else if (clients.isError) {
    body = (
      <p role="alert" className="text-gray-700 dark:text-gray-300">
        {t("admin.common.loadFailed")}
      </p>
    );
  } else if (clients.data.length === 0) {
    body = (
      <p className="text-gray-700 dark:text-gray-300">
        {t("admin.apiClients.list.empty")}
      </p>
    );
  } else {
    body = (
      <TableFrame labelledBy={headingId}>
        <thead>
          <tr>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.apiClients.list.name")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.apiClients.list.scopes")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.apiClients.list.created")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.apiClients.list.lastUsed")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.apiClients.list.actions")}
            </th>
          </tr>
        </thead>
        <tbody>
          {clients.data.map((client) => (
            <tr key={client.id}>
              <th scope="row" className={TABLE_CLASSES.rowHeader}>
                {client.name}
              </th>
              <td className={`${TABLE_CLASSES.cell} font-mono`}>
                {client.scopes.join(", ")}
              </td>
              <td className={TABLE_CLASSES.cell}>
                {formatDateTime(client.inserted_at, i18n.language)}
              </td>
              <td className={TABLE_CLASSES.cell}>
                {client.last_used_at === null
                  ? t("admin.common.never")
                  : formatDateTime(client.last_used_at, i18n.language)}
              </td>
              <td className={TABLE_CLASSES.cell}>
                <RowAction
                  subject={client.name}
                  danger
                  disabled={remove.isPending}
                  onClick={() => setDeleting(client)}
                >
                  {t("admin.apiClients.delete")}
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
        {t("admin.apiClients.list.title")}
      </h2>
      <AlertRegion>{error}</AlertRegion>
      <StatusRegion>{status}</StatusRegion>
      {body}
      <ConfirmDialog
        open={deleting !== null}
        title={t("admin.apiClients.deleteDialog.title")}
        confirmLabel={t("admin.apiClients.delete")}
        confirmVariant="danger"
        onConfirm={() => void confirm()}
        onClose={() => setDeleting(null)}
      >
        <p>
          {t("admin.apiClients.deleteDialog.text", {
            name: deleting?.name ?? "",
          })}
        </p>
      </ConfirmDialog>
    </section>
  );
}

/**
 * `/admin/api-clients` (task 0015, step 16): create a machine client and
 * show its token once with a copy button, list the clients and delete
 * one. While the token is shown, the panel takes the place of the form.
 */
export function ApiClientsPage() {
  const { t } = useTranslation();
  const [created, setCreated] = useState<AdminApiClientCreated | null>(null);
  return (
    <section>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.apiClients.title")}
      </h1>
      <p className="mt-2 max-w-3xl text-gray-700 dark:text-gray-300">
        {t("admin.apiClients.intro")}
      </p>
      {created === null ? (
        <CreateSection onCreated={setCreated} />
      ) : (
        <TokenPanel created={created} onDone={() => setCreated(null)} />
      )}
      <ClientList />
    </section>
  );
}
