import type { Block, Citation, GlossaryEntry } from "../player/runtime";
import type { PackMediaEntry } from "./media";
import type { PackPayload, PayloadFormat, PayloadModule } from "./standalone";

/** The current version of a policy, the `policy` field of a placeholder block. */
export type PolicyText = NonNullable<Block["policy"]>;

/** A competence area that a module covers in another place (`areas_elsewhere`). */
export interface AreaElsewhere {
  where: string;
  reason: string;
}

/**
 * A media file of a SCORM package (task 0018, step 17): its delivery file
 * below `media/` with a URL relative to `index.html`, and its facts.
 */
export type ScormMediaEntry = PackMediaEntry & { url: string; mime: string };

/**
 * `content.json` of a SCORM package (task 0016, steps 1 and 9): the
 * content of one module in the shape of `Espalier.Interop.Payload.module/3`
 * plus `schema` and `policies`. `module` is the module of the normalized
 * pack payload with its lessons, rules, items with their answer keys,
 * assessments, objectives and `areas_elsewhere`; `formats` holds the
 * companion formats that name an objective of the module; `policies` maps
 * the `placeholder_key` of a block to the current version of its policy.
 * `media` maps every `media/` path that a block of the module references
 * to its file in the package (task 0018); external files and embeds stay
 * URLs in the blocks.
 */
export interface ScormContent {
  schema: 1;
  program: { slug: string; title: string; locale: string };
  module: PayloadModule & { areas_elsewhere: Record<string, AreaElsewhere> };
  glossary: GlossaryEntry[];
  sources: Citation["source"][];
  formats: PayloadFormat[];
  policies: Record<string, PolicyText>;
  media: Record<string, ScormMediaEntry>;
}

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/**
 * True when `value` has the members of `content.json` that the SCORM entry
 * and the runtimes read at the top level.
 */
export function isScormContent(value: unknown): value is ScormContent {
  if (!isRecord(value) || value.schema !== 1) return false;
  const { program, module, policies, media } = value;
  return (
    isRecord(program) &&
    typeof program.slug === "string" &&
    typeof program.title === "string" &&
    typeof program.locale === "string" &&
    isRecord(module) &&
    typeof module.number === "number" &&
    ["lessons", "objectives", "rules", "items", "assessments"].every((member) =>
      Array.isArray(module[member]),
    ) &&
    ["glossary", "sources", "formats"].every((member) =>
      Array.isArray(value[member]),
    ) &&
    isRecord(policies) &&
    isRecord(media)
  );
}

/**
 * The pack payload of the package: the program of `content.json` with one
 * module station and the module, for `payloadToProgramView` and the
 * evaluation of `StandaloneRuntime`. A package has no self-assessment, no
 * segments and no other station, and it carries no pack version. The
 * media of its blocks resolve through `content.media` without a policy,
 * which `ScormRuntime` passes with the payload.
 */
export function contentPayload(content: ScormContent): PackPayload {
  return {
    key: content.program.slug,
    title: content.program.title,
    locale: content.program.locale,
    version: "",
    sources: content.sources,
    glossary: content.glossary,
    segments: [],
    stations: [
      {
        kind: "module",
        title: content.module.title,
        module: content.module.number,
        config: {},
      },
    ],
    formats: content.formats,
    modules: [content.module],
  };
}
