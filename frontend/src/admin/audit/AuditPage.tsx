import { useId, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { useSearchParams } from "react-router";
import { useAuditEvents, type AdminAuditEvent } from "../../api/admin/audit";
import { formatDateTime } from "../../app/format";
import { Button, TextField } from "../../app/forms";
import { LoadingStatus } from "../../app/LoadingStatus";
import { isUuid } from "../adminErrors";
import { Pager, RowAction, TableFrame } from "../adminParts";
import { TABLE_CLASSES } from "../insights/reportFormat";

/**
 * The actions that the platform records, offered as suggestions of the
 * action filter. The filter also takes any other exact action.
 */
const KNOWN_ACTIONS = [
  "user.invited",
  "user.invitation_resent",
  "user.signed_up",
  "user.disabled",
  "user.factors_reset",
  "user.failure_counters_reset",
  "failure_counter.reset",
  "sessions.ended",
  "sessions.ended_all",
  "role.granted",
  "role.revoked",
  "role.synced",
  "api_client.created",
  "api_client.deleted",
  "webhook.created",
  "webhook.updated",
  "webhook.deleted",
  "policy.created",
  "policy.updated",
  "policy.deleted",
  "policy_version.created",
  "policy_version.updated",
  "policy_version.published",
  "approved_tool.created",
  "approved_tool.updated",
  "approved_tool.deleted",
  "credential.revoked",
  "attendance.issued",
  "pack.imported",
  "pack.published",
] as const;

interface Filters {
  action: string;
  actorId: string;
}

/** A page number of the query, from 1; anything else reads as 1. */
function pageParam(value: string | null): number {
  const page = Number(value);
  return Number.isInteger(page) && page >= 1 ? page : 1;
}

/**
 * The filters by action and actor id. The fields start from the filters of
 * the URL; "Apply filters" writes them into the URL and returns to page 1.
 */
function FilterForm({
  filters,
  onApply,
}: {
  filters: Filters;
  onApply: (filters: Filters) => void;
}) {
  const { t } = useTranslation();
  const headingId = useId();
  const actionsId = useId();
  const [action, setAction] = useState(filters.action);
  const [actorId, setActorId] = useState(filters.actorId);
  const [actorInvalid, setActorInvalid] = useState(false);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    const next = { action: action.trim(), actorId: actorId.trim() };
    const invalid = next.actorId !== "" && !isUuid(next.actorId);
    setActorInvalid(invalid);
    if (!invalid) onApply(next);
  };

  return (
    <section aria-labelledby={headingId} className="mt-8 space-y-4">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.audit.filters.title")}
      </h2>
      <form
        onSubmit={submit}
        noValidate
        className="grid max-w-3xl gap-4 sm:grid-cols-2"
      >
        <TextField
          label={t("admin.audit.filters.action")}
          hint={t("admin.audit.filters.actionHint")}
          name="action"
          list={actionsId}
          autoComplete="off"
          spellCheck={false}
          maxLength={100}
          value={action}
          onChange={(event) => setAction(event.target.value)}
        />
        <datalist id={actionsId}>
          {KNOWN_ACTIONS.map((entry) => (
            <option key={entry} value={entry} />
          ))}
        </datalist>
        <TextField
          label={t("admin.audit.filters.actor")}
          hint={t("admin.audit.filters.actorHint")}
          name="actor_id"
          autoComplete="off"
          spellCheck={false}
          maxLength={36}
          value={actorId}
          errors={actorInvalid ? [t("admin.common.idFormat")] : []}
          onChange={(event) => setActorId(event.target.value)}
        />
        <div className="flex flex-wrap gap-3 sm:col-span-2">
          <Button type="submit">{t("admin.audit.filters.apply")}</Button>
          <Button
            variant="secondary"
            onClick={() => onApply({ action: "", actorId: "" })}
          >
            {t("admin.audit.filters.clear")}
          </Button>
        </div>
      </form>
    </section>
  );
}

