import type { Client } from "openapi-fetch";
import type { paths } from "./paths";

type SessionPayload =
  paths["/api/session"]["get"]["responses"][200]["content"]["application/json"];

export type Role = SessionPayload["roles"][number];
export type SessionStrength = NonNullable<
  SessionPayload["session"]
>["strength"];
/** A public provider entry as received (README section 6.12); 0011 renders them. */
export type Provider = SessionPayload["providers"][number];

export interface SessionUser {
  id: string;
  displayName: string | null;
}

/** The client shape of the session that the query cache holds. */
export interface Session {
  /** `null` when signed out or while a second factor is pending. */
  user: SessionUser | null;
  roles: Role[];
  sessionStrength: SessionStrength | null;
  /** The value for the `x-csrf-token` header. It lives only in the query cache. */
  csrfToken: string;
  providers: Provider[];
  flags: { demo: boolean };
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

/**
 * The one function that maps the session payload to the client shape. It
 * copies the members it knows one by one into new objects, so no key of the
 * payload, such as `__proto__`, reaches an object of the SPA (ASVS 15.3.6).
 */
export function toSession(payload: SessionPayload): Session {
  const { user, session } = payload;
  return {
    user: user ? { id: user.id, displayName: user.display_name } : null,
    roles: Array.from(payload.roles),
    sessionStrength: session ? session.strength : null,
    csrfToken: payload.csrf_token,
    providers: payload.providers.map((provider) => ({
      key: provider.key,
      type: provider.type,
      kind: provider.kind,
      label: provider.label,
      start_url: provider.start_url,
    })),
    flags: { demo: payload.flags.demo },
  };
}
