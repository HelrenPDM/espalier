import { Menu, MenuButton, MenuItem, MenuItems } from "@headlessui/react";
import { ChevronDownIcon } from "@heroicons/react/20/solid";
import { useId, useRef, useState, type ReactNode } from "react";
import { useTranslation } from "react-i18next";
import {
  staleDraft,
  useCreateFile,
  useDeleteDraftMedia,
  useDeleteFile,
  useRenameFile,
  type DraftFileEntry,
  type DraftMediaEntry,
  type PackDraft,
} from "../../api/admin/workbench";
import { ConfirmDialog } from "../../app/ConfirmDialog";
import { AlertRegion, Button, TextField } from "../../app/forms";
import { FOCUS_RING } from "../../app/formStyles";
import { MediaKindIcon } from "../media/MediaParts";
import { useDraftErrorText, usePathErrorText } from "./draftErrors";
import { AddMediaDialog, RenameMediaDialog } from "./MediaDialogs";
import {
  CAPTIONS_TEMPLATE,
  captionsPath,
  isLayoutPath,
  lessonCount,
  lessonPath,
  lessonTemplate,
  moduleDirs,
  moduleFilePath,
  MODULE_FILES,
  TOP_FILES,
} from "./paths";
import { WorkbenchDialog } from "./WorkbenchDialog";

const LABEL = "block text-sm font-medium text-gray-900 dark:text-gray-100";
const SELECT = `mt-1 block w-full rounded-md border border-gray-500 bg-white px-3 py-2 text-sm text-gray-900 dark:bg-gray-900 dark:text-gray-100 ${FOCUS_RING}`;
const FILE_BUTTON = `min-w-0 flex-1 rounded-md px-2 py-1 text-left font-mono text-xs break-all text-gray-900 hover:bg-gray-100 aria-[current=true]:bg-accent-50 aria-[current=true]:font-semibold aria-[current=true]:text-accent-700 dark:text-gray-100 dark:hover:bg-gray-800 dark:aria-[current=true]:bg-accent-700 dark:aria-[current=true]:text-white ${FOCUS_RING}`;
const MENU_BUTTON = `flex shrink-0 items-center gap-0.5 rounded-md px-1.5 py-1 text-xs font-medium text-gray-700 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-800 ${FOCUS_RING}`;
const MENU_ITEM =
  "block w-full px-4 py-2 text-left text-sm text-gray-900 data-focus:bg-accent-50 dark:text-gray-100 dark:data-focus:bg-accent-700";

/** A directory of the tree with its directories and files. */
interface DirNode {
  kind: "dir";
  name: string;
  path: string;
  children: TreeNode[];
}

interface FileNode {
  kind: "file";
  name: string;
  /** The directory of the file, `""` at the root. */
  dir: string;
  file: DraftFileEntry;
}

/** A media entry of the draft (task 0018): a library asset at a path. */
interface MediaNode {
  kind: "media";
  name: string;
  dir: string;
  entry: DraftMediaEntry;
}

type TreeNode = DirNode | FileNode | MediaNode;

/** A file or a media entry, each with its path. */
type Leaf =
  | { kind: "file"; path: string; file: DraftFileEntry }
  | { kind: "media"; path: string; entry: DraftMediaEntry };

const byPath = (a: Leaf, b: Leaf) =>
  a.path < b.path ? -1 : a.path > b.path ? 1 : 0;

/**
 * The files and the media entries as nested directories, in the order of
 * their paths: each directory appears where its first entry would, so the
 * tree reads in path order at every level. The captions of `media/` are
 * files; the images, SVG files and videos there are media entries.
 */
function buildTree(
  files: readonly DraftFileEntry[],
  media: readonly DraftMediaEntry[],
): TreeNode[] {
  const leaves: Leaf[] = [
    ...files.map((file): Leaf => ({ kind: "file", path: file.path, file })),
    ...media.map((entry): Leaf => ({ kind: "media", path: entry.path, entry })),
  ];
  const root: DirNode = { kind: "dir", name: "", path: "", children: [] };
  for (const leaf of leaves.sort(byPath)) {
    const parts = leaf.path.split("/");
    let dir = root;
    for (const [index, part] of parts.slice(0, -1).entries()) {
      const found = dir.children.find(
        (node): node is DirNode => node.kind === "dir" && node.name === part,
      );
      const next = found ?? {
        kind: "dir" as const,
        name: part,
        path: parts.slice(0, index + 1).join("/"),
        children: [],
      };
      if (found === undefined) dir.children.push(next);
      dir = next;
    }
    const name = parts[parts.length - 1];
    dir.children.push(
      leaf.kind === "file"
        ? { kind: "file", name, dir: dir.path, file: leaf.file }
        : { kind: "media", name, dir: dir.path, entry: leaf.entry },
    );
  }
  return root.children;
}

