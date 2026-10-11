import { useTranslation } from "react-i18next";
import { formatDay } from "../format";
import { Markdown } from "../Markdown";
import { ProvenanceBadge } from "../ProvenanceBadge";
import type { Block } from "../runtime";
import { BlockFrame } from "./BlockFrame";

/**
 * A place for a policy of the organization (README section 7, rule 8).
 * When the block carries the current version of its policy, it renders
 * the policy text with a badge that names the policy as its source, the
 * version number and the effective date; the citations of the pack belong
 * to the placeholder text and stay out. Without a published version it
 * shows its own body with the `placeholder` badge and the placeholder key.
 * The policy text carries no `lang` and inherits the language of the
 * document; the body of the block is pack text and carries the language
 * of the program.
 */
export function PlaceholderBlock({ block }: { block: Block }) {
  const { t, i18n } = useTranslation();
  const { policy } = block;

  if (policy === null)
    return (
      <BlockFrame
        block={{ ...block, provenance: "placeholder" }}
        label={t("blocks.placeholder")}
        className="rounded-md border border-dashed border-gray-400 p-4 dark:border-gray-500"
      >
        <Markdown>{block.body}</Markdown>
      </BlockFrame>
    );

  return (
    <BlockFrame
      block={{ ...block, citations: [] }}
      label={t("blocks.placeholder")}
      badge={
        <ProvenanceBadge provenance={block.provenance} policyKey={policy.key} />
      }
      className="rounded-md border border-gray-300 p-4 dark:border-gray-600"
    >
      <Markdown lang={null}>{policy.body}</Markdown>
      <p className="mt-2 text-sm text-gray-700 dark:text-gray-300">
        {t("policies.version", {
          number: policy.number,
          date: formatDay(policy.effective_from, i18n.language),
        })}
      </p>
    </BlockFrame>
  );
}
