import { ChevronDownIcon, ChevronUpIcon } from "@heroicons/react/20/solid";
import {
  useEffect,
  useId,
  useRef,
  useState,
  type FormEvent,
  type KeyboardEvent,
  type ReactNode,
} from "react";
import { useTranslation } from "react-i18next";
import { ConfirmDialog } from "../../app/ConfirmDialog";
import { AlertRegion, Button, StatusRegion } from "../../app/forms";
import { buttonClasses, FOCUS_RING } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useErrorText } from "../../app/useErrorText";
import {
  APPROVED_TOOL_STATUSES,
  useAdminApprovedTools,
  useCreateApprovedTool,
  useDeleteApprovedTool,
  useUpdateApprovedTool,
  type AdminApprovedTool,
  type AdminApprovedToolFields,
  type ApprovedToolStatus,
} from "../../api/admin/approvedTools";
import { fieldCodes, isApiError } from "../../api/admin/fieldErrors";
import { RECENT_AUTH_ERROR_CODE } from "../../api/errors";
import { formatDay } from "../../player/format";

const NAME_MAX = 255;
const CONDITIONS_MAX = 10_000;
const POSITION_MAX = 2_147_483_647;

const CELL =
  "border-b border-gray-200 px-3 py-2 align-top text-gray-800 dark:border-gray-700 dark:text-gray-200";
const ROW_HEADER =
  "border-b border-gray-200 px-3 py-2 align-top font-medium text-gray-900 dark:border-gray-700 dark:text-gray-100";
const COLUMN_HEADER =
  "border-b border-gray-200 bg-gray-50 px-3 py-2 align-bottom font-semibold text-gray-900 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100";
const CONTROL = `block w-full min-w-28 rounded-md border border-gray-500 bg-white px-2 py-1.5 text-sm text-gray-900 aria-[invalid=true]:border-red-700 dark:bg-gray-900 dark:text-gray-100 dark:aria-[invalid=true]:border-red-400 ${FOCUS_RING}`;
const LABEL = "block text-sm font-medium text-gray-900 dark:text-gray-100";
const FIELD_ERROR = "mt-1 text-sm text-red-700 dark:text-red-300";

type SortKey =
  "position" | "name" | "vendor" | "status" | "conditions" | "reviewed_on";
type Direction = "ascending" | "descending";

const COLUMNS: readonly SortKey[] = [
  "position",
  "name",
  "vendor",
  "status",
  "conditions",
  "reviewed_on",
];

/** The text values of the controls of a tool. */
interface ToolDraft {
  name: string;
  vendor: string;
  status: ApprovedToolStatus;
  conditions: string;
  reviewed_on: string;
  position: string;
}

type DraftErrors = Partial<Record<keyof ToolDraft, string>>;

const draftOf = (tool: AdminApprovedTool): ToolDraft => ({
  name: tool.name,
  vendor: tool.vendor,
  status: tool.status,
  conditions: tool.conditions ?? "",
  reviewed_on: tool.reviewed_on ?? "",
  position: String(tool.position),
});

/** The fields of the request; empty conditions and an empty date become `null`. */
const fieldsOf = (draft: ToolDraft): AdminApprovedToolFields => ({
  name: draft.name.trim(),
  vendor: draft.vendor.trim(),
  status: draft.status,
  conditions: draft.conditions.trim() === "" ? null : draft.conditions.trim(),
  reviewed_on: draft.reviewed_on === "" ? null : draft.reviewed_on,
  position: Number(draft.position),
});

/** The fields of `next` that differ from `tool`. */
function changedFields(
  tool: AdminApprovedTool,
  next: AdminApprovedToolFields,
): Partial<AdminApprovedToolFields> {
  const changed: Partial<AdminApprovedToolFields> = {};
  if (next.name !== tool.name) changed.name = next.name;
  if (next.vendor !== tool.vendor) changed.vendor = next.vendor;
  if (next.status !== tool.status) changed.status = next.status;
  if ((next.conditions ?? null) !== tool.conditions)
    changed.conditions = next.conditions;
  if ((next.reviewed_on ?? null) !== tool.reviewed_on)
    changed.reviewed_on = next.reviewed_on;
  if (next.position !== tool.position) changed.position = next.position;
  return changed;
}