/** The actor of an event: "System" without an actor, else a filter button. */
function Actor({
  event,
  onFilter,
}: {
  event: AdminAuditEvent;
  onFilter: (actorId: string) => void;
}) {
  const { t } = useTranslation();
  if (event.actor_id === null) return <>{t("admin.audit.system")}</>;
  const actorId = event.actor_id;
  const name = event.actor_display_name ?? t("admin.audit.unknownActor");
  return (
    <RowAction
      aria-label={t("admin.audit.filterActor", { name })}
      onClick={() => onFilter(actorId)}
    >
      {name}
    </RowAction>
  );
}

/**
 * `/admin/audit` (task 0015, step 18): the audit log, the newest first,
 * as a table with time, actor, action and subject, filtered by action and
 * actor id and paged by 50 events. The filters and the page live in the
 * URL (`?action=&actor_id=&page=`). The answer names no total, so "Next
 * page" is available while a page is full.
 */
export function AuditPage() {
  const { t, i18n } = useTranslation();
  const headingId = useId();
  const [searchParams, setSearchParams] = useSearchParams();
  const filters: Filters = {
    action: searchParams.get("action") ?? "",
    actorId: searchParams.get("actor_id") ?? "",
  };
  const page = pageParam(searchParams.get("page"));
  const events = useAuditEvents({
    action: filters.action || undefined,
    actorId: filters.actorId || undefined,
    page,
  });

  const navigate = (next: Filters, nextPage = 1) => {
    const params = new URLSearchParams();
    if (next.action !== "") params.set("action", next.action);
    if (next.actorId !== "") params.set("actor_id", next.actorId);
    if (nextPage > 1) params.set("page", String(nextPage));
    setSearchParams(params);
  };

  let body;
  if (events.isPending) {
    body = <LoadingStatus text={t("admin.audit.table.loading")} />;
  } else if (events.isError) {
    body = (
      <p role="alert" className="text-gray-700 dark:text-gray-300">
        {t("admin.common.loadFailed")}
      </p>
    );
  } else {
    const { events: entries, per_page: perPage } = events.data;
    body = (
      <>
        {entries.length === 0 ? (
          <p className="text-gray-700 dark:text-gray-300">
            {t("admin.audit.table.empty")}
          </p>
        ) : (
          <TableFrame labelledBy={headingId}>
            <thead>
              <tr>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("admin.audit.table.time")}
                </th>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("admin.audit.table.actor")}
                </th>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("admin.audit.table.action")}
                </th>
                <th scope="col" className={TABLE_CLASSES.columnHeader}>
                  {t("admin.audit.table.subject")}
                </th>
              </tr>
            </thead>
            <tbody>
              {entries.map((event) => (
                <tr key={event.id}>
                  <th
                    scope="row"
                    className={`${TABLE_CLASSES.subRowHeader} whitespace-nowrap`}
                  >
                    {formatDateTime(event.at, i18n.language)}
                  </th>
                  <td className={TABLE_CLASSES.cell}>
                    <Actor
                      event={event}
                      onFilter={(actorId) =>
                        navigate({ action: filters.action, actorId })
                      }
                    />
                  </td>
                  <td className={`${TABLE_CLASSES.cell} font-mono`}>
                    {event.action}
                  </td>
                  <td className={TABLE_CLASSES.cell}>
                    {event.subject_type === null &&
                    event.subject_id === null ? (
                      t("admin.common.none")
                    ) : (
                      <>
                        {event.subject_type}{" "}
                        <span className="block font-mono text-xs break-all text-gray-600 dark:text-gray-400">
                          {event.subject_id}
                        </span>
                      </>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </TableFrame>
        )}
        {(page > 1 || entries.length >= perPage) && (
          <Pager
            label={t("admin.audit.pagination")}
            page={page}
            hasNext={entries.length >= perPage}
            onPage={(next) => navigate(filters, next)}
          />
        )}
      </>
    );
  }

  return (
    <section>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.audit.title")}
      </h1>
      <p className="mt-2 max-w-3xl text-gray-700 dark:text-gray-300">
        {t("admin.audit.intro")}
      </p>
      <FilterForm
        key={`${filters.action}\n${filters.actorId}`}
        filters={filters}
        onApply={(next) => navigate(next)}
      />
      <section className="mt-10 space-y-4">
        <h2 id={headingId} className="text-xl font-semibold tracking-tight">
          {t("admin.audit.table.title")}
        </h2>
        {body}
      </section>
    </section>
  );
}
