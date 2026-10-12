import { useQuery } from "@tanstack/react-query";
import { useApiClient } from "./apiClientContext";
import { unwrap } from "./errors";
import type { components } from "./schema";

/**
 * The six reports for the role `analyst` (task 0014, step 8). Each one
 * reads the program `slug` in any status, names the threshold
 * `min_group_size` and the content language `locale` of the program, and
 * returns cells with `{count, value}` or `{suppressed: true}`. The reports
 * page under `src/admin/insights/` reads them through these hooks.
 */
export type ReportCell = components["schemas"]["ReportCell"];
export type SelfAssessmentReport =
  components["schemas"]["SelfAssessmentReport"];
export type ItemReport = components["schemas"]["ItemReport"];
export type CompetenceReport = components["schemas"]["CompetenceReport"];
export type FormatReport = components["schemas"]["FormatReport"];
export type FeedbackReport = components["schemas"]["FeedbackReport"];
export type CredentialReport = components["schemas"]["CredentialReport"];

export const reportsQueryKey = ["insights"] as const;

const reportKey = (report: string, slug: string) =>
  [...reportsQueryKey, report, slug] as const;

/**
 * `GET /api/insights/self-assessment`: the segments by month. With
 * `enabled: false` the hook only reads the cached report, which another
 * caller loads, and sends no request of its own.
 */
export function useSelfAssessmentReport(
  slug: string,
  { enabled = true }: { enabled?: boolean } = {},
) {
  const client = useApiClient();
  return useQuery({
    enabled,
    queryKey: reportKey("self-assessment", slug),
    queryFn: async (): Promise<SelfAssessmentReport> =>
      unwrap(
        await client.GET("/api/insights/self-assessment", {
          params: { query: { program: slug } },
        }),
      ),
  });
}

/** `GET /api/insights/items`: the attempts and the share correct per item and month. */
export function useItemReport(slug: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: reportKey("items", slug),
    queryFn: async (): Promise<ItemReport> =>
      unwrap(
        await client.GET("/api/insights/items", {
          params: { query: { program: slug } },
        }),
      ),
  });
}

/**
 * `GET /api/insights/competence`: the share correct per competence area,
 * depth and month, and per org unit when `by_org_unit` is true.
 */
export function useCompetenceReport(slug: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: reportKey("competence", slug),
    queryFn: async (): Promise<CompetenceReport> =>
      unwrap(
        await client.GET("/api/insights/competence", {
          params: { query: { program: slug } },
        }),
      ),
  });
}

/** `GET /api/insights/formats`: the "would use" votes per companion format. */
export function useFormatReport(slug: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: reportKey("formats", slug),
    queryFn: async (): Promise<FormatReport> =>
      unwrap(
        await client.GET("/api/insights/formats", {
          params: { query: { program: slug } },
        }),
      ),
  });
}

/** `GET /api/insights/feedback`: the answers per question of the feedback station. */
export function useFeedbackReport(slug: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: reportKey("feedback", slug),
    queryFn: async (): Promise<FeedbackReport> =>
      unwrap(
        await client.GET("/api/insights/feedback", {
          params: { query: { program: slug } },
        }),
      ) as FeedbackReport,
  });
}

/** `GET /api/insights/credentials`: the credentials per qualification and status. */
export function useCredentialReport(slug: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: reportKey("credentials", slug),
    queryFn: async (): Promise<CredentialReport> =>
      unwrap(
        await client.GET("/api/insights/credentials", {
          params: { query: { program: slug } },
        }),
      ),
  });
}
