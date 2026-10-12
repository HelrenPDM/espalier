import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useApiClient } from "./apiClientContext";
import { ApiError, unwrap } from "./errors";
import type { components } from "./schema";

/**
 * The SCORM export of the role `author` (task 0016, steps 10 and 11): the
 * modules of a published program, the request of an export and its status
 * with the path of the download. The export page `src/admin/ExportsPage.tsx`
 * reads them through these hooks.
 */
export type AdminExport = components["schemas"]["AdminExport"];
export type ExportRequest = components["schemas"]["AdminExportRequest"];
export type ScormVersion = ExportRequest["scorm_version"];
export type ExportStatus = AdminExport["status"];
export type ProgramModule =
  components["schemas"]["ProgramView"]["modules"][number];

/** The versions of a package in the order of the form. */
export const SCORM_VERSIONS = [
  "scorm12",
  "scorm2004",
] as const satisfies readonly ScormVersion[];

/** The milliseconds between two reads of an export that is not finished. */
export const EXPORT_POLL_INTERVAL = 2000;

export const exportQueryKey = (id: string) => ["admin", "exports", id] as const;

/** True while the worker has not finished the export. */
export const exportInProgress = (status: ExportStatus): boolean =>
  status === "queued" || status === "running";

/**
 * The interval of the next read of an export: every two seconds while the
 * last answer is `queued` or `running`, and no further read once it is
 * `done` or `failed`. An `ApiError` below 500, such as 404, ends the reads,
 * because a repeat gets the same answer; a network error or a 5xx answer
 * keeps them going.
 */
export function exportPollInterval(state: {
  data?: AdminExport;
  error: unknown;
}): number | false {
  if (state.error instanceof ApiError && state.error.status < 500) return false;
  return state.data !== undefined && exportInProgress(state.data.status)
    ? EXPORT_POLL_INTERVAL
    : false;
}

export interface ProgramModules {
  locale: string;
  /** The live modules in number order. */
  modules: ProgramModule[];
}

/**
 * The modules of the published program `slug` (`GET /api/programs/:slug`
 * of 0009), with the language of the program.
 */
export function useExportModules(slug: string | null) {
  const client = useApiClient();
  return useQuery({
    enabled: slug !== null,
    queryKey: ["admin", "exports", "modules", slug],
    queryFn: async (): Promise<ProgramModules> => {
      const program = unwrap(
        await client.GET("/api/programs/{slug}", {
          params: { path: { slug: slug ?? "" } },
        }),
      );
      return { locale: program.locale, modules: program.modules };
    },
  });
}

/**
 * `GET /api/admin/exports/:id`. The query reads the export again every two
 * seconds while its status is `queued` or `running` (`exportPollInterval`).
 * The request puts its answer into the cache, so the first read follows one
 * interval after the request.
 */
export function useExport(id: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: exportQueryKey(id),
    queryFn: async (): Promise<AdminExport> =>
      unwrap(
        await client.GET("/api/admin/exports/{id}", {
          params: { path: { id } },
        }),
      ),
    staleTime: EXPORT_POLL_INTERVAL,
    refetchInterval: (query) => exportPollInterval(query.state),
  });
}

/**
 * `POST /api/admin/exports` with exactly `module_id` and `scorm_version`,
 * the members of `AdminExportRequest`. The route needs a second factor
 * from the last 10 minutes; the API client opens the step-up dialog on a
 * 403 `reauth_required` and repeats the request once after a successful
 * step-up. The answer is the export in status `queued`.
 */
export function useRequestExport() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async ({
      module_id,
      scorm_version,
    }: ExportRequest): Promise<AdminExport> =>
      unwrap(
        await client.POST("/api/admin/exports", {
          body: { module_id, scorm_version },
        }),
      ),
    onSuccess: (exported) =>
      queryClient.setQueryData(exportQueryKey(exported.id), exported),
  });
}
