import { useQueryClient } from "@tanstack/react-query";
import { useId, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { useSearchParams } from "react-router";
import { fieldCodes, isApiError } from "../../api/admin/fieldErrors";
import { useRevokeCredential } from "../../api/admin/credentials";
import {
  useAdminUsers,
  useEndAllSessions,
  useInviteUser,
} from "../../api/admin/users";
import { sessionQueryKey } from "../../api/session";
import { ConfirmDialog } from "../../app/ConfirmDialog";
import { AlertRegion, Button, StatusRegion, TextField } from "../../app/forms";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useSession } from "../../auth/SessionProvider";
import { isUuid, useAdminErrorText } from "../adminErrors";
import { Pager } from "../adminParts";
import { UserLookup } from "./UserLookup";
import { UserTable } from "./UserTable";

const SECTION_CLASSES = "mt-10 space-y-4";
const HEADING_CLASSES = "text-xl font-semibold tracking-tight";
const TEXT_CLASSES = "max-w-3xl text-sm text-gray-700 dark:text-gray-300";

/**
 * The invitation of a local user (`POST /api/admin/users`). With
 * `LOCAL_ACCOUNTS=false` the route answers 404, so the section shows a
 * note in place of the form.
 */
function InviteSection() {
  const { t } = useTranslation();
  const { flags } = useSession();
  const errorText = useAdminErrorText();
  const invite = useInviteUser();
  const headingId = useId();
  const [email, setEmail] = useState("");
  const [displayName, setDisplayName] = useState("");
  const [sent, setSent] = useState(false);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (invite.isPending) return;
    setSent(false);
    const name = displayName.trim();
    try {
      await invite.mutateAsync({
        email: email.trim(),
        ...(name === "" ? {} : { display_name: name }),
      });
      setEmail("");
      setDisplayName("");
      setSent(true);
    } catch {
      // The form shows the error of the mutation.
    }
  };

  const failure = invite.error;
  const emailErrors =
    fieldCodes(failure, "email").length > 0
      ? [t("admin.users.invite.emailInvalid")]
      : [];
  const nameErrors =
    fieldCodes(failure, "display_name").length > 0
      ? [t("admin.users.invite.nameInvalid")]
      : [];
  let alert: string | null = null;
  if (failure !== null && emailErrors.length + nameErrors.length === 0)
    alert = isApiError(failure, 404)
      ? t("admin.users.invite.localAccountsOff")
      : errorText(failure);

  return (
    <section aria-labelledby={headingId} className={SECTION_CLASSES}>
      <h2 id={headingId} className={HEADING_CLASSES}>
        {t("admin.users.invite.title")}
      </h2>
      {flags.localAccounts ? (
        <form
          onSubmit={(event) => void submit(event)}
          className="max-w-md space-y-4"
        >
          <AlertRegion>{alert}</AlertRegion>
          <StatusRegion>
            {sent ? t("admin.users.invite.sent") : null}
          </StatusRegion>
          <TextField
            label={t("admin.users.invite.email")}
            type="email"
            name="invite-email"
            autoComplete="off"
            maxLength={160}
            required
            value={email}
            errors={emailErrors}
            onChange={(event) => setEmail(event.target.value)}
          />
          <TextField
            label={t("admin.users.invite.displayName")}
            hint={t("admin.users.invite.displayNameHint")}
            name="invite-display-name"
            autoComplete="off"
            maxLength={160}
            value={displayName}
            errors={nameErrors}
            onChange={(event) => setDisplayName(event.target.value)}
          />
          <Button type="submit" disabled={invite.isPending}>
            {t("admin.users.invite.submit")}
          </Button>
        </form>
      ) : (
        <p className={TEXT_CLASSES}>
          {t("admin.users.invite.localAccountsOff")}
        </p>
      )}
    </section>
  );
}

/** A page number of the query, from 1; anything else reads as 1. */
function pageParam(value: string | null): number {
  const page = Number(value);
  return Number.isInteger(page) && page >= 1 ? page : 1;
}

/** The paged user list (`GET /api/admin/users?page=<n>`), with `?page=` in the URL. */
function UserListSection() {
  const { t } = useTranslation();
  const headingId = useId();
  const descriptionId = useId();
  const [searchParams, setSearchParams] = useSearchParams();
  const page = pageParam(searchParams.get("page"));
  const users = useAdminUsers(page);

  let body;
  if (users.isPending) {
    body = <LoadingStatus text={t("admin.users.list.loading")} />;
  } else if (users.isError) {
    body = (
      <p role="alert" className="text-gray-700 dark:text-gray-300">
        {t("admin.common.loadFailed")}
      </p>
    );
  } else {
    const { users: entries, per_page: perPage, total } = users.data;
    const pages = Math.max(1, Math.ceil(total / perPage));
    body = (
      <>
        {entries.length === 0 ? (
          <p className="text-gray-700 dark:text-gray-300">
            {t("admin.users.list.empty")}
          </p>
        ) : (
          <UserTable
            users={entries}
            labelledBy={headingId}
            describedBy={descriptionId}
          />
        )}
        {pages > 1 && (
          <Pager
            label={t("admin.users.list.pagination")}
            page={page}
            pages={pages}
            hasNext={page < pages}
            onPage={(next) => setSearchParams({ page: String(next) })}
          />
        )}
      </>
    );
  }

  return (
    <section className={SECTION_CLASSES}>
      <h2 id={headingId} className={HEADING_CLASSES}>
        {t("admin.users.list.title")}
      </h2>
      <p id={descriptionId} className={TEXT_CLASSES}>
        {t("admin.users.list.description")}
      </p>
      {body}
    </section>
  );
}

