import { useMutation, useQuery } from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { unwrap } from "../errors";
import type { components } from "../schema";

/**
 * Attendance certificates for facilitators (task 0013, step 16, and task
 * 0015, step 17): the companion formats of a published program, the lookup
 * of one active person by the exact e-mail address, and the certificates
 * of one session. The attendance page under `src/admin/attendance/` reads
 * them through these hooks.
 */
export type CompanionFormat = components["schemas"]["CompanionFormatView"];
export type FoundPerson = components["schemas"]["UserLookupResult"];
export type AttendanceResult =
  components["schemas"]["AttendanceResult"]["results"][number];
export type AttendanceOutcome = AttendanceResult["result"];

/** The earliest day of a session that attendance records (0013 addendum). */
export const EARLIEST_SESSION_DAY = "2000-01-01";

/** The most people that one request records (`AttendanceRequest.user_ids`). */
export const MAX_ATTENDEES = 200;

/** Today in the local calendar as `YYYY-MM-DD`. */
export function localToday(now: Date = new Date()): string {
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${now.getFullYear()}-${month}-${day}`;
}

/**
 * Today as `YYYY-MM-DD` on the calendar of the attendance route, which
 * compares `held_on` with the UTC date (`Date.utc_today/0`), so the page
 * and the server agree on the latest day.
 */
export function utcToday(now: Date = new Date()): string {
  return now.toISOString().slice(0, 10);
}

export interface ProgramFormats {
  locale: string;
  /** The formats whose attendance certificate provides evidence. */
  formats: CompanionFormat[];
}

/**
 * The companion formats of the published program `slug` whose
 * `attendance_counts` is true, with the language of the program. A format
 * without it records a certificate that satisfies no requirement (README
 * section 7, rule 11), so the page offers none of them.
 */
export function useAttendanceFormats(slug: string | null) {
  const client = useApiClient();
  return useQuery({
    enabled: slug !== null,
    queryKey: ["admin", "attendance", "formats", slug],
    queryFn: async (): Promise<ProgramFormats> => {
      const program = unwrap(
        await client.GET("/api/programs/{slug}", {
          params: { path: { slug: slug ?? "" } },
        }),
      );
      return {
        locale: program.locale,
        formats: program.companion_formats.filter(
          (format) => format.attendance_counts,
        ),
      };
    },
  });
}

/**
 * Looks up one active person by the exact address. The address travels in
 * the JSON body, so no URL carries it (ASVS 14.2.1); an unknown address
 * answers 404.
 */
export function useAttendeeLookup() {
  const client = useApiClient();
  return useMutation({
    mutationFn: async (email: string): Promise<FoundPerson> =>
      unwrap(
        await client.POST("/api/facilitator/user-lookups", {
          body: { email },
        }),
      ),
  });
}

/**
 * Records the attendance of `userIds` at a session of the format on
 * `heldOn` and returns one result per person. A day after today answers
 * 422 `validation_failed` with `fields.held_on` `["future"]`, a day before
 * 2000-01-01 with `["past"]`.
 */
export function useRecordAttendance() {
  const client = useApiClient();
  return useMutation({
    mutationFn: async ({
      formatId,
      userIds,
      heldOn,
    }: {
      formatId: string;
      userIds: string[];
      heldOn: string;
    }): Promise<AttendanceResult[]> =>
      unwrap(
        await client.POST("/api/formats/{id}/attendance", {
          params: { path: { id: formatId } },
          body: { user_ids: userIds, held_on: heldOn },
        }),
      ).results,
  });
}
