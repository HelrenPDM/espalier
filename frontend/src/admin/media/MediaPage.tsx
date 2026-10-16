import { useId, useRef, useState, type FormEvent } from "react";
import { useTranslation } from "react-i18next";
import {
  MEDIA_KINDS,
  MEDIA_STATUSES,
  NO_MEDIA_FILTERS,
  useMediaLibrary,
  type MediaAsset,
  type MediaFilters,
  type MediaKind,
  type MediaStatus,
} from "../../api/admin/media";
import {
  AlertRegion,
  Button,
  FocusHeading,
  StatusRegion,
  TextField,
} from "../../app/forms";
import { FOCUS_RING, linkClasses } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { CheckboxField } from "../adminParts";
import { formatBytes } from "../workbench/draftErrors";
import { MediaDetailDialog } from "./MediaDetailDialog";
import { MediaKindIcon, MediaState, MediaThumbnail } from "./MediaParts";
import { UploadZone } from "./UploadZone";

const LABEL = "block text-sm font-medium text-gray-900 dark:text-gray-100";
const SELECT = `mt-1 block w-full rounded-md border border-gray-500 bg-white px-3 py-2 text-sm text-gray-900 dark:bg-gray-900 dark:text-gray-100 ${FOCUS_RING}`;
const MUTED = "text-gray-700 dark:text-gray-300";

/** A select with a visible label whose first option means "any". */
function FilterSelect<T extends string>({
  label,
  anyLabel,
  value,
  options,
  optionLabel,
  onChange,
}: {
  label: string;
  anyLabel: string;
  value: T | null;
  options: readonly T[];
  optionLabel: (value: T) => string;
  onChange: (value: T | null) => void;
}) {
  const id = useId();
  return (
    <div>
      <label htmlFor={id} className={LABEL}>
        {label}
      </label>
      <select
        id={id}
        value={value ?? ""}
        onChange={(event) =>
          onChange(
            event.target.value === ""
              ? null
              : (options.find((option) => option === event.target.value) ??
                  null),
          )
        }
        className={SELECT}
      >
        <option value="">{anyLabel}</option>
        {options.map((option) => (
          <option key={option} value={option}>
            {optionLabel(option)}
          </option>
        ))}
      </select>
    </div>
  );
}

/**
 * The filters of the library: kind, state and "unused only" apply on a
 * change, the search by title on submit.
 */
function FilterForm({
  filters,
  onChange,
}: {
  filters: MediaFilters;
  onChange: (filters: MediaFilters) => void;
}) {
  const { t } = useTranslation();
  const headingId = useId();
  const [q, setQ] = useState(filters.q);

  const submit = (event: FormEvent) => {
    event.preventDefault();
    onChange({ ...filters, q: q.trim() });
  };

  return (
    <section aria-labelledby={headingId} className="space-y-3">
      <h2 id={headingId} className="text-xl font-semibold tracking-tight">
        {t("admin.media.filters.title")}
      </h2>
      <form
        noValidate
        onSubmit={submit}
        className="grid max-w-3xl gap-4 sm:grid-cols-2"
      >
        <FilterSelect<MediaKind>
          label={t("admin.media.filters.kind")}
          anyLabel={t("admin.media.filters.anyKind")}
          value={filters.kind}
          options={MEDIA_KINDS}
          optionLabel={(kind) => t(`admin.media.kinds.${kind}`)}
          onChange={(kind) => onChange({ ...filters, kind })}
        />
        <FilterSelect<MediaStatus>
          label={t("admin.media.filters.status")}
          anyLabel={t("admin.media.filters.anyStatus")}
          value={filters.status}
          options={MEDIA_STATUSES}
          optionLabel={(status) => t(`admin.media.status.${status}`)}
          onChange={(status) => onChange({ ...filters, status })}
        />
        <div className="sm:col-span-2">
          <CheckboxField
            label={t("admin.media.filters.unused")}
            checked={filters.unused}
            onChange={(unused) => onChange({ ...filters, unused })}
          />
        </div>
        <div className="sm:col-span-2">
          <TextField
            label={t("admin.media.filters.search")}
            type="search"
            value={q}
            autoComplete="off"
            maxLength={255}
            onChange={(event) => setQ(event.target.value)}
          />
        </div>
        <div className="flex flex-wrap gap-3 sm:col-span-2">
          <Button type="submit">{t("admin.media.filters.submit")}</Button>
          <Button
            variant="secondary"
            onClick={() => {
              setQ("");
              onChange(NO_MEDIA_FILTERS);
            }}
          >
            {t("admin.media.filters.clear")}
          </Button>
        </div>
      </form>
    </section>
  );
}