/** A select with a visible label. */
function SelectField({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: string;
  options: readonly string[];
  onChange: (value: string) => void;
}) {
  const id = useId();
  return (
    <div>
      <label htmlFor={id} className={LABEL}>
        {label}
      </label>
      <select
        id={id}
        value={value}
        onChange={(event) => onChange(event.target.value)}
        className={SELECT}
      >
        {options.map((option) => (
          <option key={option} value={option}>
            {option}
          </option>
        ))}
      </select>
    </div>
  );
}

/** A radio button with its label to the right. */
function RadioField({
  name,
  label,
  checked,
  onChange,
}: {
  name: string;
  label: string;
  checked: boolean;
  onChange: () => void;
}) {
  const id = useId();
  return (
    <div className="flex items-center gap-2">
      <input
        id={id}
        type="radio"
        name={name}
        checked={checked}
        onChange={onChange}
        className={`size-4 border-gray-500 ${FOCUS_RING}`}
      />
      <label htmlFor={id} className="text-sm text-gray-900 dark:text-gray-100">
        {label}
      </label>
    </div>
  );
}

type FileKind = "root" | "module" | "lesson" | "captions";

const FILE_KINDS: readonly FileKind[] = [
  "root",
  "module",
  "lesson",
  "captions",
];

interface ChangeCallbacks {
  /** A 409 `stale_draft` with the stored `lock_version`. */
  onConflict: (lockVersion: number) => void;
}

/**
 * "Add file": builds a path of the pack layout from a choice (a file at
 * the root, a file of a module directory, a lesson with its key, or a
 * captions file `media/<key>.vtt` of task 0018) and sends
 * `POST .../files`. A new lesson starts with front matter (`title`,
 * `position`) and one `text` block, a new captions file with the header
 * `WEBVTT` and an empty line, and a new YAML file starts empty. The path
 * field shows `invalid_path` and `path_taken`.
 */
