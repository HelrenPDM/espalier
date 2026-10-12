import { useId, useRef, useState, type FormEvent, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { AlertRegion, Button, StatusRegion, TextField } from "../../app/forms";
import { FOCUS_RING } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useErrorText } from "../../app/useErrorText";
import {
  EARLIEST_SESSION_DAY,
  MAX_ATTENDEES,
  useAttendanceFormats,
  useAttendeeLookup,
  useRecordAttendance,
  utcToday,
  type AttendanceResult,
} from "../../api/admin/attendance";
import { fieldCodes, isApiError } from "../../api/admin/fieldErrors";
import { RECENT_AUTH_ERROR_CODE } from "../../api/errors";
import { usePrograms } from "../../api/programs";
import { formatDay } from "../../player/format";

const SELECT = `mt-1 block w-full max-w-md rounded-md border border-gray-500 bg-white px-3 py-2 text-sm text-gray-900 aria-[invalid=true]:border-red-700 dark:bg-gray-900 dark:text-gray-100 dark:aria-[invalid=true]:border-red-400 ${FOCUS_RING}`;
const LABEL = "block text-sm font-medium text-gray-900 dark:text-gray-100";
const FIELD_ERROR = "mt-1 text-sm text-red-700 dark:text-red-300";
const CELL =
  "border-b border-gray-200 px-3 py-2 align-top text-gray-800 dark:border-gray-700 dark:text-gray-200";
const ROW_HEADER =
  "border-b border-gray-200 px-3 py-2 align-top font-medium text-gray-900 dark:border-gray-700 dark:text-gray-100";
const COLUMN_HEADER =
  "border-b border-gray-200 bg-gray-50 px-3 py-2 align-bottom font-semibold text-gray-900 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100";

/** A person on the list: the answer of the lookup and the address entered. */
interface Attendee {
  id: string;
  email: string;
  displayName: string | null;
  orgUnit: string | null;
}

/** A select with a visible label and an error connected to it. */
function SelectField({
  label,
  error,
  value,
  onChange,
  lang,
  children,
}: {
  label: string;
  error: string | null;
  value: string;
  onChange: (value: string) => void;
  lang?: string;
  children: ReactNode;
}) {
  const id = useId();
  const errorId = `${id}-error`;
  return (
    <div>
      <label htmlFor={id} className={LABEL}>
        {label}
      </label>
      <select
        id={id}
        lang={lang}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        aria-invalid={error !== null ? true : undefined}
        aria-describedby={error !== null ? errorId : undefined}
        className={SELECT}
      >
        {children}
      </select>
      {error !== null && (
        <p id={errorId} className={FIELD_ERROR}>
          {error}
        </p>
      )}
    </div>
  );
}

/** The name of a person on the list, or the address when the account has none. */
function AttendeeName({ attendee }: { attendee: Attendee }) {
  return <>{attendee.displayName ?? attendee.email}</>;
}