/**
 * "End all sessions" (`DELETE /api/admin/sessions`). The confirmation
 * states that the admin's own session ends as well; afterwards the page
 * refetches the session, so the SPA moves to the sign-in.
 */
function EndAllSessionsSection() {
  const { t } = useTranslation();
  const errorText = useAdminErrorText();
  const queryClient = useQueryClient();
  const endAll = useEndAllSessions();
  const headingId = useId();
  const [open, setOpen] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const confirm = async () => {
    setOpen(false);
    setError(null);
    try {
      await endAll.mutateAsync();
      await queryClient.invalidateQueries({ queryKey: sessionQueryKey });
    } catch (failure) {
      setError(errorText(failure));
    }
  };

  return (
    <section aria-labelledby={headingId} className={SECTION_CLASSES}>
      <h2 id={headingId} className={HEADING_CLASSES}>
        {t("admin.users.endAll.title")}
      </h2>
      <p className={TEXT_CLASSES}>{t("admin.users.endAll.text")}</p>
      <AlertRegion>{error}</AlertRegion>
      <Button
        variant="danger"
        disabled={endAll.isPending}
        onClick={() => setOpen(true)}
      >
        {t("admin.users.endAll.button")}
      </Button>
      <ConfirmDialog
        open={open}
        title={t("admin.users.endAll.dialogTitle")}
        confirmLabel={t("admin.users.endAll.confirm")}
        confirmVariant="danger"
        onConfirm={() => void confirm()}
        onClose={() => setOpen(false)}
      >
        <p>{t("admin.users.endAll.dialogText")}</p>
      </ConfirmDialog>
    </section>
  );
}

/**
 * The revocation of a credential by its id
 * (`POST /api/admin/credentials/:id/revoke`) after a confirmation. Admins
 * see no credential list (README section 10).
 */
function RevokeCredentialSection() {
  const { t } = useTranslation();
  const errorText = useAdminErrorText();
  const revoke = useRevokeCredential();
  const headingId = useId();
  const [value, setValue] = useState("");
  const [invalid, setInvalid] = useState(false);
  const [confirming, setConfirming] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const id = value.trim();
    setError(null);
    setStatus(null);
    if (!isUuid(id)) {
      setInvalid(true);
      return;
    }
    setInvalid(false);
    setConfirming(id);
  };

  const confirm = async () => {
    const id = confirming;
    setConfirming(null);
    if (id === null) return;
    try {
      const revoked = await revoke.mutateAsync(id);
      setValue("");
      setStatus(
        t("admin.users.revoke.done", { code: revoked.qualification_code }),
      );
    } catch (failure) {
      setError(
        isApiError(failure, 404)
          ? t("admin.users.revoke.notFound")
          : errorText(failure),
      );
    }
  };

  return (
    <section aria-labelledby={headingId} className={SECTION_CLASSES}>
      <h2 id={headingId} className={HEADING_CLASSES}>
        {t("admin.users.revoke.title")}
      </h2>
      <p className={TEXT_CLASSES}>{t("admin.users.revoke.text")}</p>
      <form onSubmit={submit} noValidate className="max-w-md space-y-4">
        <AlertRegion>{error}</AlertRegion>
        <StatusRegion>{status}</StatusRegion>
        <TextField
          label={t("admin.users.revoke.id")}
          name="credential-id"
          autoComplete="off"
          spellCheck={false}
          maxLength={36}
          required
          value={value}
          errors={invalid ? [t("admin.common.idFormat")] : []}
          onChange={(event) => setValue(event.target.value)}
        />
        <Button type="submit" variant="danger" disabled={revoke.isPending}>
          {t("admin.users.revoke.submit")}
        </Button>
      </form>
      <ConfirmDialog
        open={confirming !== null}
        title={t("admin.users.revoke.dialogTitle")}
        confirmLabel={t("admin.users.revoke.confirm")}
        confirmVariant="danger"
        onConfirm={() => void confirm()}
        onClose={() => setConfirming(null)}
      >
        <p>{t("admin.users.revoke.dialogText", { id: confirming ?? "" })}</p>
      </ConfirmDialog>
    </section>
  );
}

/**
 * `/admin/users` (task 0015, step 12): the invitation, the lookup by exact
 * address, the paged user list with the actions per user, "End all
 * sessions" and the revocation of a credential. Every change needs a
 * second factor from the last 10 minutes; the API client opens the
 * step-up dialog when the server asks for it and repeats the request.
 */
export function UsersPage() {
  const { t } = useTranslation();
  return (
    <section>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.users.title")}
      </h1>
      <p className="mt-2 max-w-3xl text-gray-700 dark:text-gray-300">
        {t("admin.users.intro")}
      </p>
      <InviteSection />
      <UserLookup>
        {(user, headingId) => (
          <UserTable users={[user]} labelledBy={headingId} />
        )}
      </UserLookup>
      <UserListSection />
      <EndAllSessionsSection />
      <RevokeCredentialSection />
    </section>
  );
}
