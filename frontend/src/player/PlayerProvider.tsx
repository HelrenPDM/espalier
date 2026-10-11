import type { ReactNode } from "react";
import { useTranslation } from "react-i18next";
import { LoadingStatus } from "../app/LoadingStatus";
import { PlayerContext, usePlayer } from "./usePlayer";

/** The HTTP status of a failed load, when the error carries one. */
function statusOf(error: unknown): number | null {
  if (typeof error !== "object" || error === null || !("status" in error))
    return null;
  return typeof error.status === "number" ? error.status : null;
}

/**
 * Loads the program `slug` through the runtime of `RuntimeContext` and
 * provides one player to every page below it, so the program page, the
 * stations, the glossary and the handbook share one state.
 */
export function PlayerProvider({
  slug,
  children,
}: {
  slug: string;
  children: ReactNode;
}) {
  const { t } = useTranslation();
  const load = usePlayer(slug);

  if (load.status === "loading")
    return <LoadingStatus text={t("player.loading")} />;
  if (load.status === "error")
    return (
      <section className="max-w-2xl">
        <h1 className="text-2xl font-semibold tracking-tight">
          {t("player.loadFailed.title")}
        </h1>
        <p role="alert" className="mt-4 text-gray-700 dark:text-gray-300">
          {statusOf(load.error) === 404
            ? t("player.loadFailed.notFound")
            : t("player.loadFailed.text")}
        </p>
      </section>
    );

  return (
    <PlayerContext.Provider value={load.player}>
      {load.player.saveFailed && (
        <p
          role="alert"
          className="no-print mb-6 rounded-md border border-amber-600 bg-amber-50 px-4 py-2 text-sm text-amber-900 dark:border-amber-400 dark:bg-gray-900 dark:text-amber-200"
        >
          {t("player.saveFailed")}
        </p>
      )}
      {children}
    </PlayerContext.Provider>
  );
}