/** The order of the tools by `key` in `direction`; empty values sort last. */
function sortTools(
  tools: readonly AdminApprovedTool[],
  key: SortKey,
  direction: Direction,
  language: string,
): AdminApprovedTool[] {
  const factor = direction === "ascending" ? 1 : -1;
  const collator = new Intl.Collator(language, { sensitivity: "base" });
  const compare = (a: AdminApprovedTool, b: AdminApprovedTool): number => {
    if (key === "position") return a.position - b.position;
    if (key === "status")
      return (
        APPROVED_TOOL_STATUSES.indexOf(a.status) -
        APPROVED_TOOL_STATUSES.indexOf(b.status)
      );
    return collator.compare(a[key] ?? "", b[key] ?? "");
  };
  return [...tools].sort((a, b) => {
    // Empty conditions and review dates stay last in both directions.
    if (key === "conditions" || key === "reviewed_on") {
      if (a[key] === null && b[key] !== null) return 1;
      if (b[key] === null && a[key] !== null) return -1;
    }
    return compare(a, b) * factor || a.position - b.position;
  });
}

/**
 * The messages of a failed save: the client checks of `draft`, or the
 * field codes of a 422 answer of the server.
 */
function useToolErrors() {
  const { t } = useTranslation();
  const errorText = useErrorText();

  const validate = (draft: ToolDraft): DraftErrors => {
    const errors: DraftErrors = {};
    for (const field of ["name", "vendor"] as const) {
      const value = draft[field].trim();
      if (value === "")
        errors[field] = t("admin.approvedTools.errors.required");
      else if (value.length > NAME_MAX)
        errors[field] = t("admin.approvedTools.errors.tooLong", {
          max: NAME_MAX,
        });
    }
    if (draft.conditions.trim().length > CONDITIONS_MAX)
      errors.conditions = t("admin.approvedTools.errors.tooLong", {
        max: CONDITIONS_MAX,
      });
    const position = Number(draft.position);
    if (
      draft.position.trim() === "" ||
      !Number.isInteger(position) ||
      position < 0 ||
      position > POSITION_MAX
    )
      errors.position = t("admin.approvedTools.errors.position");
    return errors;
  };

  /** Field messages and the message of the form for a failed request. */
  const fromFailure = (
    failure: unknown,
  ): { fields: DraftErrors; form: string | null } => {
    if (isApiError(failure, 403, RECENT_AUTH_ERROR_CODE))
      return { fields: {}, form: t("account.stepUp.text") };
    if (!isApiError(failure, 422))
      return { fields: {}, form: errorText(failure) };
    const fields: DraftErrors = {};
    if (fieldCodes(failure, "name").includes("unique"))
      fields.name = t("admin.approvedTools.errors.nameTaken");
    for (const field of [
      "name",
      "vendor",
      "conditions",
      "reviewed_on",
      "position",
    ] as const)
      if (fields[field] === undefined && fieldCodes(failure, field).length > 0)
        fields[field] = t("admin.approvedTools.errors.invalid");
    return {
      fields,
      form:
        Object.keys(fields).length === 0
          ? t("admin.approvedTools.errors.rejected")
          : null,
    };
  };

  return { validate, fromFailure };
}

/** One control of a tool with its label and its error. */
function ToolControl({
  field,
  draft,
  errors,
  onChange,
  label,
  hiddenLabel = false,
}: {
  field: keyof ToolDraft;
  draft: ToolDraft;
  errors: DraftErrors;
  onChange: (draft: ToolDraft) => void;
  label: string;
  hiddenLabel?: boolean;
}) {
  const { t } = useTranslation();
  const id = useId();
  const errorId = `${id}-error`;
  const error = errors[field];
  const common = {
    id,
    "aria-invalid": error !== undefined ? true : undefined,
    "aria-describedby": error !== undefined ? errorId : undefined,
    className: CONTROL,
  };

  let control: ReactNode;
  if (field === "status") {
    control = (
      <select
        {...common}
        value={draft.status}
        onChange={(event) =>
          onChange({
            ...draft,
            status: event.target.value as ApprovedToolStatus,
          })
        }
      >
        {APPROVED_TOOL_STATUSES.map((status) => (
          <option key={status} value={status}>
            {t(`policies.tools.statuses.${status}`)}
          </option>
        ))}
      </select>
    );
  } else if (field === "conditions") {
    control = (
      <textarea
        {...common}
        rows={2}
        maxLength={CONDITIONS_MAX}
        value={draft.conditions}
        onChange={(event) =>
          onChange({ ...draft, conditions: event.target.value })
        }
      />
    );
  } else {
    const type =
      field === "reviewed_on"
        ? "date"
        : field === "position"
          ? "number"
          : "text";
    control = (
      <input
        {...common}
        type={type}
        min={field === "position" ? 0 : undefined}
        step={field === "position" ? 1 : undefined}
        inputMode={field === "position" ? "numeric" : undefined}
        maxLength={
          field === "name" || field === "vendor" ? NAME_MAX : undefined
        }
        required={field !== "reviewed_on"}
        value={draft[field]}
        onChange={(event) =>
          onChange({ ...draft, [field]: event.target.value })
        }
      />
    );
  }

  return (
    <div>
      <label htmlFor={id} className={hiddenLabel ? "sr-only" : LABEL}>
        {label}
      </label>
      <div className={hiddenLabel ? undefined : "mt-1"}>{control}</div>
      {error !== undefined && (
        <p id={errorId} className={FIELD_ERROR}>
          {error}
        </p>
      )}
    </div>
  );
}