function AddFileDialog({
  open,
  draft,
  onClose,
  onCreated,
  onConflict,
}: ChangeCallbacks & {
  open: boolean;
  draft: PackDraft;
  onClose: () => void;
  onCreated: (draft: PackDraft, path: string) => void;
}) {
  const { t } = useTranslation();
  const listId = useId();
  const create = useCreateFile(draft.id);
  const pathErrorText = usePathErrorText();
  const errorText = useDraftErrorText(draft.limits);
  const paths = (draft.files ?? []).map((file) => file.path);
  const dirs = moduleDirs(paths);

  const [kind, setKind] = useState<FileKind>("root");
  const [rootName, setRootName] = useState<string>(
    TOP_FILES.find((name) => !paths.includes(name)) ?? TOP_FILES[0],
  );
  const [dir, setDir] = useState(dirs[0] ?? "");
  const [moduleName, setModuleName] = useState<string>(MODULE_FILES[0]);
  const [lessonKey, setLessonKey] = useState("");
  const [captionsKey, setCaptionsKey] = useState("");
  const [title, setTitle] = useState("");
  const [titleError, setTitleError] = useState<string | null>(null);
  const [pathError, setPathError] = useState<string | null>(null);

  const path =
    kind === "root"
      ? rootName
      : kind === "module"
        ? moduleFilePath(dir, moduleName)
        : kind === "lesson"
          ? lessonPath(dir, lessonKey)
          : captionsPath(captionsKey);

  /** Every change of a choice clears the errors of the last attempt. */
  const changed =
    <T,>(set: (value: T) => void) =>
    (value: T) => {
      set(value);
      setPathError(null);
      create.reset();
    };

  const close = () => {
    if (create.isPending) return;
    onClose();
  };

  const submit = () => {
    if (create.isPending) return;
    const missingTitle = kind === "lesson" && title.trim() === "";
    setTitleError(
      missingTitle ? t("admin.workbench.draft.add.titleRequired") : null,
    );
    const validPath = isLayoutPath(path);
    setPathError(
      validPath ? null : t("admin.workbench.draft.errors.invalidPath"),
    );
    if (missingTitle || !validPath) return;
    const content =
      kind === "lesson"
        ? lessonTemplate(title.trim(), lessonCount(paths, dir) + 1)
        : kind === "captions"
          ? CAPTIONS_TEMPLATE
          : "";
    create.mutate(
      { path, content, lock_version: draft.lock_version },
      {
        onSuccess: (next) => {
          onClose();
          onCreated(next, path);
        },
        onError: (error) => {
          const stored = staleDraft(error);
          if (stored !== null) {
            onClose();
            onConflict(stored);
            return;
          }
          setPathError(pathErrorText(error));
        },
      },
    );
  };

  const otherError =
    create.error !== null &&
    staleDraft(create.error) === null &&
    pathErrorText(create.error) === null
      ? errorText(create.error)
      : null;

  return (
    <WorkbenchDialog
      open={open}
      title={t("admin.workbench.draft.add.title")}
      onClose={close}
      onSubmit={submit}
      actions={
        <>
          <Button variant="secondary" onClick={close}>
            {t("auth.forms.cancel")}
          </Button>
          <Button type="submit" disabled={create.isPending}>
            {t("admin.workbench.draft.add.submit")}
          </Button>
        </>
      }
    >
      <fieldset className="space-y-2">
        <legend className={LABEL}>{t("admin.workbench.draft.add.kind")}</legend>
        {FILE_KINDS.map((value) => (
          <RadioField
            key={value}
            name="file-kind"
            label={t(`admin.workbench.draft.add.kinds.${value}`)}
            checked={kind === value}
            onChange={() => changed(setKind)(value)}
          />
        ))}
      </fieldset>
      {kind === "root" && (
        <SelectField
          label={t("admin.workbench.draft.add.fileName")}
          value={rootName}
          options={TOP_FILES}
          onChange={changed(setRootName)}
        />
      )}
      {(kind === "module" || kind === "lesson") && (
        <>
          <TextField
            label={t("admin.workbench.draft.add.moduleDir")}
            hint={t("admin.workbench.draft.add.moduleDirHint")}
            value={dir}
            list={listId}
            autoComplete="off"
            spellCheck={false}
            autoCapitalize="off"
            onChange={(event) => changed(setDir)(event.target.value)}
          />
          <datalist id={listId}>
            {dirs.map((name) => (
              <option key={name} value={name} />
            ))}
          </datalist>
        </>
      )}
      {kind === "module" && (
        <SelectField
          label={t("admin.workbench.draft.add.fileName")}
          value={moduleName}
          options={MODULE_FILES}
          onChange={changed(setModuleName)}
        />
      )}
      {kind === "lesson" && (
        <>
          <TextField
            label={t("admin.workbench.draft.add.lessonKey")}
            hint={t("admin.workbench.draft.add.lessonKeyHint")}
            value={lessonKey}
            autoComplete="off"
            spellCheck={false}
            autoCapitalize="off"
            onChange={(event) => changed(setLessonKey)(event.target.value)}
          />
          <TextField
            label={t("admin.workbench.draft.add.lessonTitle")}
            value={title}
            autoComplete="off"
            errors={titleError === null ? [] : [titleError]}
            onChange={(event) => {
              setTitle(event.target.value);
              setTitleError(null);
            }}
          />
        </>
      )}
      {kind === "captions" && (
        <TextField
          label={t("admin.workbench.draft.add.captionsKey")}
          hint={t("admin.workbench.draft.add.captionsKeyHint")}
          value={captionsKey}
          autoComplete="off"
          spellCheck={false}
          autoCapitalize="off"
          onChange={(event) => changed(setCaptionsKey)(event.target.value)}
        />
      )}
      <TextField
        label={t("admin.workbench.draft.add.path")}
        hint={t("admin.workbench.draft.add.pathHint")}
        value={path}
        readOnly
        className="mt-1 block w-full rounded-md border border-gray-300 bg-gray-50 px-3 py-2 font-mono text-sm break-all text-gray-900 aria-[invalid=true]:border-red-700 dark:border-gray-700 dark:bg-gray-800 dark:text-gray-100 dark:aria-[invalid=true]:border-red-400"
        errors={pathError === null ? [] : [pathError]}
      />
      <AlertRegion>{otherError}</AlertRegion>
    </WorkbenchDialog>
  );
}