/** The result per person of the last submission. */
function Results({
  results,
  attendees,
}: {
  results: AttendanceResult[];
  attendees: Attendee[];
}) {
  const { t } = useTranslation();
  const headingId = useId();
  const byId = new Map(attendees.map((attendee) => [attendee.id, attendee]));

  return (
    <section className="mt-10">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.attendance.results.title")}
      </h2>
      <div
        role="region"
        aria-labelledby={headingId}
        tabIndex={0}
        className={`mt-4 overflow-x-auto rounded-lg border border-gray-200 dark:border-gray-700 ${FOCUS_RING}`}
      >
        <table
          aria-labelledby={headingId}
          className="min-w-full border-collapse text-left text-sm"
        >
          <thead>
            <tr>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.attendance.results.person")}
              </th>
              <th scope="col" className={COLUMN_HEADER}>
                {t("admin.attendance.results.result")}
              </th>
            </tr>
          </thead>
          <tbody>
            {results.map((result) => {
              const attendee = byId.get(result.user_id);
              return (
                <tr key={result.user_id} data-result={result.result}>
                  <th scope="row" className={ROW_HEADER}>
                    {attendee === undefined ? (
                      result.user_id
                    ) : (
                      <AttendeeName attendee={attendee} />
                    )}
                  </th>
                  <td className={CELL}>
                    {t(`admin.attendance.results.outcomes.${result.result}`)}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}

/**
 * `/admin/attendance` (task 0015, step 17): a facilitator records who
 * attended a session of a companion format held outside the platform. The
 * page offers the formats with `attendance_counts: true` of a published
 * program, a day from 2000-01-01 to today, and a list of people that the
 * exact e-mail address finds through `POST /api/facilitator/user-lookups`
 * (the address travels in the body). "Record attendance" sends
 * `POST /api/formats/:id/attendance` and shows the result per person. The
 * page checks the day against the UTC date, as the route does, before it
 * sends, and it also shows the 422 `validation_failed` of the route with
 * `fields.held_on` `["future"]` or `["past"]`, because the server decides
 * on its own clock.
 */
export function AttendancePage() {
  const { t, i18n } = useTranslation();
  const errorText = useErrorText();
  const programs = usePrograms();
  const lookup = useAttendeeLookup();
  const record = useRecordAttendance();
  const emailId = useId();
  const resultsRef = useRef<HTMLDivElement>(null);

  const [chosenSlug, setChosenSlug] = useState<string | null>(null);
  const slug = chosenSlug ?? programs.data?.[0]?.slug ?? null;
  const program = programs.data?.find((entry) => entry.slug === slug);
  const formats = useAttendanceFormats(slug);
  const [formatId, setFormatId] = useState("");
  const [heldOn, setHeldOn] = useState("");
  const [email, setEmail] = useState("");
  const [attendees, setAttendees] = useState<Attendee[]>([]);
  const [results, setResults] = useState<AttendanceResult[] | null>(null);
  const [errors, setErrors] = useState<{
    format?: string;
    heldOn?: string;
    people?: string;
    email?: string;
    form?: string;
  }>({});
  const [peopleStatus, setPeopleStatus] = useState<string | null>(null);
  const [recordStatus, setRecordStatus] = useState<string | null>(null);

  const today = utcToday();
  const earliest = formatDay(EARLIEST_SESSION_DAY, i18n.language);
  const lang = program?.locale ?? formats.data?.locale;

  // Any change to the session or the list makes the last results stale.
  const changed = () => {
    setResults(null);
    setRecordStatus(null);
  };

  const dayError = (code: string): string | undefined => {
    if (code === "future") return t("admin.attendance.errors.future");
    if (code === "past") return t("admin.attendance.errors.past", { earliest });
    return undefined;
  };

  const addPerson = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const address = email.trim();
    setPeopleStatus(null);
    setErrors((current) => ({ ...current, email: undefined }));
    if (address === "") {
      setErrors((current) => ({
        ...current,
        email: t("admin.attendance.people.emailRequired"),
      }));
      return;
    }
    if (attendees.length >= MAX_ATTENDEES) {
      setErrors((current) => ({
        ...current,
        email: t("admin.attendance.people.full", { max: MAX_ATTENDEES }),
      }));
      return;
    }
    try {
      const person = await lookup.mutateAsync(address);
      const name = person.display_name ?? address;
      if (attendees.some((attendee) => attendee.id === person.id)) {
        setErrors((current) => ({
          ...current,
          email: t("admin.attendance.people.duplicate", { name }),
        }));
        return;
      }
      setAttendees((current) => [
        ...current,
        {
          id: person.id,
          email: address,
          displayName: person.display_name,
          orgUnit: person.org_unit,
        },
      ]);
      setEmail("");
      setErrors((current) => ({ ...current, people: undefined }));
      setPeopleStatus(t("admin.attendance.people.added", { name }));
      changed();
    } catch (failure) {
      let message: string;
      if (isApiError(failure, 404))
        message = t("admin.attendance.people.notFound");
      else if (isApiError(failure, 422))
        message = t("admin.attendance.people.invalidEmail");
      else message = errorText(failure);
      setErrors((current) => ({ ...current, email: message }));
    }
    document.getElementById(emailId)?.focus();
  };

  const removePerson = (attendee: Attendee) => {
    setAttendees((current) =>
      current.filter((entry) => entry.id !== attendee.id),
    );
    setPeopleStatus(
      t("admin.attendance.people.removed", {
        name: attendee.displayName ?? attendee.email,
      }),
    );
    changed();
    document.getElementById(emailId)?.focus();
  };

  const submit = async () => {
    const found: typeof errors = {};
    if (formatId === "")
      found.format = t("admin.attendance.errors.formatRequired");
    if (heldOn === "") found.heldOn = t("admin.attendance.errors.dateRequired");
    else if (heldOn > today) found.heldOn = dayError("future");
    else if (heldOn < EARLIEST_SESSION_DAY) found.heldOn = dayError("past");
    if (attendees.length === 0)
      found.people = t("admin.attendance.errors.peopleRequired");
    setErrors(found);
    setRecordStatus(null);
    setResults(null);
    if (Object.keys(found).length > 0) return;

    try {
      const answer = await record.mutateAsync({
        formatId,
        userIds: attendees.map((attendee) => attendee.id),
        heldOn,
      });
      setResults(answer);
      setRecordStatus(
        t("admin.attendance.results.recorded", { count: answer.length }),
      );
      requestAnimationFrame(() => resultsRef.current?.focus());
    } catch (failure) {
      const dayCodes = fieldCodes(failure, "held_on");
      const day = dayCodes.map(dayError).find((text) => text !== undefined);
      if (day !== undefined) setErrors({ heldOn: day });
      else if (isApiError(failure, 404)) {
        setFormatId("");
        setErrors({ format: t("admin.attendance.errors.formatGone") });
        void formats.refetch();
      } else if (isApiError(failure, 403, RECENT_AUTH_ERROR_CODE))
        setErrors({ form: t("account.stepUp.text") });
      else if (isApiError(failure, 422))
        setErrors({ form: t("admin.attendance.errors.rejected") });
      else setErrors({ form: errorText(failure) });
    }
  };

  let programField: ReactNode;
  if (programs.isPending)
    programField = (
      <LoadingStatus text={t("admin.attendance.session.programsLoading")} />
    );
  else if (programs.isError)
    programField = (
      <p role="alert" className="text-gray-700 dark:text-gray-300">
        {t("admin.attendance.session.programsFailed")}
      </p>
    );
  else if (slug === null)
    programField = (
      <p className="text-gray-700 dark:text-gray-300">
        {t("admin.attendance.session.noPrograms")}
      </p>
    );
  else
    programField = (
      <SelectField
        label={t("admin.attendance.session.program")}
        error={null}
        value={slug}
        lang={program?.locale}
        onChange={(next) => {
          setChosenSlug(next);
          setFormatId("");
          changed();
        }}
      >
        {programs.data.map((entry) => (
          <option key={entry.slug} value={entry.slug} lang={entry.locale}>
            {entry.title}
          </option>
        ))}
      </SelectField>
    );

  let formatField: ReactNode = null;
  if (slug !== null) {
    if (formats.isPending)
      formatField = (
        <LoadingStatus text={t("admin.attendance.session.formatsLoading")} />
      );
    else if (formats.isError)
      formatField = (
        <p role="alert" className="text-gray-700 dark:text-gray-300">
          {t("admin.attendance.session.formatsFailed")}
        </p>
      );
    else if (formats.data.formats.length === 0)
      formatField = (
        <p className="text-gray-700 dark:text-gray-300">
          {t("admin.attendance.session.noFormats")}
        </p>
      );
    else
      formatField = (
        <SelectField
          label={t("admin.attendance.session.format")}
          error={errors.format ?? null}
          value={formatId}
          lang={formatId === "" ? undefined : lang}
          onChange={(next) => {
            setFormatId(next);
            setErrors((current) => ({ ...current, format: undefined }));
            changed();
          }}
        >
          <option value="">{t("admin.attendance.session.chooseFormat")}</option>
          {formats.data.formats.map((format) => (
            <option key={format.id} value={format.id} lang={lang}>
              {format.title}
            </option>
          ))}
        </SelectField>
      );
  }

  return (
    <section>
      <h1 className="text-2xl font-semibold tracking-tight">
        {t("admin.attendance.title")}
      </h1>
      <p className="mt-2 max-w-3xl text-gray-700 dark:text-gray-300">
        {t("admin.attendance.intro")}
      </p>

      <section aria-labelledby="attendance-session" className="mt-8 max-w-xl">
        <h2
          id="attendance-session"
          className="text-xl font-semibold tracking-tight"
        >
          {t("admin.attendance.session.title")}
        </h2>
        <div className="mt-4 space-y-4">
          {programField}
          {formatField}
          <TextField
            type="date"
            label={t("admin.attendance.session.date")}
            hint={t("admin.attendance.session.dateHint", { earliest })}
            errors={errors.heldOn === undefined ? [] : [errors.heldOn]}
            min={EARLIEST_SESSION_DAY}
            max={today}
            value={heldOn}
            onChange={(event) => {
              setHeldOn(event.target.value);
              setErrors((current) => ({ ...current, heldOn: undefined }));
              changed();
            }}
            required
          />
        </div>
      </section>

      <section aria-labelledby="attendance-people" className="mt-10 max-w-xl">
        <h2
          id="attendance-people"
          className="text-xl font-semibold tracking-tight"
        >
          {t("admin.attendance.people.title")}
        </h2>
        <form
          noValidate
          onSubmit={(event) => void addPerson(event)}
          className="mt-4 space-y-3"
        >
          <TextField
            id={emailId}
            type="email"
            label={t("admin.attendance.people.email")}
            hint={t("admin.attendance.people.emailHint")}
            errors={errors.email === undefined ? [] : [errors.email]}
            value={email}
            onChange={(event) => setEmail(event.target.value)}
            autoComplete="off"
            spellCheck={false}
            autoCapitalize="off"
            maxLength={254}
          />
          <Button type="submit" variant="secondary" disabled={lookup.isPending}>
            {lookup.isPending
              ? t("admin.attendance.people.adding")
              : t("admin.attendance.people.add")}
          </Button>
        </form>
        <div className="mt-4">
          <StatusRegion>{peopleStatus}</StatusRegion>
        </div>
        <h3 id="attendance-list" className="mt-6 font-semibold">
          {t("admin.attendance.people.listTitle", { count: attendees.length })}
        </h3>
        {attendees.length === 0 ? (
          <p className="mt-2 text-gray-700 dark:text-gray-300">
            {t("admin.attendance.people.empty")}
          </p>
        ) : (
          <ul
            aria-labelledby="attendance-list"
            className="mt-2 divide-y divide-gray-200 rounded-md border border-gray-300 dark:divide-gray-800 dark:border-gray-700"
          >
            {attendees.map((attendee) => (
              <li
                key={attendee.id}
                className="flex flex-wrap items-start justify-between gap-3 px-4 py-3"
              >
                <div>
                  <p className="font-medium">
                    <AttendeeName attendee={attendee} />
                  </p>
                  <p className="text-sm text-gray-700 dark:text-gray-300">
                    {[attendee.orgUnit, attendee.email]
                      .filter((part) => part !== null)
                      .join(", ")}
                  </p>
                </div>
                <Button
                  variant="secondary"
                  onClick={() => removePerson(attendee)}
                >
                  {t("admin.attendance.people.remove")}{" "}
                  <span className="sr-only">
                    <AttendeeName attendee={attendee} />
                  </span>
                </Button>
              </li>
            ))}
          </ul>
        )}
        {errors.people !== undefined && (
          <p className={FIELD_ERROR}>{errors.people}</p>
        )}
      </section>

      <div className="mt-8 max-w-xl space-y-3">
        <AlertRegion>
          {errors.form ??
            ((errors.format ?? errors.heldOn ?? errors.people)
              ? t("admin.attendance.errors.check")
              : null)}
        </AlertRegion>
        <Button onClick={() => void submit()} disabled={record.isPending}>
          {record.isPending
            ? t("admin.attendance.submitting")
            : t("admin.attendance.submit")}
        </Button>
        <div ref={resultsRef} tabIndex={-1} className="focus:outline-none">
          <StatusRegion>{recordStatus}</StatusRegion>
        </div>
      </div>

      {results !== null && <Results results={results} attendees={attendees} />}
    </section>
  );
}
