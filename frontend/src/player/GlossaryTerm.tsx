import { useContext } from "react";
import { useNavigate } from "react-router";
import { FOCUS_RING } from "../app/formStyles";
import { useContentLang } from "./contentLang";
import { Tooltip } from "./Tooltip";
import { PlayerContext } from "./usePlayer";
import type { GlossaryEntry } from "./runtime";

function TermButton({
  programSlug,
  term,
  text,
}: {
  programSlug: string;
  term: GlossaryEntry;
  text: string;
}) {
  const navigate = useNavigate();
  const lang = useContentLang();
  return (
    <Tooltip text={term.short_text} lang={lang}>
      {(describedBy) => (
        <button
          type="button"
          aria-describedby={describedBy}
          onClick={() =>
            navigate(`/programs/${programSlug}/glossary#${term.slug}`)
          }
          className={`cursor-help rounded-sm font-medium text-accent-700 underline decoration-dotted underline-offset-4 hover:text-accent-600 dark:text-accent-100 dark:hover:text-accent-50 ${FOCUS_RING}`}
        >
          {text}
        </button>
      )}
    </Tooltip>
  );
}

/**
 * A glossary term in Markdown (README section 7, rule 9): a button with the
 * label, the short text as its accessible description and in a tooltip, and
 * navigation to the glossary entry through React Router, so the memory
 * router of the SCORM package serves it too. Outside a player, or for a
 * slug the glossary lacks, the label renders as text.
 */
export function GlossaryTerm({
  slug,
  label,
}: {
  slug: string;
  label: string | null;
}) {
  const player = useContext(PlayerContext);
  const term = player?.program.glossary.find((entry) => entry.slug === slug);
  const text = label ?? term?.label ?? slug;
  if (player === null || term === undefined) return <span>{text}</span>;
  return (
    <TermButton programSlug={player.program.slug} term={term} text={text} />
  );
}
