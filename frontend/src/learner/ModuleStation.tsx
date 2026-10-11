import { useCallback, useState } from "react";
import { useTranslation } from "react-i18next";
import { buttonClasses } from "../app/formStyles";
import { PracticeItem } from "../player/items/PracticeItem";
import { useContentLang } from "../player/contentLang";
import { ObjectivesPanel } from "../player/objectives/ObjectivesPanel";
import { statusCounts } from "../player/objectives/status";
import { PathSwitch } from "../player/PathSwitch";
import { revealTargets } from "../player/pathLogic";
import {
  AssessmentsOpenError,
  type ItemFeedback,
  type ItemView,
  type Lesson,
  type ModuleView,
  type OpenAssessment,
  type Station,
} from "../player/runtime";
import { useCurrentPlayer } from "../player/usePlayer";
import { CompletionSummary } from "./CompletionSummary";
import { ExamSection } from "./ExamSection";
import { LessonSection } from "./LessonSection";
import { RulesRecap } from "./RulesRecap";

function ModuleContent({ module }: { module: ModuleView }) {
  const { t } = useTranslation();
  const { runtime, program, state, update, refreshEvidence } =
    useCurrentPlayer();
  const [revealCounts, setRevealCounts] = useState<Record<string, number>>({});
  const [completing, setCompleting] = useState(false);
  const [justCompleted, setJustCompleted] = useState(false);
  const [openExams, setOpenExams] = useState<OpenAssessment[] | null>(null);
  const [failed, setFailed] = useState(false);
  const lang = useContentLang();

  const lessons = [...module.lessons].sort((a, b) => a.position - b.position);
  const lessonIds = new Set(lessons.map((lesson) => lesson.id));
  const looseItems = module.practice_items.filter(
    (item) => item.lesson_id === null || !lessonIds.has(item.lesson_id),
  );
  const completed = state.completedModules.includes(module.id);

  // Records the answered item and opens the explanations of the lessons
  // that `revealTargets` names (README section 7, rule 3).
  const answered = useCallback(
    (item: ItemView, feedback: ItemFeedback): Lesson[] => {
      const targets = new Set(revealTargets(feedback, state.path, module));
      const revealed = module.lessons.filter((lesson) =>
        targets.has(lesson.id),
      );
      const blockIds = revealed.flatMap((lesson) =>
        lesson.blocks
          .filter((block) => block.kind === "explanation")
          .map((block) => block.id),
      );
      update((current) => {
        const answeredItems = current.answeredItems.includes(item.id)
          ? current.answeredItems
          : [...current.answeredItems, item.id];
        const openedExplanations = [
          ...current.openedExplanations,
          ...blockIds.filter((id) => !current.openedExplanations.includes(id)),
        ];
        if (
          answeredItems === current.answeredItems &&
          openedExplanations.length === current.openedExplanations.length
        )
          return current;
        return { ...current, answeredItems, openedExplanations };
      });
      if (revealed.length > 0)
        setRevealCounts((counts) => {
          const next = { ...counts };
          for (const lesson of revealed)
            next[lesson.id] = (next[lesson.id] ?? 0) + 1;
          return next;
        });
      return revealed;
    },
    [module, state.path, update],
  );

  const complete = async () => {
    setCompleting(true);
    setOpenExams(null);
    setFailed(false);
    try {
      await runtime.completeModule(module.id);
      update((current) =>
        current.completedModules.includes(module.id)
          ? current
          : {
              ...current,
              completedModules: [...current.completedModules, module.id],
            },
      );
      await refreshEvidence();
      setJustCompleted(true);
    } catch (error) {
      if (error instanceof AssessmentsOpenError)
        setOpenExams(error.assessments);
      else setFailed(true);
    } finally {
      setCompleting(false);
    }
  };

  const counts = statusCounts(module.objectives, program, state);
  const showSummary = completed && !completing;

  return (
    <div className="space-y-10">
      <PathSwitch />
      <ObjectivesPanel module={module} />
      {lessons.map((lesson) => (
        <LessonSection
          key={lesson.id}
          lesson={lesson}
          module={module}
          items={module.practice_items.filter(
            (item) => item.lesson_id === lesson.id,
          )}
          revealCount={revealCounts[lesson.id] ?? 0}
          onAnswered={answered}
        />
      ))}
      {looseItems.length > 0 && (
        <section aria-labelledby={`module-${module.id}-practice`}>
          <h2
            id={`module-${module.id}-practice`}
            className="text-xl font-semibold tracking-tight"
          >
            {t("station.morePractice")}
          </h2>
          <div className="mt-4 space-y-6">
            {looseItems.map((item) => (
              <PracticeItem
                key={item.id}
                item={item}
                moduleId={module.id}
                onAnswered={answered}
              />
            ))}
          </div>
        </section>
      )}
      {module.exams.map((exam) => (
        <ExamSection key={exam.id} exam={exam} module={module} />
      ))}
      <RulesRecap rules={module.rules} />

      <div className="space-y-4">
        {!showSummary && (
          <button
            type="button"
            onClick={() => void complete()}
            disabled={completing || completed}
            className={buttonClasses("primary")}
          >
            {completing ? t("station.completing") : t("station.complete")}
          </button>
        )}
        {openExams !== null && (
          <div role="alert" className="text-sm">
            <p className="font-medium">{t("station.examsOpen")}</p>
            <ul className="mt-1 list-disc pl-5">
              {openExams.map((exam) => (
                <li key={exam.id} lang={lang}>
                  {exam.title}
                </li>
              ))}
            </ul>
          </div>
        )}
        {failed && (
          <p role="alert" className="text-sm text-red-800 dark:text-red-300">
            {t("station.completeFailed")}
          </p>
        )}
        {showSummary && (
          <CompletionSummary
            module={module}
            program={program}
            state={state}
            focusOnMount={justCompleted}
          />
        )}
        <p role="status" className="sr-only">
          {justCompleted &&
            showSummary &&
            t("station.completedAnnouncement", {
              evidenced: t("completion.countEvidenced", {
                count: counts.evidenced,
              }),
              practised: t("completion.countPractised", {
                count: counts.practised,
              }),
              open: t("completion.countOpen", { count: counts.open }),
            })}
        </p>
      </div>
    </div>
  );
}

/**
 * A module station (task 0012 step 11): the path switch, the objectives of
 * the topic, one section per lesson with its blocks and practice items, the
 * exams, the rules recap, "Complete module" and, once the module is
 * complete, the summary of the objectives. It reads its data through the
 * player and the `Runtime` only, so the admin preview and the SCORM package
 * render it with their own runtimes.
 */
export function ModuleStation({ station }: { station: Station }) {
  const { t } = useTranslation();
  const { program } = useCurrentPlayer();
  const module = program.modules.find(
    (entry) => entry.id === station.module_id,
  );
  if (module === undefined) return <p>{t("station.moduleMissing")}</p>;
  return <ModuleContent key={module.id} module={module} />;
}
