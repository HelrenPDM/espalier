import { Dialog, DialogPanel, DialogTitle } from "@headlessui/react";
import { useId, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import { Link } from "react-router";
import { isApiError } from "../../api/admin/fieldErrors";
import {
  assetInUse,
  useDeleteMedia,
  useMediaAsset,
  useUpdateMediaTitle,
  type MediaAsset,
} from "../../api/admin/media";
import {
  staleDraft,
  useAttachMedia,
  useDrafts,
  type PackDraft,
} from "../../api/admin/workbench";
import { ConfirmDialog } from "../../app/ConfirmDialog";
import { AlertRegion, Button, StatusRegion, TextField } from "../../app/forms";
import { linkClasses } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { useAdminErrorText } from "../adminErrors";
import {
  useDraftErrorText,
  useMediaPathErrorText,
} from "../workbench/draftErrors";
import { isMediaPath } from "../workbench/paths";
import { ListboxField } from "./ListboxField";
import {
  CopyText,
  MediaFacts,
  MediaState,
  MediaView,
  UsesList,
} from "./MediaParts";
import {
  DELIVERY_EXTENSION,
  defaultMediaPath,
  mediaDirective,
} from "./mediaText";

const MUTED = "text-gray-700 dark:text-gray-300";
const SECTION_HEADING =
  "text-base font-semibold text-gray-900 dark:text-gray-100";

/** The largest number of characters of a title (`Asset.changeset/2`). */
const MAX_TITLE = 255;

/** "Title": a new title for the asset, sent with `PATCH`. */
function TitleForm({ asset }: { asset: MediaAsset }) {
  const { t } = useTranslation();
  const update = useUpdateMediaTitle();
  const errorText = useAdminErrorText();
  const [title, setTitle] = useState(asset.title);
  const [fieldError, setFieldError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    if (update.isPending) return;
    const next = title.trim();
    setSaved(false);
    if (next.length === 0 || [...next].length > MAX_TITLE) {
      setFieldError(t("admin.media.detail.titleInvalid"));
      return;
    }
    setFieldError(null);
    update.mutate(
      { id: asset.id, title: next },
      {
        onSuccess: (changed) => {
          setTitle(changed.title);
          setSaved(true);
        },
        onError: (error) => {
          if (isApiError(error, 422))
            setFieldError(t("admin.media.detail.titleInvalid"));
        },
      },
    );
  };

  return (
    <form noValidate onSubmit={submit} className="space-y-2">
      <TextField
        label={t("admin.media.detail.title")}
        value={title}
        autoComplete="off"
        maxLength={MAX_TITLE}
        errors={fieldError === null ? [] : [fieldError]}
        onChange={(event) => {
          setTitle(event.target.value);
          setFieldError(null);
          setSaved(false);
        }}
      />
      <Button type="submit" variant="secondary" disabled={update.isPending}>
        {t("admin.media.detail.saveTitle")}
      </Button>
      <StatusRegion>
        {saved ? t("admin.media.detail.titleSaved") : null}
      </StatusRegion>
      <AlertRegion>
        {update.error !== null && !isApiError(update.error, 422)
          ? errorText(update.error)
          : null}
      </AlertRegion>
    </form>
  );
}

/** The draft and the path of a finished "Add to draft". */
interface Added {
  draft: PackDraft;
  path: string;
}

/**
 * "Add to draft" (step 19): a draft of the workbench and a path. An image,
 * SVG or video asset becomes a media entry of the draft; for a captions
 * asset the server copies its content into a text file of the draft
 * (step 16), so no file of the browser is involved. The request sends the
 * `lock_version` of the draft list; the dialog changes nothing that the
 * draft holds, so after a 409 `stale_draft` it repeats once with the
 * stored `lock_version` of the answer, and the path rules of the server
 * keep a taken path.
 */
function AddToDraft({ asset }: { asset: MediaAsset }) {
  const { t } = useTranslation();
  const headingId = useId();
  const drafts = useDrafts();
  const attach = useAttachMedia();
  const pathErrorText = useMediaPathErrorText();
  const ext = DELIVERY_EXTENSION[asset.kind];
  const [draftId, setDraftId] = useState<string | null>(null);
  const [path, setPath] = useState(() =>
    defaultMediaPath(asset.title, asset.kind),
  );
  const [draftError, setDraftError] = useState<string | null>(null);
  const [pathError, setPathError] = useState<string | null>(null);
  const [failure, setFailure] = useState<unknown>(null);
  const [added, setAdded] = useState<Added | null>(null);
  const draft = drafts.data?.find((entry) => entry.id === draftId) ?? null;
  const errorText = useDraftErrorText(
    draft?.limits ?? { files: 0, file_bytes: 0, draft_bytes: 0 },
  );

  // Captions are copied from the stored delivery file, so they wait for
  // `ready`; an image, SVG or video entry follows the conversion.
  const usable =
    asset.kind === "captions"
      ? asset.status === "ready"
      : asset.status !== "failed";

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (attach.isPending) return;
    setAdded(null);
    setFailure(null);
    const next = path.trim();
    const noDraft = draft === null;
    const badPath = !isMediaPath(next, ext);
    setDraftError(noDraft ? t("admin.media.addToDraft.draftRequired") : null);
    setPathError(
      badPath ? t("admin.workbench.media.errors.invalidPath", { ext }) : null,
    );
    if (noDraft || badPath) return;
    let lockVersion = draft.lock_version;
    for (let attempt = 0; attempt < 2; attempt += 1) {
      try {
        const changed = await attach.mutateAsync({
          draftId: draft.id,
          media_asset_id: asset.id,
          path: next,
          lock_version: lockVersion,
        });
        setAdded({ draft: changed, path: next });
        void drafts.refetch();
        return;
      } catch (error) {
        const stored = staleDraft(error);
        if (stored !== null && attempt === 0) {
          lockVersion = stored;
          continue;
        }
        const forPath = pathErrorText(error, ext);
        if (forPath !== null) setPathError(forPath);
        else setFailure(error);
        return;
      }
    }
  };

  let body;
  if (!usable)
    body = (
      <p className={MUTED}>
        {asset.kind === "captions"
          ? t("admin.media.addToDraft.captionsNotReady")
          : t("admin.media.addToDraft.failed")}
      </p>
    );
  else if (drafts.isPending)
    body = <LoadingStatus text={t("admin.media.addToDraft.loading")} />;
  else if (drafts.isError)
    body = (
      <p role="alert" className={MUTED}>
        {t("admin.media.addToDraft.loadFailed")}
      </p>
    );
  else if (drafts.data.length === 0)
    body = (
      <p className={MUTED}>
        {t("admin.media.addToDraft.noDrafts")}{" "}
        <Link to="/admin/workbench" className={linkClasses}>
          {t("admin.media.addToDraft.toWorkbench")}
        </Link>
      </p>
    );
  else
    body = (
      <form
        noValidate
        onSubmit={(event) => void submit(event)}
        className="space-y-3"
      >
        <p className={MUTED}>
          {asset.kind === "captions"
            ? t("admin.media.addToDraft.captionsIntro")
            : t("admin.media.addToDraft.intro")}
        </p>
        <ListboxField
          label={t("admin.media.addToDraft.draft")}
          placeholder={t("admin.media.addToDraft.choose")}
          choices={drafts.data.map((entry) => ({
            value: entry.id,
            label: entry.title,
          }))}
          value={draftId}
          error={draftError}
          onChange={(id) => {
            setDraftId(id);
            setDraftError(null);
            setFailure(null);
          }}
        />
        <TextField
          label={t("admin.media.addToDraft.path")}
          hint={t("admin.media.addToDraft.pathHint", { ext })}
          value={path}
          autoComplete="off"
          spellCheck={false}
          autoCapitalize="off"
          errors={pathError === null ? [] : [pathError]}
          onChange={(event) => {
            setPath(event.target.value);
            setPathError(null);
            setFailure(null);
          }}
        />
        <Button type="submit" disabled={attach.isPending}>
          {t("admin.media.addToDraft.submit")}
        </Button>
        <AlertRegion>
          {failure === null ? null : errorText(failure)}
        </AlertRegion>
        <StatusRegion>
          {added !== null && (
            <span>
              {t("admin.media.addToDraft.added", { path: added.path })}{" "}
              <Link
                to={`/admin/workbench/${encodeURIComponent(added.draft.id)}`}
                className={linkClasses}
              >
                {t("admin.media.addToDraft.openDraft", {
                  title: added.draft.title,
                })}
              </Link>
            </span>
          )}
        </StatusRegion>
      </form>
    );

  return (
    <section aria-labelledby={headingId} className="space-y-3">
      <h3 id={headingId} className={SECTION_HEADING}>
        {t("admin.media.addToDraft.title")}
      </h3>
      {body}
    </section>
  );
}

