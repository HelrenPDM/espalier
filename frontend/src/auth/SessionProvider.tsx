import { useQueryClient } from "@tanstack/react-query";
import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react";
import { useNavigate } from "react-router";
import { useApiClient } from "../api/apiClientContext";
import type {
  AuthMethod,
  PendingSecondFactor,
  Provider,
  Role,
  Session,
  SessionFlags,
  SessionStrength,
  SessionUser,
} from "../api/session";
import { deleteSession, useSessionQuery } from "../api/sessionHooks";
import {
  clearAccountData,
  refreshSession,
  sessionChanged,
  useSessionTabSync,
} from "./sessionEvents";

export interface SessionContextValue {
  user: SessionUser | null;
  roles: Role[];
  sessionStrength: SessionStrength | null;
  authMethods: AuthMethod[];
  providerKey: string | null;
  pending: PendingSecondFactor | null;
  csrfToken: string | null;
  providers: Provider[];
  flags: SessionFlags;
  /** True while the session query loads for the first time and during a sign-out. */
  loading: boolean;
  signOut: () => Promise<void>;
}

type SessionData = Omit<SessionContextValue, "loading" | "signOut">;

/** The values of the context for the cached session, or before the first answer. */
function sessionValue(data: Session | undefined): SessionData {
  return {
    user: data?.user ?? null,
    roles: data?.roles ?? [],
    sessionStrength: data?.sessionStrength ?? null,
    authMethods: data?.authMethods ?? [],
    providerKey: data?.providerKey ?? null,
    pending: data?.pending ?? null,
    csrfToken: data?.csrfToken ?? null,
    providers: data?.providers ?? [],
    flags: data?.flags ?? DEFAULT_FLAGS,
  };
}

/** The flags before the first answer: the server defaults. */
const DEFAULT_FLAGS: SessionFlags = {
  demo: false,
  localAccounts: true,
  signup: "closed",
  adminPasskeyRequired: false,
  testNotes: false,
  feedbackFreeText: false,
};

const SIGNING_OUT = sessionValue(undefined);

// The component tests render the guards and the layout inside
// SessionContext.Provider, so this file exports the context and its hook
// next to the provider. Fast refresh then reloads the page for this file.
// oxlint-disable-next-line react/only-export-components
export const SessionContext = createContext<SessionContextValue | null>(null);

/**
 * Provides the session of `GET /api/session` and `signOut()`, and follows
 * the session changes of other tabs (`useSessionTabSync`).
 */
export function SessionProvider({ children }: { children: ReactNode }) {
  const query = useSessionQuery();
  const queryClient = useQueryClient();
  const client = useApiClient();
  const navigate = useNavigate();
  const { data, isPending } = query;
  // From the end of a session until the refetch after the navigation to
  // /sign-in, the tree sees a loading session. The query cache reports the
  // reset on its own tick, and a page that read the old session in between
  // would navigate away from /sign-in again.
  const [signingOut, setSigningOut] = useState(false);

  // Clears the account data, opens /sign-in and then refetches the session,
  // so a page behind RequireAuth does not redirect to /sign-in with itself
  // in `return_to` first. `broadcast` tells the other tabs.
  const leave = useCallback(
    async (broadcast: boolean) => {
      clearAccountData(queryClient);
      setSigningOut(true);
      try {
        await navigate("/sign-in");
        if (broadcast) await sessionChanged("signed-out", queryClient, client);
        else await refreshSession(queryClient, client).catch(() => undefined);
      } finally {
        setSigningOut(false);
      }
    },
    [client, navigate, queryClient],
  );

  useSessionTabSync(() => leave(false));

  // On a failed request the session stays as it is, and the person can
  // sign out again. With a `logout_url` the provider ends its session and
  // redirects to /signed-out (0006 step 13, ASVS 7.6.1); the account data
  // leaves the cache before the navigation.
  const signOut = useCallback(async () => {
    let logoutUrl: string | null;
    try {
      logoutUrl = await deleteSession(client);
    } catch {
      return;
    }
    if (logoutUrl === null) {
      await leave(true);
      return;
    }
    clearAccountData(queryClient);
    setSigningOut(true);
    void sessionChanged("signed-out", queryClient, client);
    window.location.assign(logoutUrl);
  }, [client, leave, queryClient]);

  const value = useMemo<SessionContextValue>(
    () => ({
      ...(signingOut ? SIGNING_OUT : sessionValue(data)),
      loading: signingOut || isPending,
      signOut,
    }),
    [data, isPending, signOut, signingOut],
  );

  return (
    <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
  );
}

// oxlint-disable-next-line react/only-export-components
export function useSession(): SessionContextValue {
  const value = useContext(SessionContext);
  if (value === null)
    throw new Error("useSession needs a SessionContext provider");
  return value;
}