/** A column header that sorts the table by its column. */
function SortHeader({
  column,
  sort,
  onSort,
}: {
  column: SortKey;
  sort: { key: SortKey; direction: Direction };
  onSort: (key: SortKey) => void;
}) {
  const { t } = useTranslation();
  const active = sort.key === column;
  const Icon =
    active && sort.direction === "descending" ? ChevronDownIcon : ChevronUpIcon;
  return (
    <th
      scope="col"
      aria-sort={active ? sort.direction : undefined}
      className={COLUMN_HEADER}
    >
      <button
        type="button"
        onClick={() => onSort(column)}
        className={`inline-flex items-center gap-1 rounded-sm font-semibold ${FOCUS_RING}`}
      >
        {t(`admin.approvedTools.columns.${column}`)}
        <Icon
          aria-hidden="true"
          className={`size-4 ${active ? "" : "opacity-30"}`}
        />
      </button>
    </th>
  );
}

/** A row in place for editing: one control per column, Save and Cancel. */
function EditRow({
  tool,
  onDone,
}: {
  tool: AdminApprovedTool;
  onDone: (message: string | null) => void;
}) {
  const { t } = useTranslation();
  const update = useUpdateApprovedTool();
  const { validate, fromFailure } = useToolErrors();
  const [draft, setDraft] = useState(() => draftOf(tool));
  const [errors, setErrors] = useState<DraftErrors>({});
  const [formError, setFormError] = useState<string | null>(null);
  const nameCell = useRef<HTMLTableCellElement>(null);

  useEffect(() => {
    nameCell.current?.querySelector("input")?.focus();
  }, []);

  const save = async () => {
    const found = validate(draft);
    setErrors(found);
    setFormError(null);
    if (Object.keys(found).length > 0) return;
    const changed = changedFields(tool, fieldsOf(draft));
    if (Object.keys(changed).length === 0) {
      onDone(null);
      return;
    }
    try {
      const saved = await update.mutateAsync({ id: tool.id, tool: changed });
      onDone(t("admin.approvedTools.saved", { name: saved.name }));
    } catch (failure) {
      const { fields, form } = fromFailure(failure);
      setErrors(fields);
      setFormError(form);
    }
  };

  const onKeyDown = (event: KeyboardEvent<HTMLTableRowElement>) => {
    if (event.key === "Escape") {
      event.preventDefault();
      onDone(null);
    }
  };

  const control = (field: keyof ToolDraft) => (
    <ToolControl
      field={field}
      draft={draft}
      errors={errors}
      onChange={setDraft}
      label={t(`admin.approvedTools.columns.${field}`)}
      hiddenLabel
    />
  );

  return (
    <tr onKeyDown={onKeyDown} className="bg-accent-50/40 dark:bg-gray-800/60">
      <td className={`${CELL} w-24`}>{control("position")}</td>
      <td ref={nameCell} className={CELL}>
        {control("name")}
      </td>
      <td className={CELL}>{control("vendor")}</td>
      <td className={CELL}>{control("status")}</td>
      <td className={CELL}>{control("conditions")}</td>
      <td className={CELL}>{control("reviewed_on")}</td>
      <td className={CELL}>
        <div className="flex flex-wrap gap-2">
          <Button onClick={() => void save()} disabled={update.isPending}>
            {update.isPending
              ? t("admin.approvedTools.saving")
              : t("admin.approvedTools.save")}
          </Button>
          <Button variant="secondary" onClick={() => onDone(null)}>
            {t("admin.approvedTools.cancel")}
          </Button>
        </div>
        {formError !== null && (
          <p role="alert" className={FIELD_ERROR}>
            {formError}
          </p>
        )}
      </td>
    </tr>
  );
}