/** A card of the grid: preview, title (opens the dialog), kind, size, state. */
function MediaCard({
  asset,
  onOpen,
}: {
  asset: MediaAsset;
  onOpen: (asset: MediaAsset) => void;
}) {
  const { t, i18n } = useTranslation();
  return (
    <li
      data-status={asset.status}
      className="flex min-w-0 flex-col gap-3 rounded-lg border border-gray-200 p-3 dark:border-gray-700"
    >
      <MediaThumbnail asset={asset} />
      <h3 className="text-sm font-semibold break-words">
        <button
          type="button"
          onClick={() => onOpen(asset)}
          className={`text-left ${linkClasses}`}
        >
          {asset.title}
        </button>
      </h3>
      <dl className="grid grid-cols-[max-content_minmax(0,1fr)] gap-x-3 gap-y-1 text-xs">
        <dt className="font-medium text-gray-900 dark:text-gray-100">
          {t("admin.media.facts.kind")}
        </dt>
        <dd className={`flex items-center gap-1 ${MUTED}`}>
          <MediaKindIcon kind={asset.kind} className="size-4" />
          {t(`admin.media.kinds.${asset.kind}`)}
        </dd>
        <dt className="font-medium text-gray-900 dark:text-gray-100">
          {t("admin.media.facts.size")}
        </dt>
        <dd className={MUTED}>
          {asset.bytes === null ? "-" : formatBytes(asset.bytes, i18n.language)}
        </dd>
        <dt className="font-medium text-gray-900 dark:text-gray-100">
          {t("admin.media.facts.state")}
        </dt>
        <dd className={MUTED}>
          <MediaState asset={asset} subject={asset.title} />
        </dd>
      </dl>
    </li>
  );
}

/**
 * `/admin/media` (task 0018, step 19): the media library of the authors.
 * An upload zone for several files with a progress bar per file, filters
 * for kind, state and "unused", a search by title, and a grid of cards
 * with a preview, the title, the kind, the size, the state with the
 * progress of a conversion and the failure text per code and reason tag.
 * The list loads 50 assets per page, newest first, and reads the loaded
 * pages again every two seconds while an asset is `queued` or
 * `processing`. A title opens the detail dialog. Titles, file names and
 * codes render as text (ASVS 3.2.2).
 */
export function MediaPage() {
  const { t } = useTranslation();
  const uploadHeadingId = useId();
  const listHeadingId = useId();
  const listRef = useRef<HTMLHeadingElement>(null);
  const [filters, setFilters] = useState<MediaFilters>(NO_MEDIA_FILTERS);
  const [open, setOpen] = useState<MediaAsset | null>(null);
  const [announcement, setAnnouncement] = useState<string | null>(null);
  const library = useMediaLibrary(filters);
  const assets = library.data?.pages.flatMap((page) => page.items) ?? [];
  const filtered =
    filters.kind !== null ||
    filters.status !== null ||
    filters.unused ||
    filters.q !== "";

  let list;
  if (library.isPending)
    list = <LoadingStatus text={t("admin.media.list.loading")} />;
  else if (library.isError && assets.length === 0)
    list = (
      <p role="alert" className={MUTED}>
        {t("admin.media.list.loadFailed")}
      </p>
    );
  else if (assets.length === 0)
    list = (
      <p className={MUTED}>
        {filtered ? t("admin.media.list.noMatch") : t("admin.media.list.empty")}
      </p>
    );
  else
    list = (
      <>
        <ul className="grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
          {assets.map((asset) => (
            <MediaCard key={asset.id} asset={asset} onOpen={setOpen} />
          ))}
        </ul>
        {library.hasNextPage && (
          <div className="mt-4 flex flex-wrap items-center gap-4">
            <Button
              variant="secondary"
              disabled={library.isFetchingNextPage}
              onClick={() => void library.fetchNextPage()}
            >
              {t("admin.media.list.more")}
            </Button>
            {library.isFetchingNextPage && (
              <LoadingStatus text={t("admin.media.list.loadingMore")} />
            )}
          </div>
        )}
      </>
    );

  return (
    <section className="space-y-10">
      <div className="space-y-2">
        <FocusHeading>{t("admin.media.title")}</FocusHeading>
        <p className={`max-w-3xl ${MUTED}`}>{t("admin.media.intro")}</p>
      </div>

      <section
        aria-labelledby={uploadHeadingId}
        className="max-w-3xl space-y-3"
      >
        <h2
          id={uploadHeadingId}
          className="text-xl font-semibold tracking-tight"
        >
          {t("admin.media.upload.title")}
        </h2>
        <p className={`text-sm ${MUTED}`}>{t("admin.media.upload.intro")}</p>
        <UploadZone kinds={MEDIA_KINDS} />
      </section>

      <FilterForm filters={filters} onChange={setFilters} />

      <section aria-labelledby={listHeadingId} className="space-y-4">
        <h2
          id={listHeadingId}
          ref={listRef}
          tabIndex={-1}
          className="text-xl font-semibold tracking-tight focus:outline-none"
        >
          {t("admin.media.list.title")}
        </h2>
        <StatusRegion>{announcement}</StatusRegion>
        <AlertRegion>
          {library.isError && assets.length > 0
            ? t("admin.media.list.refreshFailed")
            : null}
        </AlertRegion>
        {list}
      </section>

      <MediaDetailDialog
        asset={open}
        onClose={() => setOpen(null)}
        onDeleted={(asset) => {
          setOpen(null);
          setAnnouncement(t("admin.media.delete.done", { title: asset.title }));
          // The card that opened the dialog left with its asset.
          requestAnimationFrame(() => listRef.current?.focus());
        }}
      />
    </section>
  );
}
