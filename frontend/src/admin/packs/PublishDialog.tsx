import { Dialog, DialogPanel, DialogTitle } from "@headlessui/react";
import { useTranslation } from "react-i18next";
import {
  alignmentErrorFindings,
  usePackDiff,
  usePublishPack,
  type PackDiff,
  type PackImport,
} from "../../api/admin/packs";
import { ApiError } from "../../api/errors";
import { AlertRegion, Button } from "../../app/forms";
import { LoadingStatus } from "../../app/LoadingStatus";
import { CheckFindingList } from "./findings";

/** The keyed kinds of the diff, in the order of the publisher (0008 step 10). */
const KINDS = [
  "modules",
  "lessons",
  "learning_objectives",
  "items",
  "rules",
  "assessments",
  "qualifications",
  "formats",
  "sources",
  "segments",
  "glossary_terms",
] as const satisfies readonly (keyof PackDiff)[];

const CHANGES = ["added", "changed", "archived"] as const;

const Keys = ({ keys }: { keys: readonly string[] }) => (
  <span className="font-mono text-xs break-words">{keys.join(", ")}</span>
);

/**
 * The added, changed and archived keys per kind. A changed learning
 * objective also names the fields of `changed_fields` that differ.
 */
function DiffSummary({ diff }: { diff: PackDiff }) {
  const { t } = useTranslation();
  const kinds = KINDS.filter((kind) =>
    CHANGES.some((change) => diff[kind][change].length > 0),
  );
  if (kinds.length === 0) return <p>{t("admin.pack.publish.noChanges")}</p>;

  const changedFields = diff.learning_objectives.changed_fields;
  return (
    <div className="space-y-3">
      <p>{t("admin.pack.publish.intro")}</p>
      {kinds.map((kind) => (
        <section key={kind} className="space-y-1">
          <h3 className="font-semibold text-gray-900 dark:text-gray-100">
            {t(`admin.pack.publish.kinds.${kind}`)}
          </h3>
          <dl className="space-y-1">
            {CHANGES.filter((change) => diff[kind][change].length > 0).map(
              (change) => (
                <div key={change}>
                  <dt className="font-medium">
                    {t(`admin.pack.publish.${change}`, {
                      count: diff[kind][change].length,
                    })}
                  </dt>
                  <dd>
                    {kind === "learning_objectives" && change === "changed" ? (
                      <ul className="list-disc pl-5">
                        {diff[kind].changed.map((key) => (
                          <li key={key}>
                            <Keys keys={[key]} />
                            {Object.hasOwn(changedFields, key) && (
                              <>
                                {" ("}
                                {t("admin.pack.publish.fields", {
                                  fields: changedFields[key].join(", "),
                                })}
                                {")"}
                              </>
                            )}
                          </li>
                        ))}
                      </ul>
                    ) : (
                      <Keys keys={diff[kind][change]} />
                    )}
                  </dd>
                </div>
              ),
            )}
          </dl>
        </section>
      ))}
    </div>
  );
}

/**
 * The confirmation of a publication (task 0015, step 11): the changes of
 * `GET /api/admin/packs/:id/diff` per kind with the changed fields of each
 * changed learning objective, and the number of alignment warnings. A 409
 * `alignment_errors` answer shows its findings here, and the import stays
 * unpublished. "Publish" waits for the diff, so the author sees every
 * change before the publication.
 */
export function PublishDialog({
  pack,
  open,
  onClose,
  onPublished,
}: {
  pack: PackImport;
  open: boolean;
  onClose: () => void;
  onPublished: () => void;
}) {
  const { t } = useTranslation();
  const diff = usePackDiff(pack.id, { enabled: open });
  const publish = usePublishPack(pack.id);

  const close = () => {
    if (publish.isPending) return;
    publish.reset();
    onClose();
  };

  const confirm = () => {
    if (publish.isPending) return;
    publish.mutate(undefined, {
      onSuccess: () => {
        publish.reset();
        onPublished();
      },
    });
  };

  const error = publish.error;
  const findings =
    error instanceof ApiError && error.status === 409
      ? alignmentErrorFindings(error.body)
      : null;
  let failure = null;
  if (findings !== null)
    failure = (
      <div className="space-y-2">
        <p>{t("admin.pack.publish.refused")}</p>
        <CheckFindingList findings={findings} />
      </div>
    );
  else if (error instanceof ApiError && error.status === 409)
    failure = <p>{t("admin.pack.publish.notPublishable")}</p>;
  else if (error !== null) failure = <p>{t("admin.pack.publish.failed")}</p>;
  const refused = error instanceof ApiError && error.status === 409;

  return (
    <Dialog open={open} onClose={close} className="relative z-50">
      <div className="fixed inset-0 bg-gray-900/40" aria-hidden="true" />
      <div className="fixed inset-0 flex items-center justify-center p-4">
        <DialogPanel className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-lg bg-white p-6 text-gray-900 shadow-xl dark:bg-gray-900 dark:text-gray-100">
          <DialogTitle className="text-lg font-semibold">
            {t("admin.pack.publish.dialogTitle", { key: pack.pack_key ?? "" })}
          </DialogTitle>
          <div className="mt-3 space-y-4 text-sm text-gray-700 dark:text-gray-300">
            {diff.isPending ? (
              <LoadingStatus text={t("admin.pack.publish.diffLoading")} />
            ) : diff.isError ? (
              <p role="alert">{t("admin.pack.publish.diffFailed")}</p>
            ) : (
              <DiffSummary diff={diff.data} />
            )}
            <p>
              {t("admin.pack.publish.warnings", {
                count: pack.alignment.warnings.length,
              })}
            </p>
            <AlertRegion>{failure}</AlertRegion>
            {publish.isPending && (
              <LoadingStatus text={t("admin.pack.publish.publishing")} />
            )}
          </div>
          <div className="mt-6 flex flex-wrap justify-end gap-3">
            <Button variant="secondary" onClick={close} data-autofocus>
              {t("auth.forms.cancel")}
            </Button>
            {!refused && (
              <Button
                onClick={confirm}
                disabled={!diff.isSuccess || publish.isPending}
              >
                {t("admin.pack.publish.confirm")}
              </Button>
            )}
          </div>
        </DialogPanel>
      </div>
    </Dialog>
  );
}
