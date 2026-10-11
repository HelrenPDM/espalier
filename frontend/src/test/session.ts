import { vi } from "vitest";
import type { SessionContextValue } from "../auth/SessionProvider";

/** A fixed SessionContext value: a learner in a full demo session. */
export function sessionValue(
  overrides: Partial<SessionContextValue> = {},
): SessionContextValue {
  return {
    user: {
      id: "8a4c7a5e-2f5b-4d6e-9c1a-3b2d4e5f6a7b",
      displayName: "Test person 1",
    },
    roles: ["learner"],
    sessionStrength: "demo",
    csrfToken: "token-1",
    providers: [],
    flags: { demo: false },
    loading: false,
    signOut: vi.fn(async () => {}),
    ...overrides,
  };
}
