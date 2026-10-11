import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { useRuntime } from "./RuntimeContext";
import {
  emptyResumeState,
  type ProgramView,
  type ResumeState,
  type Runtime,
} from "./runtime";

/** A loaded player: the program, the state and the ways to change it. */
export interface Player {
  runtime: Runtime;
  program: ProgramView;
  state: ResumeState;
  /**
   * Applies `change` to the current state and passes the result through
   * `saveState`. A change that returns the state unchanged saves nothing.
   */
  update(change: (state: ResumeState) => ResumeState): void;
  /**
   * Calls `loadState()` and replaces only `evidencedObjectives`, without a
   * `saveState` call, because the list comes from the runtime. A failed or
   * empty load leaves the list unchanged.
   */
  refreshEvidence(): Promise<void>;
  /** The last `saveState` call failed. */
  saveFailed: boolean;
}

export type PlayerLoad =
  | { status: "loading" }
  | { status: "error"; error: unknown }
  | { status: "ready"; player: Player };

interface Loaded {
  program: ProgramView;
  state: ResumeState;
}

const LOADING = { status: "loading" } as const;

// One load per runtime and slug, so a remount (and the double effect of
// StrictMode) creates no second enrollment.
const loads = new WeakMap<Runtime, Map<string, Promise<Loaded>>>();

function loadOnce(runtime: Runtime, slug: string): Promise<Loaded> {
  let bySlug = loads.get(runtime);
  if (bySlug === undefined) {
    bySlug = new Map();
    loads.set(runtime, bySlug);
  }
  let load = bySlug.get(slug);
  if (load === undefined) {
    load = (async () => {
      const program = await runtime.loadProgram(slug);
      const state = (await runtime.loadState()) ?? emptyResumeState("full");
      // The first save writes the runtime's resume entry once a program
      // page or a station has been opened.
      await runtime.saveState(state).catch(() => undefined);
      return { program, state };
    })();
    bySlug.set(slug, load);
    // A failed load may be repeated by the next mount.
    load.catch(() => bySlug.delete(slug));
  }
  return load;
}

/**
 * Loads the program `slug` and the resume state once per runtime and keeps
 * the state in React state. When `loadState` resolves `null`, the player
 * starts on the full path with empty lists.
 */
export function usePlayer(slug: string): PlayerLoad {
  const runtime = useRuntime();
  // The result of the load of `runtime` and `slug`; a result of another
  // runtime or slug counts as loading.
  const [result, setResult] = useState<
    | ({ runtime: Runtime; slug: string } & (
        { status: "error"; error: unknown } | ({ status: "ready" } & Loaded)
      ))
    | null
  >(null);
  const [saveFailed, setSaveFailed] = useState(false);
  const stateRef = useRef<ResumeState | null>(null);
  const load =
    result !== null && result.runtime === runtime && result.slug === slug
      ? result
      : LOADING;

  useEffect(() => {
    let current = true;
    loadOnce(runtime, slug).then(
      (loaded) => {
        if (!current) return;
        stateRef.current = loaded.state;
        setResult({ runtime, slug, status: "ready", ...loaded });
      },
      (error: unknown) => {
        if (current) setResult({ runtime, slug, status: "error", error });
      },
    );
    return () => {
      current = false;
    };
  }, [runtime, slug]);

  const setState = useCallback((state: ResumeState) => {
    stateRef.current = state;
    setResult((result) =>
      result !== null && result.status === "ready"
        ? { ...result, state }
        : result,
    );
  }, []);

  const update = useCallback(
    (change: (state: ResumeState) => ResumeState) => {
      const state = stateRef.current;
      if (state === null) return;
      const next = change(state);
      if (next === state) return;
      setState(next);
      runtime.saveState(next).then(
        () => setSaveFailed(false),
        () => setSaveFailed(true),
      );
    },
    [runtime, setState],
  );

  const refreshEvidence = useCallback(async () => {
    let loaded: ResumeState | null;
    try {
      loaded = await runtime.loadState();
    } catch {
      return;
    }
    const state = stateRef.current;
    if (loaded === null || state === null) return;
    setState({
      ...state,
      evidencedObjectives: [...loaded.evidencedObjectives],
    });
  }, [runtime, setState]);

  return useMemo((): PlayerLoad => {
    if (load.status === "loading") return { status: "loading" };
    if (load.status === "error") return { status: "error", error: load.error };
    return {
      status: "ready",
      player: {
        runtime,
        program: load.program,
        state: load.state,
        update,
        refreshEvidence,
        saveFailed,
      },
    };
  }, [load, runtime, update, refreshEvidence, saveFailed]);
}

/** The player of the program routes, which `PlayerProvider` provides. */
export const PlayerContext = createContext<Player | null>(null);

export function useCurrentPlayer(): Player {
  const player = useContext(PlayerContext);
  if (player === null)
    throw new Error("useCurrentPlayer outside PlayerProvider");
  return player;
}