/** The content of the dialog for one asset, read again with its uses. */
function DetailBody({
  initial,
  onClose,
  onDeleted,
}: {
  initial: MediaAsset;
  onClose: () => void;
  onDeleted: (asset: MediaAsset) => void;
}) {
  const { t } = useTranslation();
  const usesHeadingId = useId();
  const directiveHeadingId = useId();
  const query = useMediaAsset(initial.id);
  const remove = useDeleteMedia();
  const errorText = useAdminErrorText();
  const [confirming, setConfirming] = useState(false);
  const asset = query.data ?? initial;
  const directive = mediaDirective(
    asset.kind,
    defaultMediaPath(asset.title, asset.kind),
  );
  const inUse = assetInUse(remove.error);

  const confirmDelete = () => {
    if (remove.isPending) return;
    remove.mutate(asset.id, {
      onSuccess: () => {
        setConfirming(false);
        onDeleted(asset);
      },
    });
  };

  let uses;
  if (query.data?.uses !== undefined)
    uses = <UsesList uses={query.data.uses} />;
  else if (query.isError)
    uses = (
      <p role="alert" className={MUTED}>
        {t("admin.media.uses.loadFailed")}
      </p>
    );
  else uses = <LoadingStatus text={t("admin.media.uses.loading")} />;

  return (
    <>
      <DialogTitle className="text-lg font-semibold break-words">
        {asset.title}
      </DialogTitle>
      <div className="mt-4 space-y-6 text-sm text-gray-700 dark:text-gray-300">
        <MediaView asset={asset} title={asset.title} />
        <div className="space-y-2">
          <p>
            <span className="font-medium text-gray-900 dark:text-gray-100">
              {t("admin.media.facts.state")}
            </span>{" "}
            <MediaState asset={asset} subject={asset.title} />
          </p>
          <MediaFacts asset={asset} />
        </div>
        <TitleForm key={asset.id} asset={asset} />
        <section aria-labelledby={usesHeadingId} className="space-y-2">
          <h3 id={usesHeadingId} className={SECTION_HEADING}>
            {t("admin.media.uses.title")}
          </h3>
          {uses}
        </section>
        {directive !== null && (
          <section aria-labelledby={directiveHeadingId} className="space-y-2">
            <h3 id={directiveHeadingId} className={SECTION_HEADING}>
              {t("admin.media.directive.title")}
            </h3>
            <p className={MUTED}>{t("admin.media.directive.hint")}</p>
            <CopyText
              label={t("admin.media.directive.label")}
              text={directive}
              buttonLabel={t("admin.media.directive.copy")}
            />
          </section>
        )}
        <AddToDraft asset={asset} />
      </div>
      <div className="mt-6 flex flex-wrap justify-end gap-3">
        <Button
          variant="danger"
          onClick={() => {
            remove.reset();
            setConfirming(true);
          }}
        >
          {t("admin.media.delete.button")}
        </Button>
        <Button variant="secondary" onClick={onClose} data-autofocus>
          {t("admin.media.detail.close")}
        </Button>
      </div>
      <ConfirmDialog
        open={confirming}
        title={t("admin.media.delete.title", { title: asset.title })}
        confirmLabel={t("admin.media.delete.confirm")}
        confirmVariant="danger"
        onConfirm={confirmDelete}
        onClose={() => {
          if (!remove.isPending) setConfirming(false);
        }}
      >
        <p>{t("admin.media.delete.body")}</p>
        <AlertRegion>
          {inUse !== null ? (
            <div className="space-y-2">
              <p>{t("admin.media.delete.inUse")}</p>
              <UsesList uses={inUse} />
            </div>
          ) : remove.error !== null ? (
            errorText(remove.error)
          ) : null}
        </AlertRegion>
      </ConfirmDialog>
    </>
  );
}

