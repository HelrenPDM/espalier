import { useTranslation } from "react-i18next";
import { Markdown } from "../../player/Markdown";
import type { Station } from "../../player/runtime";

/**
 * A panel with the station title for the kinds whose components later
 * tasks add: the self-assessment and the feedback station (0014), the
 * credential station (0013) and the companion formats (0014).
 */
export function PendingStation({ station }: { station: Station }) {
  const { t } = useTranslation();
  return (
    <div className="rounded-lg border border-dashed border-gray-400 p-4 dark:border-gray-500">
      <p className="font-semibold">{station.title}</p>
      {station.intro && <Markdown className="mt-2">{station.intro}</Markdown>}
      <p className="mt-2 text-sm text-gray-700 dark:text-gray-300">
        {t("station.pending")}
      </p>
    </div>
  );
}
