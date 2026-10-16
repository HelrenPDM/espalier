import { useDeferredValue, useState } from "react";
import { useTranslation } from "react-i18next";
import {
  MEDIA_MAX_PAGE,
  NO_MEDIA_FILTERS,
  useMediaLibrary,
  type MediaAsset,
  type MediaKind,
} from "../../api/admin/media";
import {
  staleDraft,
  useAttachMedia,
  useRenameMedia,
  type DraftMediaEntry,
  type PackDraft,
} from "../../api/admin/workbench";
import { AlertRegion, Button, TextField } from "../../app/forms";
import { LoadingStatus } from "../../app/LoadingStatus";
import { ListboxField } from "../media/ListboxField";
import { DELIVERY_EXTENSION, defaultMediaPath } from "../media/mediaText";
import { UploadZone } from "../media/UploadZone";
import { useDraftErrorText, useMediaPathErrorText } from "./draftErrors";
import { isMediaPath } from "./paths";
import { WorkbenchDialog } from "./WorkbenchDialog";

/** The kinds that become media entries; captions are text files. */
const ENTRY_KINDS: readonly MediaKind[] = ["image", "svg", "video"];

const isEntryKind = (asset: MediaAsset) => ENTRY_KINDS.includes(asset.kind);

interface ChangeCallbacks {
  /** A 409 `stale_draft` with the stored `lock_version`. */
  onConflict: (lockVersion: number) => void;
}

/**
 * "Add media" (task 0018, step 19): an image, SVG or video asset of the
 * library, found by a part of its title, or a file uploaded here, at a
 * `media/` path with the delivery extension of the asset, sent with
 * `POST .../media`. The path starts as `media/<slug of the title>.<ext>`
 * and follows the chosen asset until the author changes it. An asset that
 * is still converted can be added; a failed one is not offered. The path
 * field shows `invalid_path` and `path_taken`.
 */
export function AddMediaDialog({
  open,
  draft,
  onClose,
  onAdded,
  onConflict,
}: ChangeCallbacks & {
  open: boolean;
  draft: PackDraft;
  onClose: () => void;
  onAdded: (draft: PackDraft, path: string) => void;
}) {
  const { t } = useTranslation();
  const attach = useAttachMedia();
  const errorText = useDraftErrorText(draft.limits);
  const pathErrorText = useMediaPathErrorText();
  const [q, setQ] = useState("");
  const search = useDeferredValue(q.trim());
  const library = useMediaLibrary(
    { ...NO_MEDIA_FILTERS, q: search },
    { limit: MEDIA_MAX_PAGE, enabled: open },
  );
  const [selected, setSelected] = useState<MediaAsset | null>(null);
  const [path, setPath] = useState("");
  const [pathEdited, setPathEdited] = useState(false);
  const [assetError, setAssetError] = useState<string | null>(null);
  const [pathError, setPathError] = useState<string | null>(null);

  const candidates = (
    library.data?.pages.flatMap((page) => page.items) ?? []
  ).filter((asset) => isEntryKind(asset) && asset.status !== "failed");
  const options =
    selected !== null && !candidates.some((asset) => asset.id === selected.id)
      ? [selected, ...candidates]
      : candidates;

  const choose = (asset: MediaAsset) => {
    setSelected(asset);
    setAssetError(null);
    attach.reset();
    if (!pathEdited) {
      setPath(defaultMediaPath(asset.title, asset.kind));
      setPathError(null);
    }
  };

  const close = () => {
    if (attach.isPending) return;
    onClose();
  };

  const submit = () => {
    if (attach.isPending) return;
    const next = path.trim();
    if (selected === null) {
      setAssetError(t("admin.workbench.media.add.assetRequired"));
      return;
    }
    const ext = DELIVERY_EXTENSION[selected.kind];
    if (!isMediaPath(next, ext)) {
      setPathError(t("admin.workbench.media.errors.invalidPath", { ext }));
      return;
    }
    attach.mutate(
      {
        draftId: draft.id,
        media_asset_id: selected.id,
        path: next,
        lock_version: draft.lock_version,
      },
      {
        onSuccess: (changed) => {
          onClose();
          onAdded(changed, next);
        },
        onError: (error) => {
          const stored = staleDraft(error);
          if (stored !== null) {
            onClose();
            onConflict(stored);
            return;
          }
          setPathError(pathErrorText(error, ext));
        },
      },
    );
  };

  const otherError =
    attach.error !== null &&
    staleDraft(attach.error) === null &&
    pathErrorText(attach.error, "") === null
      ? errorText(attach.error)
      : null;

  let picker;
  if (library.isPending)
    picker = <LoadingStatus text={t("admin.workbench.media.add.loading")} />;
  else if (library.isError && options.length === 0)
    picker = <p role="alert">{t("admin.workbench.media.add.loadFailed")}</p>;
  else if (options.length === 0)
    picker = (
      <p>
        {search === ""
          ? t("admin.workbench.media.add.emptyLibrary")
          : t("admin.workbench.media.add.noMatch")}
      </p>
    );
  else
    picker = (
      <ListboxField
        label={t("admin.workbench.media.add.asset")}
        placeholder={t("admin.workbench.media.add.choose")}
        value={selected?.id ?? null}
        error={assetError}
        choices={options.map((asset) => ({
          value: asset.id,
          label: asset.title,
          detail: `${t(`admin.media.kinds.${asset.kind}`)}, ${t(
            `admin.media.status.${asset.status}`,
          )}`,
        }))}
        onChange={(id) => {
          const asset = options.find((entry) => entry.id === id);
          if (asset !== undefined) choose(asset);
        }}
      />
    );

  return (
    <WorkbenchDialog
      open={open}
      title={t("admin.workbench.media.add.title")}
      onClose={close}
      onSubmit={submit}
      actions={
        <>
          <Button variant="secondary" onClick={close}>
            {t("auth.forms.cancel")}
          </Button>
          <Button type="submit" disabled={attach.isPending}>
            {t("admin.workbench.media.add.submit")}
          </Button>
        </>
      }
    >
      <p>{t("admin.workbench.media.add.intro")}</p>
      <TextField
        label={t("admin.workbench.media.add.search")}
        type="search"
        value={q}
        autoComplete="off"
        maxLength={255}
        onChange={(event) => setQ(event.target.value)}
        onKeyDown={(event) => {
          // Enter in the search field filters; it does not add the asset.
          if (event.key === "Enter") event.preventDefault();
        }}
      />
      {picker}
      {assetError !== null && options.length === 0 && (
        <p className="text-sm text-red-700 dark:text-red-300">{assetError}</p>
      )}
      <div className="space-y-2">
        <p className="font-medium text-gray-900 dark:text-gray-100">
          {t("admin.workbench.media.add.uploadTitle")}
        </p>
        <UploadZone
          kinds={ENTRY_KINDS}
          multiple={false}
          onUploaded={({ asset }) => {
            if (isEntryKind(asset)) choose(asset);
          }}
        />
      </div>
      <TextField
        label={t("admin.workbench.media.add.path")}
        hint={t("admin.workbench.media.add.pathHint", {
          ext:
            selected === null
              ? "webp, svg, webm"
              : DELIVERY_EXTENSION[selected.kind],
        })}
        value={path}
        autoComplete="off"
        spellCheck={false}
        autoCapitalize="off"
        errors={pathError === null ? [] : [pathError]}
        onChange={(event) => {
          setPath(event.target.value);
          setPathEdited(true);
          setPathError(null);
          attach.reset();
        }}
      />
      <AlertRegion>{otherError}</AlertRegion>
    </WorkbenchDialog>
  );
}

