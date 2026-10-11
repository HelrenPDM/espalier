import { startRegistration } from "@simplewebauthn/browser";
import {
  useMutation,
  useQuery,
  useQueryClient,
  type QueryClient,
} from "@tanstack/react-query";
import { useApiClient } from "./apiClientContext";
import type { ApiClient } from "./client";
import { unwrap } from "./errors";
import type { components } from "./schema";
import { sessionQueryKey } from "./session";

/**
 * The queries and mutations of the security settings (task 0011, step 12).
 * They read the API client from `ApiClientProvider`. Every mutation
 * invalidates `["me", "security"]` and `["me", "sessions"]` on success.
 * Mutations that return recovery codes or a TOTP secret set `gcTime: 0`, so
 * the values leave the mutation cache once the component resets them.
 */
export type SecuritySummary = components["schemas"]["SecuritySummary"];
export type PasskeyView = components["schemas"]["PasskeyView"];
export type SessionView =
  components["schemas"]["SessionList"]["sessions"][number];
export type TotpEnrollment = components["schemas"]["TotpEnrollment"];
export type PasskeyRegistrationResult =
  components["schemas"]["PasskeyRegistrationResult"];
export type TotpConfirmResult = components["schemas"]["TotpConfirmResult"];

export const securityQueryKey = ["me", "security"] as const;
export const sessionsQueryKey = ["me", "sessions"] as const;

/**
 * The passkeys and an enabled authenticator app: the count behind the
 * disabled "Remove" of the last second factor (ASVS 6.5.6).
 */
export function factorCount(security: SecuritySummary): number {
  return security.passkeys.length + (security.totp.enabled ? 1 : 0);
}

export function invalidateAccount(queryClient: QueryClient) {
  return Promise.all([
    queryClient.invalidateQueries({ queryKey: securityQueryKey }),
    queryClient.invalidateQueries({ queryKey: sessionsQueryKey }),
  ]);
}

export function securityQueryOptions(client: ApiClient) {
  return {
    queryKey: securityQueryKey,
    queryFn: async () => unwrap(await client.GET("/api/me/security")),
  };
}

export function useSecurity({ enabled = true }: { enabled?: boolean } = {}) {
  const client = useApiClient();
  return useQuery({ ...securityQueryOptions(client), enabled });
}

export function useSessions({ enabled = true }: { enabled?: boolean } = {}) {
  const client = useApiClient();
  return useQuery({
    queryKey: sessionsQueryKey,
    queryFn: async () => unwrap(await client.GET("/api/me/sessions")).sessions,
    enabled,
  });
}

function useAccountMutation<TVariables, TData>(
  mutationFn: (variables: TVariables) => Promise<TData>,
  { gcTime }: { gcTime?: number } = {},
) {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn,
    gcTime,
    onSuccess: () => invalidateAccount(queryClient),
  });
}

/**
 * Registers a passkey: creation options, `startRegistration` and
 * `POST /api/me/passkeys`. The SPA never asks for an automatic registration
 * without user presence, because `wax_` requires user presence at
 * registration. A browser failure rejects
 * with the error of `@simplewebauthn/browser`.
 */
export function useRegisterPasskey() {
  const client = useApiClient();
  return useAccountMutation(
    async (nickname: string): Promise<PasskeyRegistrationResult> => {
      const options = unwrap(await client.POST("/api/me/passkeys/options"));
      const credential = await startRegistration({ optionsJSON: options });
      const trimmed = nickname.trim();
      return unwrap(
        await client.POST("/api/me/passkeys", {
          body:
            trimmed === "" ? { credential } : { credential, nickname: trimmed },
        }),
      );
    },
    { gcTime: 0 },
  );
}

export function useRemovePasskey() {
  const client = useApiClient();
  return useAccountMutation(async (id: string) =>
    unwrap(
      await client.DELETE("/api/me/passkeys/{id}", {
        params: { path: { id } },
      }),
    ),
  );
}

export function useTotpSetup() {
  const client = useApiClient();
  return useAccountMutation(
    async (): Promise<TotpEnrollment> =>
      unwrap(await client.POST("/api/me/totp")),
    { gcTime: 0 },
  );
}

export function useConfirmTotp() {
  const client = useApiClient();
  return useAccountMutation(
    async (code: string): Promise<TotpConfirmResult> =>
      unwrap(await client.POST("/api/me/totp/confirm", { body: { code } })),
    { gcTime: 0 },
  );
}

export function useRemoveTotp() {
  const client = useApiClient();
  return useAccountMutation(async () =>
    unwrap(await client.DELETE("/api/me/totp")),
  );
}

export function useRegenerateRecoveryCodes() {
  const client = useApiClient();
  return useAccountMutation(
    async () =>
      unwrap(await client.POST("/api/me/recovery-codes")).recovery_codes,
    { gcTime: 0 },
  );
}

/**
 * `PUT /api/me/password`. An enrollment or recovery session sends no
 * `current_password` (0005 step 15).
 */
export function useChangePassword() {
  const client = useApiClient();
  return useAccountMutation(
    async (body: { current_password?: string; password: string }) =>
      unwrap(await client.PUT("/api/me/password", { body })),
  );
}

export function useChangeEmail() {
  const client = useApiClient();
  return useAccountMutation(async (email: string) =>
    unwrap(await client.PUT("/api/me/email", { body: { email } })),
  );
}

export function useConfirmEmail() {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (token: string) =>
      unwrap(await client.POST("/api/me/email/confirm", { body: { token } })),
    onSuccess: () =>
      Promise.all([
        queryClient.invalidateQueries({ queryKey: sessionQueryKey }),
        queryClient.invalidateQueries({ queryKey: securityQueryKey }),
      ]),
  });
}

export function useEndSession() {
  const client = useApiClient();
  return useAccountMutation(async (id: string) =>
    unwrap(
      await client.DELETE("/api/me/sessions/{id}", {
        params: { path: { id } },
      }),
    ),
  );
}

/**
 * Ends every other session of the user, one `DELETE /api/me/sessions/:id`
 * after the other, so a step-up opens at most one dialog.
 */
export function useEndOtherSessions() {
  const client = useApiClient();
  return useAccountMutation(async () => {
    const { sessions } = unwrap(await client.GET("/api/me/sessions"));
    for (const session of sessions) {
      if (session.current) continue;
      unwrap(
        await client.DELETE("/api/me/sessions/{id}", {
          params: { path: { id: session.id } },
        }),
      );
    }
  });
}

/** Links a directory account (0007 step 20). */
export function useLinkLdap() {
  const client = useApiClient();
  return useAccountMutation(
    async ({
      provider,
      username,
      password,
    }: {
      provider: string;
      username: string;
      password: string;
    }) =>
      unwrap(
        await client.POST("/api/me/identities/ldap/{provider}", {
          params: { path: { provider } },
          body: { username, password },
        }),
      ),
  );
}

/** Creates an OIDC intent (0006 step 11) and returns the authorize URL. */
export function useOidcIntent() {
  const client = useApiClient();
  return useMutation({
    mutationFn: async ({
      provider,
      purpose,
    }: {
      provider: string;
      purpose: "link" | "step_up";
    }) =>
      unwrap(
        await client.POST("/api/auth/oidc/{provider}/intents", {
          params: { path: { provider } },
          body: { purpose },
        }),
      ).url,
  });
}