/** "Rename": a new path for a file, sent with `PATCH .../files/:file_id`. */
function RenameDialog({
  file,
  draft,
  onClose,
  onRenamed,
  onConflict,
}: ChangeCallbacks & {
  file: DraftFileEntry | null;
  draft: PackDraft;
  onClose: () => void;
  onRenamed: (from: string, to: string) => void;
}) {
  const { t } = useTranslation();
  const rename = useRenameFile(draft.id);
  const pathErrorText = usePathErrorText();
  const errorText = useDraftErrorText(draft.limits);
  const [path, setPath] = useState(file?.path ?? "");
  const [pathError, setPathError] = useState<string | null>(null);

  const close = () => {
    if (rename.isPending) return;
    onClose();
  };

  const submit = () => {
    if (rename.isPending || file === null) return;
    const next = path.trim();
    if (next === file.path) {
      onClose();
      return;
    }
    if (!isLayoutPath(next)) {
      setPathError(t("admin.workbench.draft.errors.invalidPath"));
      return;
    }
    rename.mutate(
      { fileId: file.id, path: next, lock_version: draft.lock_version },
      {
        onSuccess: () => {
          onClose();
          onRenamed(file.path, next);
        },
        onError: (error) => {
          const stored = staleDraft(error);
          if (stored !== null) {
            onClose();
            onConflict(stored);
            return;
          }
          setPathError(pathErrorText(error));
        },
      },
    );
  };

  const otherError =
    rename.error !== null &&
    staleDraft(rename.error) === null &&
    pathErrorText(rename.error) === null
      ? errorText(rename.error)
      : null;

  return (
    <WorkbenchDialog
      open={file !== null}
      title={t("admin.workbench.draft.rename.title", { path: file?.path })}
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
        hint={t("admin.workbench.draft.rename.hint")}
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

/** "Rename" and "Delete" of one file or media entry in a Headless UI `Menu`. */
function FileMenu({
  path,
  onRename,
  onDelete,
}: {
  path: string;
  onRename: () => void;
  onDelete: () => void;
}) {
  const { t } = useTranslation();
  return (
    <Menu>
      <MenuButton className={MENU_BUTTON}>
        {t("admin.workbench.draft.tree.actions")}{" "}
        <span className="sr-only">
          {t("admin.workbench.draft.tree.actionsFor", { path })}
        </span>
        <ChevronDownIcon aria-hidden="true" className="size-4" />
      </MenuButton>
      <MenuItems
        anchor="bottom end"
        className="z-10 mt-1 w-40 rounded-md border border-gray-200 bg-white py-1 shadow-lg focus:outline-none dark:border-gray-700 dark:bg-gray-900"
      >
        <MenuItem>
          <button type="button" onClick={onRename} className={MENU_ITEM}>
            {t("admin.workbench.draft.tree.rename")}
          </button>
        </MenuItem>
        <MenuItem>
          <button type="button" onClick={onDelete} className={MENU_ITEM}>
            {t("admin.workbench.draft.tree.delete")}
          </button>
        </MenuItem>
      </MenuItems>
    </Menu>
  );
}

function TreeList({
  nodes,
  nested,
  renderFile,
  renderMedia,
}: {
  nodes: TreeNode[];
  nested: boolean;
  renderFile: (node: FileNode) => ReactNode;
  renderMedia: (node: MediaNode) => ReactNode;
}) {
  return (
    <ul
      className={
        nested
          ? "ml-2 space-y-0.5 border-l border-gray-200 pl-2 dark:border-gray-700"
          : "space-y-0.5"
      }
    >
      {nodes.map((node) =>
        node.kind === "dir" ? (
          <li key={`dir:${node.path}`}>
            <span className="block px-2 py-1 font-mono text-xs font-semibold break-all text-gray-700 dark:text-gray-300">
              {`${node.name}/`}
            </span>
            <TreeList
              nodes={node.children}
              nested
              renderFile={renderFile}
              renderMedia={renderMedia}
            />
          </li>
        ) : node.kind === "file" ? (
          <li key={node.file.id} className="flex items-start gap-1">
            {renderFile(node)}
          </li>
        ) : (
          <li key={`media:${node.entry.id}`} className="flex items-start gap-1">
            {renderMedia(node)}
          </li>
        ),
      )}
    </ul>
  );
}

type TreeDialog =
  | { kind: "add" }
  | { kind: "addMedia" }
  | { kind: "rename"; file: DraftFileEntry }
  | { kind: "delete"; file: DraftFileEntry }
  | { kind: "renameMedia"; entry: DraftMediaEntry }
  | { kind: "deleteMedia"; entry: DraftMediaEntry };

/**
 * The file tree of the draft page (task 0016a, step 13): a `nav` named
 * "Files of the draft" with nested lists of directories and files in the
 * order of their paths. Each file is a button; the open file carries
 * `aria-current="true"` and, with unsaved changes, the marker "unsaved".
 * The tree uses lists and buttons without the ARIA `tree` role, so Tab
 * and the arrow keys keep their plain behavior. "Add file" and the menu
 * of each file ("Rename", "Delete") open a dialog each; paths and names
 * render as text.
 *
 * The media entries of task 0018 sit below `media/` among the files, each
 * a button with the icon and the name of its kind; the captions there are
 * text files. "Add media" adds a library asset or a new upload, and the
 * menu of a media entry renames it or removes it from the draft through
 * the media routes.
 */
export function FileTree({
  draft,
  openFileId,
  openMediaId,
  unsaved,
  onOpen,
  onOpenMedia,
  onCreated,
  onRenamed,
  onDeleted,
  onMediaAdded,
  onMediaDeleted,
  onConflict,
}: ChangeCallbacks & {
  draft: PackDraft;
  openFileId: string | null;
  /** The media entry shown in place of the editor. */
  openMediaId: string | null;
  /** The open file has unsaved changes. */
  unsaved: boolean;
  onOpen: (fileId: string) => void;
  onOpenMedia: (mediaId: string) => void;
  onCreated: (draft: PackDraft, path: string) => void;
  /** A file or a media entry moved from `from` to `to`. */
  onRenamed: (from: string, to: string) => void;
  onDeleted: (file: DraftFileEntry) => void;
  onMediaAdded: (draft: PackDraft, path: string) => void;
  onMediaDeleted: (entry: DraftMediaEntry) => void;
}) {
  const { t } = useTranslation();
  const headingId = useId();
  const headingRef = useRef<HTMLHeadingElement>(null);
  const remove = useDeleteFile(draft.id);
  const removeMedia = useDeleteDraftMedia(draft.id);
  const errorText = useDraftErrorText(draft.limits);
  const [dialog, setDialog] = useState<TreeDialog | null>(null);
  // A new key for each dialog that opens, so it starts with fresh fields.
  const [dialogKey, setDialogKey] = useState(0);
  const files = draft.files ?? [];
  const media = draft.media ?? [];

  const openDialog = (next: TreeDialog) => {
    remove.reset();
    removeMedia.reset();
    setDialogKey((key) => key + 1);
    setDialog(next);
  };
  const closeDialog = () => setDialog(null);
  const deleting = dialog?.kind === "delete" ? dialog.file : null;
  const deletingMedia = dialog?.kind === "deleteMedia" ? dialog.entry : null;

  const confirmDeleteMedia = () => {
    if (removeMedia.isPending || deletingMedia === null) return;
    removeMedia.mutate(
      { entry: deletingMedia, lock_version: draft.lock_version },
      {
        onSuccess: () => {
          closeDialog();
          onMediaDeleted(deletingMedia);
          requestAnimationFrame(() => headingRef.current?.focus());
        },
        onError: (error) => {
          const stored = staleDraft(error);
          if (stored === null) return;
          closeDialog();
          onConflict(stored);
        },
      },
    );
  };

  const confirmDelete = () => {
    if (remove.isPending || deleting === null) return;
    remove.mutate(
      { fileId: deleting.id, lock_version: draft.lock_version },
      {
        onSuccess: () => {
          closeDialog();
          onDeleted(deleting);
          // The menu button that opened the dialog left with its file.
          requestAnimationFrame(() => headingRef.current?.focus());
        },
        onError: (error) => {
          const stored = staleDraft(error);
          if (stored === null) return;
          closeDialog();
          onConflict(stored);
        },
      },
    );
  };

  const renderFile = ({ name, dir, file }: FileNode) => {
    const current = file.id === openFileId;
    return (
      <>
        <button
          type="button"
          aria-current={current ? "true" : undefined}
          onClick={() => onOpen(file.id)}
          className={FILE_BUTTON}
        >
          {name}
          {dir !== "" && <span className="sr-only">{`, ${dir}/`}</span>}
          {current && unsaved && (
            <>
              <span className="sr-only">,</span>{" "}
              <span className="ml-1 rounded bg-amber-100 px-1 font-sans text-xs font-medium text-amber-900 dark:bg-amber-900 dark:text-amber-100">
                {t("admin.workbench.draft.tree.unsaved")}
              </span>
            </>
          )}
        </button>
        <FileMenu
          path={file.path}
          onRename={() => openDialog({ kind: "rename", file })}
          onDelete={() => openDialog({ kind: "delete", file })}
        />
      </>
    );
  };

  const renderMedia = ({ name, dir, entry }: MediaNode) => {
    const current = entry.id === openMediaId;
    return (
      <>
        <button
          type="button"
          aria-current={current ? "true" : undefined}
          onClick={() => onOpenMedia(entry.id)}
          className={`flex items-start gap-1.5 ${FILE_BUTTON}`}
        >
          <MediaKindIcon kind={entry.asset.kind} className="mt-px size-4" />
          <span className="min-w-0">
            {name}
            <span className="sr-only">
              {`, ${dir}/, ${t(`admin.media.kinds.${entry.asset.kind}`)}`}
            </span>
          </span>
        </button>
        <FileMenu
          path={entry.path}
          onRename={() => openDialog({ kind: "renameMedia", entry })}
          onDelete={() => openDialog({ kind: "deleteMedia", entry })}
        />
      </>
    );
  };

  return (
    <nav aria-labelledby={headingId} className="min-w-0 space-y-3">
      <h2
        id={headingId}
        ref={headingRef}
        tabIndex={-1}
        className="text-lg font-semibold tracking-tight focus:outline-none"
      >
        {t("admin.workbench.draft.tree.title")}
      </h2>
      <div className="flex flex-wrap gap-2">
        <Button variant="secondary" onClick={() => openDialog({ kind: "add" })}>
          {t("admin.workbench.draft.tree.add")}
        </Button>
        <Button
          variant="secondary"
          onClick={() => openDialog({ kind: "addMedia" })}
        >
          {t("admin.workbench.draft.tree.addMedia")}
        </Button>
      </div>
      {files.length === 0 && media.length === 0 ? (
        <p className="text-sm text-gray-700 dark:text-gray-300">
          {t("admin.workbench.draft.tree.empty")}
        </p>
      ) : (
        <TreeList
          nodes={buildTree(files, media)}
          nested={false}
          renderFile={renderFile}
          renderMedia={renderMedia}
        />
      )}
      <AddFileDialog
        key={`add-${dialogKey}`}
        open={dialog?.kind === "add"}
        draft={draft}
        onClose={closeDialog}
        onCreated={onCreated}
        onConflict={onConflict}
      />
      <AddMediaDialog
        key={`add-media-${dialogKey}`}
        open={dialog?.kind === "addMedia"}
        draft={draft}
        onClose={closeDialog}
        onAdded={onMediaAdded}
        onConflict={onConflict}
      />
      <RenameMediaDialog
        key={`rename-media-${dialogKey}`}
        entry={dialog?.kind === "renameMedia" ? dialog.entry : null}
        draft={draft}
        onClose={closeDialog}
        onRenamed={onRenamed}
        onConflict={onConflict}
      />
      <ConfirmDialog
        open={deletingMedia !== null}
        title={t("admin.workbench.media.delete.title", {
          path: deletingMedia?.path,
        })}
        confirmLabel={t("admin.workbench.media.delete.confirm")}
        confirmVariant="danger"
        onConfirm={confirmDeleteMedia}
        onClose={() => {
          if (!removeMedia.isPending) closeDialog();
        }}
      >
        <p>{t("admin.workbench.media.delete.body")}</p>
        <AlertRegion>
          {removeMedia.error !== null && staleDraft(removeMedia.error) === null
            ? errorText(removeMedia.error)
            : null}
        </AlertRegion>
      </ConfirmDialog>
      <RenameDialog
        key={`rename-${dialogKey}`}
        file={dialog?.kind === "rename" ? dialog.file : null}
        draft={draft}
        onClose={closeDialog}
        onRenamed={onRenamed}
        onConflict={onConflict}
      />
      <ConfirmDialog
        open={deleting !== null}
        title={t("admin.workbench.draft.delete.title", {
          path: deleting?.path,
        })}
        confirmLabel={t("admin.workbench.draft.delete.confirm")}
        confirmVariant="danger"
        onConfirm={confirmDelete}
        onClose={() => {
          if (!remove.isPending) closeDialog();
        }}
      >
        <p>{t("admin.workbench.draft.delete.body")}</p>
        <AlertRegion>
          {remove.error !== null && staleDraft(remove.error) === null
            ? errorText(remove.error)
            : null}
        </AlertRegion>
      </ConfirmDialog>
    </nav>
  );
}