/** The form that adds a tool below the table. */
function CreateToolForm({
  nextPosition,
  onAdded,
}: {
  nextPosition: number;
  onAdded: (message: string) => void;
}) {
  const { t } = useTranslation();
  const create = useCreateApprovedTool();
  const { validate, fromFailure } = useToolErrors();
  const empty = (): ToolDraft => ({
    name: "",
    vendor: "",
    status: "approved",
    conditions: "",
    reviewed_on: "",
    position: "",
  });
  const [draft, setDraft] = useState(empty);
  const [errors, setErrors] = useState<DraftErrors>({});
  const [formError, setFormError] = useState<string | null>(null);
  // An untouched position field shows the place after the last tool.
  const shown: ToolDraft = {
    ...draft,
    position: draft.position === "" ? String(nextPosition) : draft.position,
  };

  const submit = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const found = validate(shown);
    setErrors(found);
    setFormError(null);
    if (Object.keys(found).length > 0) return;
    try {
      const added = await create.mutateAsync(fieldsOf(shown));
      setDraft(empty());
      onAdded(t("admin.approvedTools.add.added", { name: added.name }));
    } catch (failure) {
      const { fields, form } = fromFailure(failure);
      setErrors(fields);
      setFormError(form);
    }
  };

  const control = (field: keyof ToolDraft) => (
    <ToolControl
      field={field}
      draft={shown}
      errors={errors}
      onChange={setDraft}
      label={t(`admin.approvedTools.columns.${field}`)}
    />
  );

  return (
    <section aria-labelledby="add-tool" className="mt-10 max-w-3xl">
      <h2 id="add-tool" className="text-xl font-semibold tracking-tight">
        {t("admin.approvedTools.add.title")}
      </h2>
      <form
        noValidate
        onSubmit={(event) => void submit(event)}
        className="mt-4 grid gap-4 sm:grid-cols-2"
      >
        {control("name")}
        {control("vendor")}
        {control("status")}
        {control("reviewed_on")}
        <div className="sm:col-span-2">{control("conditions")}</div>
        {control("position")}
        <div className="space-y-2 sm:col-span-2">
          <AlertRegion>{formError}</AlertRegion>
          <Button type="submit" disabled={create.isPending}>
            {create.isPending
              ? t("admin.approvedTools.saving")
              : t("admin.approvedTools.add.submit")}
          </Button>
        </div>
      </form>
    </section>
  );
}

/**
 * `/admin/approved-tools` (task 0015, step 14): the approved tool list that
 * learners see on `/policies`, in a table that sorts by each column. "Edit"
 * turns a row into controls in place and sends the changed fields as
 * `{"approved_tool": {...}}`; Escape or "Cancel" leaves the row unchanged.
 * A form below the table adds a tool, and "Delete" asks for a
 * confirmation first.
 */
