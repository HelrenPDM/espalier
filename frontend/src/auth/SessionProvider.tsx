import { useQueryClient } from "@tanstack/react-query";
import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  type ReactNode,
} from "react";
import { useNavigate } from "react-router";
import type {
  Provider,
  Role,
  SessionStrength,
  SessionUser,
} from "../api/session";
import { deleteSession, useSessionQuery } from "../api/sessionHooks";

export interface SessionContextValue {
  user: SessionUser | null;
  roles: Role[];
  sessionStrength: SessionStrength | null;
  csrfToken: string | null;
  providers: Provider[];
  flags: { demo: boolean };
  /** True while the session query loads for the first time. */
  loading: boolean;
  signOut: () => Promise<void>;
}

// The component tests render the guards and the layout inside
// SessionContext.Provider, so this file exports the context and its hook
// next to the provider. Fast refresh then reloads the page for this file.
// oxlint-disable-next-line react/only-export-components
export const SessionContext = createContext<SessionContextValue | null>(null);

/** Provides the session of `GET /api/session` and `signOut()`. */
export function SessionProvider({ children }: { children: ReactNode }) {
  const query = useSessionQuery();
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const { data, isPending, refetch } = query;

  // Every 2xx answer counts as success: 204, or 200 with the `logout_url`
  // that 0011 follows. On a failed request the session stays as it is, and
  // the person can sign out again.
  const signOut = useCallback(async () => {
    let response: Response;
    try {
      response = await deleteSession();
    } catch {
      return;
    }
    if (!response.ok) return;
    // The navigation comes before the refetch: a signed-out session on a
    // page behind RequireAuth would otherwise redirect to /sign-in with
    // that page in `return_to`. Without data, RequireAuth only waits.
    queryClient.clear();
    await navigate("/sign-in");
    await refetch();
  }, [navigate, queryClient, refetch]);

  const value = useMemo<SessionContextValue>(
    () => ({
      user: data?.user ?? null,
      roles: data?.roles ?? [],
      sessionStrength: data?.sessionStrength ?? null,
      csrfToken: data?.csrfToken ?? null,
      providers: data?.providers ?? [],
      flags: data?.flags ?? { demo: false },
      loading: isPending,
      signOut,
    }),
    [data, isPending, signOut],
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
