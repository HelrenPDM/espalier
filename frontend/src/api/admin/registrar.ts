import { useQuery } from "@tanstack/react-query";
import { useApiClient } from "../apiClientContext";
import { unwrap } from "../errors";
import type { components } from "../schema";

/**
 * The credential list of one qualification for the role `registrar`
 * (README section 10, task 0013 step 18, task 0015 step 17). The route
 * answers 404 `not_found` while `REGISTRAR_ENABLED=false`, also for a
 * registrar.
 */
export type RegistrarCredential =
  components["schemas"]["RegistrarCredentialList"]["credentials"][number];

/**
 * The format of a qualification code, as the route checks it
 * (`Fields.key_param`): lower-case letters, digits and hyphens, starting
 * with a letter or a digit, at most 255 characters.
 */
export const QUALIFICATION_CODE_PATTERN = /^[a-z0-9][a-z0-9-]*$/;
export const QUALIFICATION_CODE_MAX_LENGTH = 255;

export const isQualificationCode = (code: string) =>
  code.length <= QUALIFICATION_CODE_MAX_LENGTH &&
  QUALIFICATION_CODE_PATTERN.test(code);

/**
 * One entry per credential of every qualification with `code`, ordered by
 * display name; a person who holds the code in two programs appears once
 * per credential. Sends no request while `code` is `null`.
 */
export function useRegistrarCredentials(code: string | null) {
  const client = useApiClient();
  return useQuery({
    enabled: code !== null,
    queryKey: ["registrar", "credentials", code],
    queryFn: async (): Promise<RegistrarCredential[]> =>
      unwrap(
        await client.GET("/api/registrar/credentials", {
          params: { query: { qualification: code ?? "" } },
        }),
      ).credentials,
  });
}
