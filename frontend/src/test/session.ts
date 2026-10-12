import { vi } from "vitest";
import type { SessionFlags, SessionPayload } from "../api/session";
import type { SessionContextValue } from "../auth/SessionProvider";

type Overrides = Partial<Omit<SessionContextValue, "flags">> & {
  flags?: Partial<SessionFlags>;
};

/** A fixed SessionContext value: a learner in a full demo session. */
export function sessionValue(overrides: Overrides = {}): SessionContextValue {
  const { flags, ...rest } = overrides;
  return {
    user: {
      id: "8a4c7a5e-2f5b-4d6e-9c1a-3b2d4e5f6a7b",
      displayName: "Test person 1",
      email: null,
    },
    roles: ["learner"],
    sessionStrength: "demo",
    authMethods: ["demo"],
    providerKey: null,
    pending: null,
    csrfToken: "token-1",
    providers: [],
    loading: false,
    signOut: vi.fn(async () => {}),
    ...rest,
    flags: {
      demo: false,
      localAccounts: true,
      signup: "closed",
      adminPasskeyRequired: false,
      testNotes: false,
      feedbackFreeText: false,
      ...flags,
    },
  };
}

type PayloadSession = NonNullable<SessionPayload["session"]>;

export type PayloadOverrides = Partial<
  Omit<SessionPayload, "session" | "flags">
> & {
  session?: Partial<PayloadSession> | null;
  flags?: Partial<SessionPayload["flags"]>;
};

export const TEST_USER = {
  id: "5b1f7c2e-3d4a-4e6b-8c9d-0e1f2a3b4c5d",
  display_name: "Ada Example",
  email: "ada@example.test",
  locale: "en",
} as const;

/**
 * A session payload of `GET /api/session` (0004 step 35). Without
 * overrides it is signed out; `session` merges into an `mfa` session row.
 */
export function sessionPayload(
  overrides: PayloadOverrides = {},
): SessionPayload {
  const { session, flags, ...rest } = overrides;
  return {
    user: null,
    roles: [],
    pending: null,
    csrf_token: "csrf-1",
    providers: [],
    ...rest,
    session:
      session === undefined || session === null
        ? null
        : {
            strength: "mfa",
            auth_methods: ["passkey"],
            provider_key: null,
            recent_auth_until: null,
            expires_at: "2026-10-12T10:00:00Z",
            idle_timeout_minutes: 60,
            ...session,
          },
    flags: {
      demo: false,
      local_accounts: true,
      signup: "closed",
      admin_passkey_required: false,
      test_notes: false,
      feedback_free_text: false,
      ...flags,
    },
  };
}

/** A signed-in payload of strength `strength` for `TEST_USER`. */
export function signedInPayload(
  strength: PayloadSession["strength"] = "mfa",
  overrides: PayloadOverrides = {},
): SessionPayload {
  return sessionPayload({
    user: { ...TEST_USER },
    roles: ["learner"],
    ...overrides,
    session: { strength, ...overrides.session },
  });
}
