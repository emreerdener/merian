import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  parseJsonBody,
  PublicHttpError,
  publicHttpError,
} from "../_shared/http.ts";
import {
  normalizeCursorTimestamp,
  normalizeExploreFeedFilter,
  normalizeLatitude,
  normalizeLimit,
  normalizeLongitude,
  normalizeNonNegativeInteger,
  requireUuid,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
  withExplorePostHashtags,
  withExplorePostMediaItems,
} from "../_shared/explore.ts";
import {
  normalizeExploreMediaTypes,
  normalizeExploreNearbyRadiusMiles,
  normalizeExploreSpeciesCategories,
} from "../_shared/exploreFeedFilters.ts";
import { fetchExploreFeed } from "./db.ts";

function makeHttpError(
  status: number,
  message: string,
): PublicHttpError {
  return publicHttpError(status, message);
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, {
      limit: "standard",
      allowEmpty: true,
    });
    if (body instanceof Response) return body;

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
    const speciesCategories = normalizeExploreSpeciesCategories(
      body.species_categories,
    );
    const mediaTypes = normalizeExploreMediaTypes(body.media_types);
    const sharedSince = normalizeCursorTimestamp(
      body.shared_since,
      "shared_since",
    );
    const nearbyRadiusMiles = normalizeExploreNearbyRadiusMiles(
      body.nearby_radius_miles,
    );

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

    const data = await withExplorePostHashtags(
      await withExplorePostMediaItems(
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
              {
                speciesCategories,
                mediaTypes,
                sharedSince,
                nearbyRadiusMiles,
              },
              supabaseAdmin,
            ),
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
