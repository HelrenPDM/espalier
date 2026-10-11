import { useId } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { linkClasses } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import {
  useRequirements,
  type QualificationRequirements,
  type Requirement,
} from "../../api/credentials";
import { usePolicies, type CurrentPolicy } from "../../api/policies";
import { useContentLang } from "../../player/contentLang";
import { formatDay } from "../../player/format";
import { Markdown } from "../../player/Markdown";
import type { ProgramView, Station } from "../../player/runtime";
import { useCurrentPlayer } from "../../player/usePlayer";
import { CredentialStatus } from "../CredentialStatus";

/** The name of a requirement's target and whether it is text of the pack. */
interface Target {
  text: string;
  fromPack: boolean;
}

/**
 * The title of the module, exam, policy, format or qualification that a
 * requirement names, or its key when the program holds no such entry.
 * Policy titles belong to the organization, every other title to the pack.
 */
function targetOf(
  requirement: Requirement,
  program: ProgramView,
  policies: CurrentPolicy[],
  qualifications: QualificationRequirements[],
): Target {
  const key = requirement.target_key;
  const pack = (text: string | undefined): Target =>
    text === undefined
      ? { text: key, fromPack: false }
      : { text, fromPack: true };
  switch (requirement.kind) {
    case "module_completed":
      return pack(
        program.modules.find((module) => String(module.number) === key)?.title,
      );
    case "assessment_passed":
      return pack(
        program.modules
          .flatMap((module) => module.exams)
          .find((exam) => exam.key === key)?.title,
      );
    case "attendance":
      return pack(
        program.companion_formats.find((format) => format.key === key)?.title,
      );
    case "qualification_held":
      return pack(qualifications.find((entry) => entry.code === key)?.title);
    case "policy_acknowledged":
      return {
        text: policies.find((policy) => policy.key === key)?.title ?? key,
        fromPack: false,
      };
  }
}

/**
 * The page that satisfies an open requirement: `/policies` for a policy,
 * the station of its position for the others, or none.
 */
function linkOf(requirement: Requirement, slug: string): string | null {
  if (requirement.kind === "policy_acknowledged") return "/policies";
  if (requirement.station_position === null) return null;
  return `/programs/${slug}/stations/${requirement.station_position}`;
}

function RequirementEntry({
  requirement,
  open,
  target,
}: {
  requirement: Requirement;
  open: boolean;
  target: Target;
}) {
  const { t } = useTranslation();
  const { program } = useCurrentPlayer();
  const lang = useContentLang();
  const label = (
    <>
      {open
        ? t(`credentialStation.todo.${requirement.kind}`)
        : t(`credentialStation.done.${requirement.kind}`)}{" "}
      <span lang={target.fromPack ? lang : undefined}>{target.text}</span>
    </>
  );
  const to = open ? linkOf(requirement, program.slug) : null;
  return (
    <li
      data-requirement-kind={requirement.kind}
      data-target-key={requirement.target_key}
    >
      {to === null ? (
        label
      ) : (
        <Link to={to} className={linkClasses}>
          {label}
        </Link>
      )}
    </li>
  );
}

function QualificationSection({
  qualification,
  qualifications,
  policies,
}: {
  qualification: QualificationRequirements;
  qualifications: QualificationRequirements[];
  policies: CurrentPolicy[];
}) {
  const { t, i18n } = useTranslation();
  const { program } = useCurrentPlayer();
  const lang = useContentLang();
  const headingId = useId();
  const openId = useId();
  const metId = useId();
  const unlocksId = useId();
  const { credential } = qualification;
  const entries = (list: Requirement[], open: boolean) =>
    list.map((requirement) => (
      <RequirementEntry
        key={`${requirement.kind}:${requirement.target_key}`}
        requirement={requirement}
        open={open}
        target={targetOf(requirement, program, policies, qualifications)}
      />
    ));

  return (
    <section
      aria-labelledby={headingId}
      data-qualification={qualification.code}
      className="rounded-lg border border-gray-300 p-4 dark:border-gray-600"
    >
      <h2
        id={headingId}
        lang={lang}
        className="text-xl font-semibold tracking-tight"
      >
        {qualification.title}
      </h2>
      {qualification.add_on && (
        <p className="mt-1 text-sm text-gray-700 dark:text-gray-300">
          {t("credentialStation.addOn")}
        </p>
      )}

      {credential === null ? (
        <p className="mt-3">{t("credentialStation.notIssued")}</p>
      ) : (
        <div className="mt-3 flex flex-wrap items-center gap-x-3 gap-y-2">
          <span>{t("credentialStation.issued")}</span>
          <CredentialStatus status={credential.status} />
          <span className="text-sm text-gray-700 dark:text-gray-300">
            {credential.valid_until === null
              ? t("credentials.noExpiry")
              : t("credentialStation.validUntil", {
                  date: formatDay(credential.valid_until, i18n.language),
                })}
          </span>
          <Link to={`/me/credentials/${credential.id}`} className={linkClasses}>
            {t("credentialStation.view")}
          </Link>
        </div>
      )}

      {qualification.open.length > 0 && (
        <>
          <h3 id={openId} className="mt-4 font-semibold">
            {t("credentialStation.open")}
          </h3>
          <ul
            aria-labelledby={openId}
            className="mt-2 list-disc space-y-1 pl-5"
          >
            {entries(qualification.open, true)}
          </ul>
        </>
      )}
      {qualification.met.length > 0 && (
        <>
          <h3 id={metId} className="mt-4 font-semibold">
            {t("credentialStation.met")}
          </h3>
          <ul aria-labelledby={metId} className="mt-2 list-disc space-y-1 pl-5">
            {entries(qualification.met, false)}
          </ul>
        </>
      )}
      {qualification.unlocks.length > 0 && (
        <>
          <h3 id={unlocksId} className="mt-4 font-semibold">
            {t("credentialStation.unlocks")}
          </h3>
          <ul
            aria-labelledby={unlocksId}
            lang={lang}
            className="mt-2 list-disc space-y-1 pl-5"
          >
            {qualification.unlocks.map((task) => (
              <li key={task}>{task}</li>
            ))}
          </ul>
        </>
      )}
    </section>
  );
}

/**
 * The credential station (task 0013, step 23): the station intro and, per
 * qualification of the program, the credential of the learner with its
 * status and a link to its page, the open requirements with a link to the
 * station or page that satisfies each, the met requirements and the tasks
 * the credential unlocks. Titles of the pack carry the content language;
 * policy titles come from the organization.
 */
export function CredentialStation({ station }: { station: Station }) {
  const { t } = useTranslation();
  const { program } = useCurrentPlayer();
  const requirements = useRequirements(program.slug);
  const policies = usePolicies();

  return (
    <div className="space-y-6">
      {station.intro && <Markdown>{station.intro}</Markdown>}
      {requirements.isPending ? (
        <LoadingStatus text={t("credentialStation.loading")} />
      ) : requirements.isError ? (
        <p role="alert" className="text-gray-700 dark:text-gray-300">
          {t("credentialStation.loadFailed")}
        </p>
      ) : requirements.data.length === 0 ? (
        <p className="text-gray-700 dark:text-gray-300">
          {t("credentialStation.none")}
        </p>
      ) : (
        requirements.data.map((qualification) => (
          <QualificationSection
            key={qualification.code}
            qualification={qualification}
            qualifications={requirements.data}
            policies={policies.data ?? []}
          />
        ))
      )}
    </div>
  );
}
