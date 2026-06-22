import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  normalizeCursorTimestamp,
  normalizeExploreFeedFilter,
  normalizeLatitude,
  normalizeLimit,
  normalizeLongitude,
  normalizeNonNegativeInteger,
  refreshExploreAuthorStateBestEffort,
  requireUuid,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
  withExplorePostHashtags,
} from "../_shared/explore.ts";
import { fetchExploreFeed } from "./db.ts";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      // Body is optional.
    }

    const limit = normalizeLimit(body.limit, 20, 100);
    const filter = normalizeExploreFeedFilter(body.filter);
    const beforeSharedAt = normalizeCursorTimestamp(
      body.before_shared_at,
      "before_shared_at",
    );
    const beforePostId = body.before_post_id == null
      ? null
      : requireUuid(body.before_post_id, "before_post_id");
    const beforeRankingValue = normalizeNonNegativeInteger(
      body.before_ranking_value,
      "before_ranking_value",
    );
    const latitude = normalizeLatitude(body.latitude, "latitude");
    const longitude = normalizeLongitude(body.longitude, "longitude");

    if (filter === "trending") {
      const hasAnyCursor = beforeRankingValue != null ||
        beforeSharedAt != null || beforePostId != null;
      if (
        hasAnyCursor &&
        (beforeRankingValue == null || beforeSharedAt == null ||
          beforePostId == null)
      ) {
        throw makeHttpError(
          400,
          "before_ranking_value, before_shared_at, and before_post_id must be provided together for trending pagination.",
        );
      }
    } else {
      if ((beforeSharedAt == null) != (beforePostId == null)) {
        throw makeHttpError(
          400,
          "before_shared_at and before_post_id must be provided together.",
        );
      }

      if (beforeRankingValue != null) {
        throw makeHttpError(
          400,
          "before_ranking_value is only supported for the trending filter.",
        );
      }
    }

    if (filter === "nearby" && (latitude == null || longitude == null)) {
      throw makeHttpError(
        400,
        "latitude and longitude are required for the nearby filter.",
      );
    }

    await refreshExploreAuthorStateBestEffort(
      user.id,
      supabaseAdmin,
      "get-explore-feed",
    );

    const data = await withExplorePostHashtags(
      await withExploreAuthorUsernames(
        await withExploreAuthorProBadges(
          await fetchExploreFeed(
            user.id,
            limit,
            filter,
            {
              beforeSharedAt,
              beforePostId,
              beforeRankingValue,
            },
            {
              latitude,
              longitude,
            },
            supabaseAdmin,
          ),
          supabaseAdmin,
        ),
        supabaseAdmin,
      ),
      supabaseAdmin,
    );

    return jsonResponse({ data }, 200);
  })
);
