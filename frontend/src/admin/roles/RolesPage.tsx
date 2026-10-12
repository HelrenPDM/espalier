import { useQueryClient } from "@tanstack/react-query";
import { useId, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  GRANTABLE_ROLES,
  useGrantHolders,
  useGrantRole,
  useRevokeGrant,
  type GrantableRole,
  type UserGrant,
} from "../../api/admin/roles";
import type { AdminUser } from "../../api/admin/users";
import { sessionQueryKey } from "../../api/session";
import { ConfirmDialog } from "../../app/ConfirmDialog";
import { AlertRegion, Button, StatusRegion } from "../../app/forms";
import { FOCUS_RING } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useSession } from "../../auth/SessionProvider";
import { useAdminErrorText } from "../adminErrors";
import { RowAction, TableFrame } from "../adminParts";
import { TABLE_CLASSES } from "../insights/reportFormat";
import { UserLookup } from "../users/UserLookup";

type Change =
  | { kind: "grant"; user: AdminUser; role: GrantableRole }
  | { kind: "remove"; user: AdminUser; grant: UserGrant };

/** The role select and "Grant" of one person. */
function AddRole({
  user,
  name,
  disabled,
  onGrant,
}: {
  user: AdminUser;
  name: string;
  disabled: boolean;
  onGrant: (role: GrantableRole) => void;
}) {
  const { t } = useTranslation();
  const selectId = useId();
  const held = new Set(
    user.grants
      .filter((grant) => grant.source === "manual")
      .map((grant) => grant.role),
  );
  const available = GRANTABLE_ROLES.filter((role) => !held.has(role));
  const [chosen, setChosen] = useState<GrantableRole | "">("");
  const role = available.find((entry) => entry === chosen) ?? available[0];

  if (role === undefined)
    return (
      <p className="text-gray-700 dark:text-gray-300">
        {t("admin.roles.allGranted")}
      </p>
    );
  return (
    <div className="flex flex-wrap items-center gap-2">
      <label htmlFor={selectId} className="sr-only">
        {t("admin.roles.role", { name })}
      </label>
      <select
        id={selectId}
        value={role}
        onChange={(event) =>
          setChosen(
            available.find((entry) => entry === event.target.value) ?? "",
          )
        }
        className={`rounded-md border border-gray-500 bg-white px-2 py-1 text-sm text-gray-900 dark:bg-gray-900 dark:text-gray-100 ${FOCUS_RING}`}
      >
        {available.map((entry) => (
          <option key={entry} value={entry}>
            {t(`admin.roles.names.${entry}`)}
          </option>
        ))}
      </select>
      <Button
        variant="secondary"
        disabled={disabled}
        aria-label={t("admin.roles.grantLabel", { name })}
        onClick={() => onGrant(role)}
      >
        {t("admin.roles.grant")}
      </Button>
    </div>
  );
}

/**
 * The people of a list or of a lookup with their grants (task 0015, step
 * 15). A `manual` grant has "Remove"; a grant of an identity provider
 * names its provider and changes only there. Adding and removing open a
 * confirmation that states that the change ends the person's sessions.
 * A change of the admin's own grants refetches the session, so the SPA
 * moves to the sign-in.
 */
