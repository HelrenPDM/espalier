import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useApiClient } from "./apiClientContext";
import { unwrap } from "./errors";
import type { components } from "./schema";

/**
 * The query and the mutations of the anonymous insights (task 0014, steps
 * 4 to 7): what the signed-in user has answered in a program, the
 * self-assessment, the vote for a companion format and the feedback. The
 * stations under `src/learner/stations/` reach them through these hooks
 * and import no API client. Each mutation invalidates the participation of
 * its program, so a station shows the recorded state afterwards.
 */
export type Participation = components["schemas"]["Participation"];
export type SelfAssessmentResult =
  components["schemas"]["SelfAssessmentResult"];
export type InsightRecorded = components["schemas"]["InsightRecorded"];
/** The answers by question key: an option key, a scale value or a text. */
export type FeedbackAnswers =
  components["schemas"]["FeedbackRequest"]["answers"];

export const participationQueryKey = ["me", "participation"] as const;

const participationKey = (slug: string) =>
  [...participationQueryKey, slug] as const;

/**
 * Whether the signed-in user has answered the self-assessment and the
 * feedback of the program `slug`, and the ids of the formats they voted
 * for. It holds no segment and no feedback answer.
 */
export function useParticipation(slug: string) {
  const client = useApiClient();
  return useQuery({
    queryKey: participationKey(slug),
    queryFn: async (): Promise<Participation> =>
      unwrap(
        await client.GET("/api/me/participation", {
          params: { query: { program: slug } },
        }),
      ),
  });
}

/**
 * Records the segment `segmentKey` as the self-assessment of the program
 * `slug`. The answer names the path of the enrollment afterwards and
 * whether the user had answered before.
 */
export function useRecordSelfAssessment(slug: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (segmentKey: string): Promise<SelfAssessmentResult> =>
      unwrap(
        await client.POST("/api/self-assessments", {
          body: { program_slug: slug, segment_key: segmentKey },
        }),
      ),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: participationKey(slug) }),
  });
}

/**
 * Votes "would use" for the companion format `formatId` of the program
 * `slug`. On success it adds the format to the cached participation before
 * the invalidation, so the toggle stays pressed while the query reloads.
 */
export function useVoteFormat(slug: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (formatId: string): Promise<InsightRecorded> =>
      unwrap(
        await client.POST("/api/formats/{id}/votes", {
          params: { path: { id: formatId } },
          body: { choice: "would_use" },
        }),
      ),
    onSuccess: (_result, formatId) => {
      queryClient.setQueryData<Participation>(
        participationKey(slug),
        (participation) =>
          participation === undefined ||
          participation.format_votes.includes(formatId)
            ? participation
            : {
                ...participation,
                format_votes: [...participation.format_votes, formatId],
              },
      );
      return queryClient.invalidateQueries({
        queryKey: participationKey(slug),
      });
    },
  });
}

/** Sends the feedback `answers` of the program `slug` once. */
export function useSubmitFeedback(slug: string) {
  const client = useApiClient();
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: async (answers: FeedbackAnswers): Promise<InsightRecorded> =>
      unwrap(
        await client.POST("/api/feedback", {
          body: { program_slug: slug, answers },
        }),
      ),
    onSuccess: () => {
      queryClient.setQueryData<Participation>(
        participationKey(slug),
        (participation) =>
          participation === undefined
            ? participation
            : { ...participation, feedback: true },
      );
      return queryClient.invalidateQueries({
        queryKey: participationKey(slug),
      });
    },
  });
}
