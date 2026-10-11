import { useQuery } from "@tanstack/react-query";
import { useApiClient } from "./apiClientContext";
import { unwrap } from "./errors";
import type { components } from "./schema";

/**
 * The queries of the learner's credentials and requirements (task 0013,
 * step 23). The pages under `src/learner/` read them through these hooks and
 * import no API client.
 */
export type Credential = components["schemas"]["CredentialView"];
export type CredentialStatus = Credential["status"];
export type QualificationRequirements =
  components["schemas"]["RequirementList"]["qualifications"][number];
export type Requirement = QualificationRequirements["open"][number];
export type RequirementKind = Requirement["kind"];

export const credentialsQueryKey = ["me", "credentials"] as const;
export const requirementsQueryKey = ["me", "requirements"] as const;

/** The credentials of the signed-in user, the newest first. */
export function useCredentials() {
  const client = useApiClient();
  return useQuery({
    queryKey: credentialsQueryKey,
    queryFn: async (): Promise<Credential[]> =>
      unwrap(await client.GET("/api/me/credentials")).credentials,
  });
}

/** One credential of the signed-in user; any other id fails with a 404. */
export function useCredential(id: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: [...credentialsQueryKey, id],
    queryFn: async (): Promise<Credential> =>
      unwrap(
        await client.GET("/api/me/credentials/{id}", {
          params: { path: { id } },
        }),
      ),
  });
}

/**
 * The met and open requirements of the signed-in user per qualification of
 * the program `slug`, with the credential of each qualification.
 */
export function useRequirements(slug: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: [...requirementsQueryKey, slug],
    queryFn: async (): Promise<QualificationRequirements[]> =>
      unwrap(
        await client.GET("/api/me/requirements", {
          params: { query: { program: slug } },
        }),
      ).qualifications,
  });
}
