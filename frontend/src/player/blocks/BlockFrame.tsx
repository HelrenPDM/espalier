import type { ReactNode } from "react";
import { Citations } from "../Citations";
import { ProvenanceBadge } from "../ProvenanceBadge";
import type { Block } from "../runtime";

/**
 * The frame of every block: an optional label, the provenance badge, the
 * content and the citations. `badge` replaces the provenance badge of the
 * block.
 */
export function BlockFrame({
  block,
  label,
  badge,
  className = "",
  children,
}: {
  block: Block;
  label?: ReactNode;
  badge?: ReactNode;
  className?: string;
  children: ReactNode;
}) {
  return (
    <div className={className} data-block-kind={block.kind}>
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        {label === undefined ? (
          <span />
        ) : (
          <p className="text-sm font-semibold text-gray-800 dark:text-gray-200">
            {label}
          </p>
        )}
        {badge ?? (
          <ProvenanceBadge
            provenance={block.provenance}
            placeholderKey={block.placeholder_key}
          />
        )}
      </div>
      {children}
      <Citations citations={block.citations} />
    </div>
  );
}
