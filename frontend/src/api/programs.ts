import { useQuery } from "@tanstack/react-query";
import { useApiClient } from "./apiClientContext";
import { unwrap } from "./errors";
import type { components } from "./schema";

/** A published program of `GET /api/programs`. */
export type ProgramSummary =
  components["schemas"]["ProgramList"]["programs"][number];
export type Handbook = components["schemas"]["Handbook"];

/** The published programs with slug, title and locale. */
export function usePrograms() {
  const client = useApiClient();
  return useQuery({
    queryKey: ["programs"],
    queryFn: async (): Promise<ProgramSummary[]> =>
      unwrap(await client.GET("/api/programs")).programs,
  });
}

/**
 * The rules of a program grouped by module, and the placeholders of the
 * program, each with its key and the current version of its policy or
 * `null`.
 */
export function useHandbook(slug: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: ["programs", slug, "handbook"],
    queryFn: async (): Promise<Handbook> =>
      unwrap(
        await client.GET("/api/programs/{slug}/handbook", {
          params: { path: { slug } },
        }),
      ),
  });
}
