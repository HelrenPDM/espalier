import { createContext, useContext } from "react";
import type { Runtime } from "./runtime";

/**
 * The runtime of the player: `PlatformRuntime` in the platform build (provided
 * by `src/learner/ProgramRoute.tsx`), `StandaloneRuntime` in the admin
 * preview and a SCORM runtime in the package.
 */
export const RuntimeContext = createContext<Runtime | null>(null);

export function useRuntime(): Runtime {
  const runtime = useContext(RuntimeContext);
  if (runtime === null) throw new Error("useRuntime outside RuntimeContext");
  return runtime;
}
