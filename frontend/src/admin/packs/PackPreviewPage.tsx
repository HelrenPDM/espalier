import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import createClient from "openapi-fetch";
import { useId, useMemo, useState } from "react";
import { useTranslation } from "react-i18next";
import { Link, Navigate, Outlet, Route, Routes, useParams } from "react-router";
import { usePackImport, type PackImport } from "../../api/admin/packs";
import { ApiClientProvider } from "../../api/ApiClientProvider";
import { ApiError } from "../../api/errors";
import type { paths } from "../../api/paths";
import { linkClasses } from "../../app/formStyles";
import { LoadingStatus } from "../../app/LoadingStatus";
import { BackToProgram } from "../../learner/BackToProgram";
import { GlossaryPage } from "../../learner/GlossaryPage";
import { ProgramPage } from "../../learner/ProgramPage";
import { StationPage } from "../../learner/StationPage";
import { EmbedConsentContext } from "../../player/embedConsent";
import { PlayerProvider } from "../../player/PlayerProvider";
import { ProgramBaseContext } from "../../player/programBase";
import { RuntimeContext } from "../../player/RuntimeContext";
import type { Provenance } from "../../player/runtime";
import type { PackMedia } from "../../runtimes/media";
import {
  StandaloneRuntime,
  isPackPayload,
  type PackPayload,
} from "../../runtimes/standalone";

/** The provenance values of blocks and items, in the order of the badge. */
const PROVENANCES = [
  "invented",
  "sourced",
  "vendor_statement",
  "assumption",
  "placeholder",
] as const satisfies readonly Provenance[];

/** The number of blocks and items per provenance value of `payload`. */
function provenanceCounts(payload: PackPayload) {
  const counts = new Map<Provenance, { blocks: number; items: number }>(
    PROVENANCES.map((value) => [value, { blocks: 0, items: 0 }]),
  );
  for (const module of payload.modules) {
    for (const lesson of module.lessons)
      for (const block of lesson.blocks) {
        const entry = counts.get(block.provenance);
        if (entry !== undefined) entry.blocks += 1;
      }
    for (const item of module.items) {
      const entry = counts.get(item.provenance);
      if (entry !== undefined) entry.items += 1;
    }
  }
  return PROVENANCES.map((value) => ({
    value,
    ...(counts.get(value) ?? { blocks: 0, items: 0 }),
  }));
}

const CELL = "border border-gray-300 px-3 py-1 text-left dark:border-gray-700";

function ProvenanceOverview({ payload }: { payload: PackPayload }) {
  const { t } = useTranslation();
  const descriptionId = useId();
  return (
    <div className="space-y-1">
      <table aria-describedby={descriptionId} className="text-sm">
        <caption className="text-left font-semibold">
          {t("admin.preview.provenance.title")}
        </caption>
        <thead>
          <tr>
            <th scope="col" className={CELL}>
              {t("admin.preview.provenance.value")}
            </th>
            <th scope="col" className={CELL}>
              {t("admin.preview.provenance.blocks")}
            </th>
            <th scope="col" className={CELL}>
              {t("admin.preview.provenance.items")}
            </th>
          </tr>
        </thead>
        <tbody>
          {provenanceCounts(payload).map(({ value, blocks, items }) => (
            <tr key={value}>
              <th scope="row" className={`${CELL} font-medium`}>
                {t(`provenance.${value}`)}
              </th>
              <td className={`${CELL} tabular-nums`}>{blocks}</td>
              <td className={`${CELL} tabular-nums`}>{items}</td>
            </tr>
          ))}
        </tbody>
      </table>
      <p id={descriptionId} className="text-sm">
        {t("admin.preview.provenance.description")}
      </p>
    </div>
  );
}

/** The handbook reads the rules of a published program, so the preview has none. */
function PreviewHandbook() {
  const { t } = useTranslation();
  return (
    <section className="max-w-3xl">
      <p className="text-sm">
        <BackToProgram />
      </p>
      <h1 className="mt-4 text-2xl font-semibold tracking-tight">
        {t("handbook.title")}
      </h1>
      <p className="mt-4 text-gray-700 dark:text-gray-300">
        {t("admin.preview.handbook")}
      </p>
    </section>
  );
}

function PreviewProgram({ runtime }: { runtime: StandaloneRuntime }) {
  const { slug = "" } = useParams();
  return (
    <RuntimeContext.Provider value={runtime}>
      <PlayerProvider slug={slug}>
        <Outlet />
      </PlayerProvider>
    </RuntimeContext.Provider>
  );
}

/**
 * The media of the import as the resolution of the blocks reads them
 * (`PackMediaEntry`), in path order, as a string. It leaves out `status`
 * and `progress`: the import is read again every two seconds while a file
 * converts, and only a file that turns `ready` (and gets its URL) changes
 * the key, so the runtime of the preview, and with it the answers, the
 * path, the open explanations and a playing video, survives every other
 * read.
 */
function resolvedMediaKey(media: PackImport["media"]): string {
  const entries = Object.keys(media)
    .sort()
    .map((path): [string, PackMedia[string]] => {
      const {
        kind,
        url,
        width,
        height,
        duration_ms,
        has_audio,
        has_alpha,
        animated,
        poster_url,
      } = media[path];
      return [
        path,
        {
          kind,
          url,
          width,
          height,
          duration_ms,
          has_audio,
          has_alpha,
          animated,
          poster_url,
        },
      ];
    });
  return JSON.stringify(Object.fromEntries(entries));
}

