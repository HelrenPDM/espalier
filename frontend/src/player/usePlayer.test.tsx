import { screen, waitFor } from "@testing-library/react";
import { useState } from "react";
import { describe, expect, test } from "vitest";
import { fakeRuntime, IDS, renderPlayer } from "../test/player";
import { emptyResumeState, type ResumeState } from "./runtime";
import { useCurrentPlayer } from "./usePlayer";

/**
 * Task 0014 step 5: `refreshPath()` takes over a path that the server set
 * (the default path of a self-assessment) from `loadState()` and replaces
 * only `path`, without a `saveState` call, which `PlatformRuntime` would
 * send as a manual choice. It resolves whether the player holds the loaded
 * path, so a caller can try again or tell the learner.
 */
function PathProbe() {
  const { state, refreshPath } = useCurrentPlayer();
  const [results, setResults] = useState<boolean[]>([]);
  return (
    <div>
      <p data-testid="path">{state.path}</p>
      <p data-testid="visited">{state.visitedStations.join(",")}</p>
      <p data-testid="results">{results.join(",")}</p>
      <button
        type="button"
        onClick={() =>
          void refreshPath().then((result) =>
            setResults((current) => [...current, result]),
          )
        }
      >
        Refresh
      </button>
    </div>
  );
}

const loaded = (overrides: Partial<ResumeState> = {}): ResumeState => ({
  ...emptyResumeState("full"),
  visitedStations: [1, 2],
  ...overrides,
});

describe("refreshPath", () => {
  test("replaces only the path with the loaded one and saves nothing", async () => {
    const runtime = fakeRuntime({ state: loaded() });
    const { user } = renderPlayer(<PathProbe />, { runtime });
    await screen.findByRole("button", { name: "Refresh" });
    const saves = runtime.saveState.mock.calls.length;
    runtime.loadState.mockResolvedValueOnce(
      loaded({
        path: "short",
        visitedStations: [],
        completedModules: [IDS.module1],
      }),
    );

    await user.click(screen.getByRole("button", { name: "Refresh" }));

    await waitFor(() =>
      expect(screen.getByTestId("path")).toHaveTextContent("short"),
    );
    expect(screen.getByTestId("visited")).toHaveTextContent("1,2");
    expect(runtime.saveState.mock.calls.length).toBe(saves);
    expect(screen.getByTestId("results")).toHaveTextContent("true");
  });

  test("resolves true also when the loaded path is the current one", async () => {
    const runtime = fakeRuntime({ state: loaded() });
    const { user } = renderPlayer(<PathProbe />, { runtime });
    await screen.findByRole("button", { name: "Refresh" });
    const saves = runtime.saveState.mock.calls.length;
    runtime.loadState.mockResolvedValueOnce(loaded());

    await user.click(screen.getByRole("button", { name: "Refresh" }));

    await waitFor(() =>
      expect(screen.getByTestId("results")).toHaveTextContent("true"),
    );
    expect(screen.getByTestId("path")).toHaveTextContent("full");
    expect(runtime.saveState.mock.calls.length).toBe(saves);
  });

  test("a failed or empty load leaves the path unchanged and resolves false", async () => {
    const runtime = fakeRuntime({ state: loaded() });
    const { user } = renderPlayer(<PathProbe />, { runtime });
    await screen.findByRole("button", { name: "Refresh" });
    runtime.loadState
      .mockRejectedValueOnce(new Error("offline"))
      .mockResolvedValueOnce(null);

    await user.click(screen.getByRole("button", { name: "Refresh" }));
    await user.click(screen.getByRole("button", { name: "Refresh" }));

    await waitFor(() => expect(runtime.loadState).toHaveBeenCalledTimes(3));
    await waitFor(() =>
      expect(screen.getByTestId("results")).toHaveTextContent("false,false"),
    );
    expect(screen.getByTestId("path")).toHaveTextContent("full");
    expect(runtime.saveState).toHaveBeenCalledTimes(1);
  });
});