/**
 * The detail dialog of an asset of the media library (task 0018, step
 * 19): the preview (`<img>` or `<video controls>`), the state and the
 * facts, the title, the uses with links, "Copy directive", "Add to draft",
 * and the deletion with `ConfirmDialog`, which shows the uses of a 409
 * `asset_in_use`. It reads the asset with its uses when it opens, and
 * again every two seconds while the asset is converted. Titles, paths and
 * codes render as text (ASVS 3.2.2).
 */
export function MediaDetailDialog({
  asset,
  onClose,
  onDeleted,
}: {
  /** The asset of the card that opened the dialog; `null` closes it. */
  asset: MediaAsset | null;
  onClose: () => void;
  onDeleted: (asset: MediaAsset) => void;
}) {
  return (
    <Dialog open={asset !== null} onClose={onClose} className="relative z-40">
      <div className="fixed inset-0 bg-gray-900/40" aria-hidden="true" />
      <div className="fixed inset-0 flex items-center justify-center p-4">
        <DialogPanel className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-lg bg-white p-6 text-gray-900 shadow-xl dark:bg-gray-900 dark:text-gray-100">
          {asset !== null && (
            <DetailBody
              key={asset.id}
              initial={asset}
              onClose={onClose}
              onDeleted={onDeleted}
            />
          )}
        </DialogPanel>
      </div>
    </Dialog>
  );
}