/** Every request of the player in the preview answers 404 without leaving the browser. */
const offlineFetch = async () =>
  new Response(JSON.stringify({ error: "not_found" }), {
    status: 404,
    headers: { "content-type": "application/json" },
  });

/**
 * The player on `payload` with `StandaloneRuntime`, below the route of the
 * preview. The routes are those of the learner pages (0012), which build
 * their links from `ProgramBaseContext`, here the program path below the
 * preview route, so that every link and the back button stay in the
 * preview. The player gets
 * a query cache of its own and an API client that sends nothing: the
 * stations that read or record platform data (self-assessment, credential,
 * companion formats, feedback) show their notices, and the preview writes
 * no record and reads no data of the live program. The media of the
 * blocks resolve through the `media` of the import and the allowlists of
 * `mediaPolicy`, whose `embed_consent` decides when an embed player loads
 * (task 0018). The runtime is built again only when the resolved media
 * change (`resolvedMediaKey`), so the progress of a conversion leaves the
 * player as it is.
 */
function PreviewPlayer({
  id,
  payload,
  media,
  mediaPolicy,
}: {
  id: string;
  payload: PackPayload;
  media: PackImport["media"];
  mediaPolicy: PackImport["media_policy"];
}) {
  const mediaKey = resolvedMediaKey(media);
  const runtime = useMemo(
    () =>
      new StandaloneRuntime(
        payload,
        JSON.parse(mediaKey) as PackMedia,
        mediaPolicy,
      ),
    [payload, mediaKey, mediaPolicy],
  );
  const programBase = `/admin/packs/${encodeURIComponent(id)}/preview/programs`;
  const [queryClient] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: { retry: false },
          mutations: { retry: false },
        },
      }),
  );
  const [client] = useState(() =>
    createClient<paths>({ baseUrl: "", fetch: offlineFetch }),
  );

  return (
    <QueryClientProvider client={queryClient}>
      <ApiClientProvider client={client}>
        <EmbedConsentContext.Provider value={mediaPolicy.embed_consent}>
          <ProgramBaseContext.Provider value={programBase}>
            <Routes>
              <Route
                path="programs/:slug"
                element={<PreviewProgram runtime={runtime} />}
              >
                <Route index element={<ProgramPage />} />
                <Route path="stations/:position" element={<StationPage />} />
                <Route path="glossary" element={<GlossaryPage />} />
                <Route path="handbook" element={<PreviewHandbook />} />
              </Route>
              <Route
                path="*"
                element={
                  <Navigate
                    to={`${programBase}/${encodeURIComponent(payload.key)}`}
                    replace
                  />
                }
              />
            </Routes>
          </ProgramBaseContext.Provider>
        </EmbedConsentContext.Provider>
      </ApiClientProvider>
    </QueryClientProvider>
  );
}

/**
 * `/admin/packs/:id/preview/*`: the player with `StandaloneRuntime` on the
 * payload of a `validated` import (task 0015, steps 9 and 11), below a
 * visible "Preview" banner with a provenance overview that counts the
 * blocks and items per provenance value. An import without a payload shows
 * a notice.
 */
export function PackPreviewPage() {
  const { t } = useTranslation();
  const { id = "" } = useParams();
  const query = usePackImport(id);
  const bannerId = useId();

  const back = (
    <Link to={`/admin/packs/${id}`} className={linkClasses}>
      {t("admin.preview.back")}
    </Link>
  );

  if (query.isPending) return <LoadingStatus text={t("admin.pack.loading")} />;

  const { data } = query;
  const payload = data?.payload;
  if (query.isError || data === undefined || !isPackPayload(payload))
    return (
      <section className="max-w-3xl space-y-4">
        <h1 className="text-2xl font-semibold tracking-tight">
          {t("admin.preview.title")}
        </h1>
        <p role="alert" className="text-gray-700 dark:text-gray-300">
          {query.isError
            ? query.error instanceof ApiError &&
              (query.error.status === 404 || query.error.status === 422)
              ? t("admin.pack.notFound")
              : t("admin.pack.loadFailed")
            : t("admin.preview.noPayload")}
        </p>
        <p className="text-sm">{back}</p>
      </section>
    );

  return (
    <div className="space-y-8">
      <section
        aria-labelledby={bannerId}
        className="no-print space-y-3 rounded-lg border-2 border-amber-600 bg-amber-50 p-4 text-gray-900 dark:border-amber-400 dark:bg-gray-900 dark:text-gray-100"
      >
        <p
          id={bannerId}
          className="text-lg font-semibold tracking-tight text-amber-900 dark:text-amber-200"
        >
          {t("admin.preview.title")}
        </p>
        <p className="font-medium">
          {t("admin.preview.label", {
            title: payload.title,
            version: payload.version,
          })}
        </p>
        <p className="text-sm">{t("admin.preview.text")}</p>
        <p className="text-sm">{back}</p>
        <ProvenanceOverview payload={payload} />
      </section>
      <PreviewPlayer
        id={id}
        payload={payload}
        media={data.media}
        mediaPolicy={data.media_policy}
      />
    </div>
  );
}
