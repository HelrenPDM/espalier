import { useQueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import {
  useDisableUser,
  useEndUserSessions,
  useResendInvitation,
  useResetFactors,
  useResetFailureCounters,
  type AdminUser,
} from "../../api/admin/users";
import { sessionQueryKey } from "../../api/session";
import { ConfirmDialog } from "../../app/ConfirmDialog";
import { formatDateTime } from "../../app/format";
import { AlertRegion, StatusRegion } from "../../app/forms";
import { useSession } from "../../auth/SessionProvider";
import { useAdminErrorText } from "../adminErrors";
import { RowAction, TableFrame } from "../adminParts";
import { TABLE_CLASSES } from "../insights/reportFormat";
import { ResetFactorsDialog } from "./ResetFactorsDialog";

type ConfirmedAction = "disable" | "endSessions" | "resetFactors";

/**
 * "Resend invitation" fits a local account that has not enrolled a second
 * factor; the server refuses every other user with 409 `not_invitable`.
 */
const invitable = (user: AdminUser) =>
  user.status === "active" && !user.enrolled && user.provider_keys.length === 0;

/**
 * The users of a page or of a lookup (task 0015, step 12) with status,
 * roles, linked providers and last sign-in, and the actions per user:
 * "Resend invitation", "Disable" and "End sessions" with a confirmation,
 * "Reset second factors" with the identity check of decision D11, and
 * "Reset failure counters". "Disable" and "Reset second factors" are
 * missing on the admin's own row, where the server answers 409
 * `own_account`. Ending the own sessions refetches the session, so the
 * SPA moves to the sign-in.
 */
export function UserTable({
  users,
  labelledBy,
  describedBy,
}: {
  users: AdminUser[];
  labelledBy: string;
  describedBy?: string;
}) {
  const { t, i18n } = useTranslation();
  const errorText = useAdminErrorText();
  const queryClient = useQueryClient();
  const session = useSession();
  const resend = useResendInvitation();
  const disable = useDisableUser();
  const endSessions = useEndUserSessions();
  const resetFactors = useResetFactors();
  const resetCounters = useResetFailureCounters();
  const [confirming, setConfirming] = useState<{
    action: ConfirmedAction;
    user: AdminUser;
  } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const busy =
    resend.isPending ||
    disable.isPending ||
    endSessions.isPending ||
    resetFactors.isPending ||
    resetCounters.isPending;

  const nameOf = (user: AdminUser) =>
    user.display_name ?? t("admin.common.noName");
  const own = (user: AdminUser) => user.id === session.user?.id;

  const run = async (action: () => Promise<string>) => {
    setError(null);
    setStatus(null);
    try {
      setStatus(await action());
    } catch (failure) {
      setError(errorText(failure));
    }
  };

  const confirm = () => {
    const current = confirming;
    setConfirming(null);
    if (current === null) return;
    const { action, user } = current;
    const name = nameOf(user);
    if (action === "disable")
      void run(async () => {
        await disable.mutateAsync(user.id);
        return t("admin.users.done.disabled", { name });
      });
    if (action === "endSessions")
      void run(async () => {
        await endSessions.mutateAsync(user.id);
        if (own(user))
          await queryClient.invalidateQueries({ queryKey: sessionQueryKey });
        return t("admin.users.done.sessionsEnded", { name });
      });
    if (action === "resetFactors")
      void run(async () => {
        const result = await resetFactors.mutateAsync(user.id);
        return result.invitation_sent
          ? t("admin.users.done.factorsResetInvited", { name })
          : t("admin.users.done.factorsReset", { name });
      });
  };

  const confirmingName = confirming === null ? "" : nameOf(confirming.user);

  return (
    <div className="space-y-3">
      <AlertRegion>{error}</AlertRegion>
      <StatusRegion>{status}</StatusRegion>
      <TableFrame labelledBy={labelledBy} describedBy={describedBy}>
        <thead>
          <tr>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.users.list.name")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.users.list.status")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.users.list.roles")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.users.list.providers")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.users.list.lastSignIn")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.users.list.actions")}
            </th>
          </tr>
        </thead>
        <tbody>
          {users.map((user) => {
            const name = nameOf(user);
            return (
              <tr key={user.id}>
                <th scope="row" className={TABLE_CLASSES.rowHeader}>
                  {name}
                  {own(user) && (
                    <span className="ml-2 rounded bg-gray-100 px-2 py-0.5 text-xs font-normal dark:bg-gray-800">
                      {t("admin.users.list.you")}
                    </span>
                  )}
                </th>
                <td className={TABLE_CLASSES.cell}>
                  {t(`admin.users.status.${user.status}`)}
                  {!user.enrolled && (
                    <span className="block text-xs text-gray-600 dark:text-gray-400">
                      {t("admin.users.list.notEnrolled")}
                    </span>
                  )}
                </td>
                <td className={TABLE_CLASSES.cell}>
                  {user.roles
                    .map((role) => t(`admin.roles.names.${role}`))
                    .join(", ")}
                </td>
                <td className={TABLE_CLASSES.cell}>
                  {user.provider_keys.length === 0
                    ? t("admin.common.none")
                    : user.provider_keys.join(", ")}
                </td>
                <td className={TABLE_CLASSES.cell}>
                  {user.last_login_at === null
                    ? t("admin.common.never")
                    : formatDateTime(user.last_login_at, i18n.language)}
                </td>
                <td className={TABLE_CLASSES.cell}>
                  <div className="flex flex-col items-start gap-1">
                    {invitable(user) && (
                      <RowAction
                        subject={name}
                        disabled={busy}
                        onClick={() =>
                          void run(async () => {
                            await resend.mutateAsync(user.id);
                            return t("admin.users.done.invitationResent", {
                              name,
                            });
                          })
                        }
                      >
                        {t("admin.users.actions.resendInvitation")}
                      </RowAction>
                    )}
                    <RowAction
                      subject={name}
                      disabled={busy}
                      onClick={() =>
                        setConfirming({ action: "endSessions", user })
                      }
                    >
                      {t("admin.users.actions.endSessions")}
                    </RowAction>
                    <RowAction
                      subject={name}
                      disabled={busy}
                      onClick={() =>
                        void run(async () => {
                          await resetCounters.mutateAsync(user.id);
                          return t("admin.users.done.countersReset", { name });
                        })
                      }
                    >
                      {t("admin.users.actions.resetCounters")}
                    </RowAction>
                    {!own(user) && (
                      <RowAction
                        subject={name}
                        danger
                        disabled={busy}
                        onClick={() =>
                          setConfirming({ action: "resetFactors", user })
                        }
                      >
                        {t("admin.users.actions.resetFactors")}
                      </RowAction>
                    )}
                    {!own(user) && user.status === "active" && (
                      <RowAction
                        subject={name}
                        danger
                        disabled={busy}
                        onClick={() =>
                          setConfirming({ action: "disable", user })
                        }
                      >
                        {t("admin.users.actions.disable")}
                      </RowAction>
                    )}
                  </div>
                </td>
              </tr>
            );
          })}
        </tbody>
      </TableFrame>
      <ConfirmDialog
        open={confirming?.action === "disable"}
        title={t("admin.users.disableDialog.title")}
        confirmLabel={t("admin.users.actions.disable")}
        confirmVariant="danger"
        onConfirm={confirm}
        onClose={() => setConfirming(null)}
      >
        <p>{t("admin.users.disableDialog.text", { name: confirmingName })}</p>
      </ConfirmDialog>
      <ConfirmDialog
        open={confirming?.action === "endSessions"}
        title={t("admin.users.endSessionsDialog.title")}
        confirmLabel={t("admin.users.actions.endSessions")}
        confirmVariant="danger"
        onConfirm={confirm}
        onClose={() => setConfirming(null)}
      >
        <p>
          {t("admin.users.endSessionsDialog.text", { name: confirmingName })}
        </p>
        {confirming !== null && own(confirming.user) && (
          <p>{t("admin.users.endSessionsDialog.own")}</p>
        )}
      </ConfirmDialog>
      <ResetFactorsDialog
        name={confirming?.action === "resetFactors" ? confirmingName : null}
        onConfirm={confirm}
        onClose={() => setConfirming(null)}
      />
    </div>
  );
}