function GrantTable({
  users,
  labelledBy,
  describedBy,
}: {
  users: AdminUser[];
  labelledBy: string;
  describedBy?: string;
}) {
  const { t } = useTranslation();
  const errorText = useAdminErrorText();
  const queryClient = useQueryClient();
  const session = useSession();
  const grant = useGrantRole();
  const revoke = useRevokeGrant();
  const [change, setChange] = useState<Change | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const busy = grant.isPending || revoke.isPending;

  const nameOf = (user: AdminUser) =>
    user.display_name ?? t("admin.common.noName");
  const roleName = (role: UserGrant["role"]) => t(`admin.roles.names.${role}`);
  const own = (user: AdminUser) => user.id === session.user?.id;

  const source = (entry: UserGrant) => {
    if (entry.source === "manual") return t("admin.roles.source.manual");
    return entry.provider_key === null
      ? t("admin.roles.source.idpClaimUnknown")
      : t("admin.roles.source.idpClaim", { provider: entry.provider_key });
  };

  const confirm = async () => {
    const current = change;
    setChange(null);
    if (current === null) return;
    setError(null);
    setStatus(null);
    const name = nameOf(current.user);
    try {
      if (current.kind === "grant") {
        await grant.mutateAsync({
          userId: current.user.id,
          role: current.role,
        });
        setStatus(
          t("admin.roles.granted", { name, role: roleName(current.role) }),
        );
      } else {
        await revoke.mutateAsync(current.grant.id);
        setStatus(
          t("admin.roles.removed", {
            name,
            role: roleName(current.grant.role),
          }),
        );
      }
      if (own(current.user))
        await queryClient.invalidateQueries({ queryKey: sessionQueryKey });
    } catch (failure) {
      setError(errorText(failure));
    }
  };

  const changeName = change === null ? "" : nameOf(change.user);
  const changeRole =
    change === null
      ? ""
      : roleName(change.kind === "grant" ? change.role : change.grant.role);

  return (
    <div className="space-y-3">
      <AlertRegion>{error}</AlertRegion>
      <StatusRegion>{status}</StatusRegion>
      <TableFrame labelledBy={labelledBy} describedBy={describedBy}>
        <thead>
          <tr>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.roles.holders.person")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.roles.holders.grants")}
            </th>
            <th scope="col" className={TABLE_CLASSES.columnHeader}>
              {t("admin.roles.holders.add")}
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
                </th>
                <td className={TABLE_CLASSES.cell}>
                  {user.grants.length === 0 ? (
                    t("admin.common.none")
                  ) : (
                    <ul className="space-y-1">
                      {user.grants.map((entry) => (
                        <li
                          key={entry.id}
                          className="flex flex-wrap items-baseline gap-x-2"
                        >
                          <span>
                            {roleName(entry.role)}{" "}
                            <span className="text-xs text-gray-600 dark:text-gray-400">
                              ({source(entry)})
                            </span>
                          </span>
                          {entry.source === "manual" && (
                            <RowAction
                              aria-label={t("admin.roles.removeLabel", {
                                name,
                                role: roleName(entry.role),
                              })}
                              danger
                              disabled={busy}
                              onClick={() =>
                                setChange({
                                  kind: "remove",
                                  user,
                                  grant: entry,
                                })
                              }
                            >
                              {t("admin.roles.remove")}
                            </RowAction>
                          )}
                        </li>
                      ))}
                    </ul>
                  )}
                </td>
                <td className={TABLE_CLASSES.cell}>
                  <AddRole
                    user={user}
                    name={name}
                    disabled={busy}
                    onGrant={(role) => setChange({ kind: "grant", user, role })}
                  />
                </td>
              </tr>
            );
          })}
        </tbody>
      </TableFrame>
      <ConfirmDialog
        open={change !== null}
        title={
          change?.kind === "remove"
            ? t("admin.roles.removeDialog.title")
            : t("admin.roles.grantDialog.title")
        }
        confirmLabel={
          change?.kind === "remove"
            ? t("admin.roles.remove")
            : t("admin.roles.grant")
        }
        confirmVariant={change?.kind === "remove" ? "danger" : "primary"}
        onConfirm={() => void confirm()}
        onClose={() => setChange(null)}
      >
        <p>
          {change?.kind === "remove"
            ? t("admin.roles.removeDialog.text", {
                name: changeName,
                role: changeRole,
              })
            : t("admin.roles.grantDialog.text", {
                name: changeName,
                role: changeRole,
              })}
        </p>
        <p>{t("admin.roles.endsSessions")}</p>
        {change !== null && own(change.user) && <p>{t("admin.roles.own")}</p>}
      </ConfirmDialog>
    </div>
  );
}

/** The users with a grant beyond `learner` (`GET /api/admin/role-grants`). */
function HoldersSection() {
  const { t } = useTranslation();
  const headingId = useId();
  const descriptionId = useId();
  const holders = useGrantHolders();

  let body;
  if (holders.isPending) {
    body = <LoadingStatus text={t("admin.roles.holders.loading")} />;
  } else if (holders.isError) {
    body = (
      <p role="alert" className="text-gray-700 dark:text-gray-300">
        {t("admin.common.loadFailed")}
      </p>
    );
  } else if (holders.data.length === 0) {
    body = (
      <p className="text-gray-700 dark:text-gray-300">
        {t("admin.roles.holders.empty")}
      </p>
    );
  } else {
    body = (
      <GrantTable
        users={holders.data}
        labelledBy={headingId}
        describedBy={descriptionId}
      />
    );
  }

  return (
    <section className="mt-10 space-y-4">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.roles.holders.title")}
      </h2>
      <p
        id={descriptionId}
        className="max-w-3xl text-sm text-gray-700 dark:text-gray-300"
      >
        {t("admin.roles.holders.description")}
      </p>
      {body}
    </section>
  );
}

/**
 * `/admin/roles` (task 0015, step 15): the lookup by exact address, the
 * users with grants, and adding and removing `manual` grants. Names cannot
 * be searched, because the display name is encrypted (README section 6.9).
 */
export function RolesPage() {
  const { t } = useTranslation();
  return (
    <section>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.roles.title")}
      </h1>
      <p className="mt-2 max-w-3xl text-gray-700 dark:text-gray-300">
        {t("admin.roles.intro")}
      </p>
      <UserLookup>
        {(user, headingId) => (
          <GrantTable users={[user]} labelledBy={headingId} />
        )}
      </UserLookup>
      <HoldersSection />
    </section>
  );
}