export function ApprovedToolsPage() {
  const { t, i18n } = useTranslation();
  const errorText = useErrorText();
  const tools = useAdminApprovedTools();
  const remove = useDeleteApprovedTool();
  const headingId = useId();
  const [sort, setSort] = useState<{ key: SortKey; direction: Direction }>({
    key: "position",
    direction: "ascending",
  });
  const [editing, setEditing] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<AdminApprovedTool | null>(null);
  const [status, setStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const editButtons = useRef(new Map<string, HTMLButtonElement>());

  const onSort = (key: SortKey) =>
    setSort((current) => ({
      key,
      direction:
        current.key === key && current.direction === "ascending"
          ? "descending"
          : "ascending",
    }));

  const startEditing = (tool: AdminApprovedTool) => {
    setStatus(null);
    setError(null);
    setEditing(tool.id);
  };

  const stopEditing = (id: string, message: string | null) => {
    setEditing(null);
    if (message !== null) setStatus(message);
    requestAnimationFrame(() => editButtons.current.get(id)?.focus());
  };

  const confirmDelete = async () => {
    const tool = deleting;
    setDeleting(null);
    if (tool === null) return;
    setStatus(null);
    setError(null);
    try {
      await remove.mutateAsync(tool.id);
      setStatus(t("admin.approvedTools.deleted", { name: tool.name }));
    } catch (failure) {
      setError(
        isApiError(failure, 403, RECENT_AUTH_ERROR_CODE)
          ? t("account.stepUp.text")
          : errorText(failure),
      );
    }
  };

  let body: ReactNode;
  if (tools.isPending) {
    body = <LoadingStatus text={t("admin.approvedTools.loading")} />;
  } else if (tools.isError) {
    body = (
      <p role="alert" className="text-gray-700 dark:text-gray-300">
        {t("admin.approvedTools.loadFailed")}
      </p>
    );
  } else if (tools.data.length === 0) {
    body = (
      <p className="text-gray-700 dark:text-gray-300">
        {t("admin.approvedTools.empty")}
      </p>
    );
  } else {
    const sorted = sortTools(
      tools.data,
      sort.key,
      sort.direction,
      i18n.language,
    );
    body = (
      <div
        role="region"
        aria-labelledby={headingId}
        tabIndex={0}
        className={`overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700 ${FOCUS_RING}`}
      >
        <table
          aria-labelledby={headingId}
          className="min-w-full border-collapse text-left text-sm"
        >
          <thead>
            <tr>
              {COLUMNS.map((column) => (
                <SortHeader
                  key={column}
                  column={column}
                  sort={sort}
                  onSort={onSort}
                />
              ))}
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.approvedTools.columns.actions")}
              </th>
            </tr>
          </thead>
          <tbody>
            {sorted.map((tool) =>
              editing === tool.id ? (
                <EditRow
                  key={tool.id}
                  tool={tool}
                  onDone={(message) => stopEditing(tool.id, message)}
                />
              ) : (
                <tr key={tool.id}>
                  <td className={`${CELL} tabular-nums`}>{tool.position}</td>
                  <th scope="row" className={ROW_HEADER}>
                    {tool.name}
                  </th>
                  <td className={CELL}>{tool.vendor}</td>
                  <td className={CELL} data-status={tool.status}>
                    {t(`policies.tools.statuses.${tool.status}`)}
                  </td>
                  <td className={CELL}>
                    {tool.conditions ?? t("policies.tools.noConditions")}
                  </td>
                  <td className={`${CELL} whitespace-nowrap`}>
                    {tool.reviewed_on === null
                      ? t("policies.tools.notReviewed")
                      : formatDay(tool.reviewed_on, i18n.language)}
                  </td>
                  <td className={CELL}>
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        className={buttonClasses("secondary")}
                        disabled={editing !== null}
                        ref={(element) => {
                          if (element)
                            editButtons.current.set(tool.id, element);
                          else editButtons.current.delete(tool.id);
                        }}
                        onClick={() => startEditing(tool)}
                      >
                        {t("admin.approvedTools.edit")}{" "}
                        <span className="sr-only">{tool.name}</span>
                      </button>
                      <Button
                        variant="danger"
                        disabled={editing !== null || remove.isPending}
                        onClick={() => setDeleting(tool)}
                      >
                        {t("admin.approvedTools.delete")}{" "}
                        <span className="sr-only">{tool.name}</span>
                      </Button>
                    </div>
                  </td>
                </tr>
              ),
            )}
          </tbody>
        </table>
      </div>
    );
  }

  const nextPosition =
    (tools.data ?? []).reduce(
      (highest, tool) => Math.max(highest, tool.position),
      0,
    ) + 1;

  return (
    <section>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.approvedTools.title")}
      </h1>
      <p className="mt-2 max-w-3xl text-gray-700 dark:text-gray-300">
        {t("admin.approvedTools.intro")}
      </p>
      <div className="mt-8 space-y-4">
        <h2 id={headingId} className="text-xl font-semibold tracking-tight">
          {t("admin.approvedTools.tableTitle")}
        </h2>
        <AlertRegion>{error}</AlertRegion>
        <StatusRegion>{status}</StatusRegion>
        {body}
      </div>
      <CreateToolForm
        nextPosition={nextPosition}
        onAdded={(message) => {
          setError(null);
          setStatus(message);
        }}
      />
      <ConfirmDialog
        open={deleting !== null}
        title={t("admin.approvedTools.deleteTitle")}
        confirmLabel={t("admin.approvedTools.delete")}
        confirmVariant="danger"
        onConfirm={() => void confirmDelete()}
        onClose={() => setDeleting(null)}
      >
        <p>
          {t("admin.approvedTools.deleteText", { name: deleting?.name ?? "" })}
        </p>
      </ConfirmDialog>
    </section>
  );
}