/**
 * "Rename" of a media entry: a new `media/` path with the delivery
 * extension of its asset, sent with `PATCH .../media/:media_id`.
 */
export function RenameMediaDialog({
  entry,
  draft,
  onClose,
  onRenamed,
  onConflict,
}: ChangeCallbacks & {
  entry: DraftMediaEntry | null;
  draft: PackDraft;
  onClose: () => void;
  onRenamed: (from: string, to: string) => void;
}) {
  const { t } = useTranslation();
  const rename = useRenameMedia(draft.id);
  const errorText = useDraftErrorText(draft.limits);
  const pathErrorText = useMediaPathErrorText();
  const [path, setPath] = useState(entry?.path ?? "");
  const [pathError, setPathError] = useState<string | null>(null);
  const ext = entry === null ? "" : DELIVERY_EXTENSION[entry.asset.kind];

  const close = () => {
    if (rename.isPending) return;
    onClose();
  };

  const submit = () => {
    if (rename.isPending || entry === null) return;
    const next = path.trim();
    if (next === entry.path) {
      onClose();
      return;
    }
    if (!isMediaPath(next, DELIVERY_EXTENSION[entry.asset.kind])) {
      setPathError(t("admin.workbench.media.errors.invalidPath", { ext }));
      return;
    }
    rename.mutate(
      { entry, path: next, lock_version: draft.lock_version },
      {
        onSuccess: () => {
          onClose();
          onRenamed(entry.path, next);
        },
        onError: (error) => {
          const stored = staleDraft(error);
          if (stored !== null) {
            onClose();
            onConflict(stored);
            return;
          }
          setPathError(pathErrorText(error, ext));
        },
      },
    );
  };

  const otherError =
    rename.error !== null &&
    staleDraft(rename.error) === null &&
    pathErrorText(rename.error, ext) === null
      ? errorText(rename.error)
      : null;

  return (
    <WorkbenchDialog
      open={entry !== null}
      title={t("admin.workbench.draft.rename.title", { path: entry?.path })}
      onClose={close}
      onSubmit={submit}
      actions={
        <>
          <Button variant="secondary" onClick={close}>
            {t("auth.forms.cancel")}
          </Button>
          <Button type="submit" disabled={rename.isPending}>
            {t("admin.workbench.draft.rename.submit")}
          </Button>
        </>
      }
    >
      <TextField
        label={t("admin.workbench.draft.rename.path")}
        hint={t("admin.workbench.media.rename.hint", { ext })}
        value={path}
        autoComplete="off"
        spellCheck={false}
        autoCapitalize="off"
        errors={pathError === null ? [] : [pathError]}
        onChange={(event) => {
          setPath(event.target.value);
          setPathError(null);
          rename.reset();
        }}
      />
      <AlertRegion>{otherError}</AlertRegion>
    </WorkbenchDialog>
  );
}
