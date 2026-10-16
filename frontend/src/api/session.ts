import type { Client } from "openapi-fetch";
import type { paths } from "./paths";

export type SessionPayload =
  paths["/api/session"]["get"]["responses"][200]["content"]["application/json"];

type PayloadSession = NonNullable<SessionPayload["session"]>;
type PayloadProvider = SessionPayload["providers"][number];

export type Role = SessionPayload["roles"][number];
export type SessionStrength = PayloadSession["strength"];
export type AuthMethod = PayloadSession["auth_methods"][number];
export type Signup = SessionPayload["flags"]["signup"];
export type MediaEmbedConsent = SessionPayload["flags"]["media_embed_consent"];

/**
 * A public provider entry (README section 6.12). The pages decide by `kind`
 * alone: `redirect` renders a button, `credentials` a form.
 */
export interface Provider {
  key: string;
  type: PayloadProvider["type"];
  kind: PayloadProvider["kind"];
  label: string;
  startUrl: string;
}

export interface SessionUser {
  id: string;
  displayName: string | null;
  email: string | null;
}

/** The pending second-factor state after a first factor. */
export interface PendingSecondFactor {
  next: "second_factor";
  expiresAt: string;
}

export interface SessionFlags {
  demo: boolean;
  localAccounts: boolean;
  signup: Signup;
  adminPasskeyRequired: boolean;
  /** `TEST_NOTES`: the SPA records the test session notes in the browser (0014). */
  testNotes: boolean;
  /** `FEEDBACK_FREE_TEXT`: the feedback station shows free-text questions (0014). */
  feedbackFreeText: boolean;
  /**
   * `MEDIA_EMBED_CONSENT` (0018): `click` loads the player of a streaming
   * service after the learner agrees, `auto` with the page.
   */
  mediaEmbedConsent: MediaEmbedConsent;
}

/** The client shape of the session that the query cache holds. */
export interface Session {
  /** `null` when signed out or while a second factor is pending. */
  user: SessionUser | null;
  roles: Role[];
  sessionStrength: SessionStrength | null;
  authMethods: AuthMethod[];
  /** The provider of the session row; `null` for local and demo sessions. */
  providerKey: string | null;
  /**
   * The end of the window of the last second factor (README section 6.4),
   * or `null` outside it. The media upload opens the step-up dialog before
   * it sends a body when it lies in the past (0018).
   */
  recentAuthUntil: string | null;
  pending: PendingSecondFactor | null;
  /** The value for the `x-csrf-token` header. It lives only in the query cache. */
  csrfToken: string;
  providers: Provider[];
  flags: SessionFlags;
}

export const sessionQueryKey = ["session"] as const;

export function sessionQueryOptions(client: Client<paths>) {
  return {
    queryKey: sessionQueryKey,
    queryFn: async (): Promise<Session> => {
      const { data, response } = await client.GET("/api/session");
      if (data === undefined)
        throw new Error(`GET /api/session answered ${response.status}`);
      return toSession(data);
    },
  };
}

const PROVIDER_KINDS: readonly string[] = ["redirect", "credentials"];

/**
 * The one function that maps the session payload to the client shape. It
 * copies the members it knows one by one into new objects, so no key of the
 * payload, such as `__proto__`, reaches an object of the SPA (ASVS 15.3.6).
 * A provider entry with an unknown `kind` is dropped.
 */
export function toSession(payload: SessionPayload): Session {
  const { user, session, pending, flags } = payload;
  return {
    user: user
      ? { id: user.id, displayName: user.display_name, email: user.email }
      : null,
    roles: Array.from(payload.roles),
    sessionStrength: session ? session.strength : null,
    authMethods: session ? Array.from(session.auth_methods) : [],
    providerKey: session ? session.provider_key : null,
    recentAuthUntil: session ? session.recent_auth_until : null,
    pending: pending
      ? { next: pending.next, expiresAt: pending.expires_at }
      : null,
    csrfToken: payload.csrf_token,
    providers: payload.providers
      .filter((provider) => PROVIDER_KINDS.includes(provider.kind))
      .map((provider) => ({
        key: provider.key,
        type: provider.type,
        kind: provider.kind,
        label: provider.label,
        startUrl: provider.start_url,
      })),
    flags: {
      demo: flags.demo,
      localAccounts: flags.local_accounts,
      signup: flags.signup,
      adminPasskeyRequired: flags.admin_passkey_required,
      testNotes: flags.test_notes,
      feedbackFreeText: flags.feedback_free_text,
      mediaEmbedConsent: flags.media_embed_consent,
    },
  };
}
