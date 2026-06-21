// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  normalizeCursorTimestamp,
  normalizeLatitude,
  normalizeLimit,
  normalizeLongitude,
  requireUuid,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
} from "../_shared/explore.ts";
import { makeHttpError } from "../_shared/communityIdentification.ts";
import { fetchCommunityIdentificationFeed } from "./db.ts";
import type { CommunityIdentificationFeedScope } from "./db.ts";

function normalizeCommunityFeedScope(
  value: unknown,
): CommunityIdentificationFeedScope {
  if (value == null) return "all";
  if (value === "all" || value === "mine") return value;
  throw makeHttpError(400, "scope must be one of: all, mine.");
}

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      // Body is optional.
    }

    const limit = normalizeLimit(body.limit, 30, 100);
    const beforeRequestedAt = normalizeCursorTimestamp(
      body.before_requested_at,
      "before_requested_at",
    );
    const beforeRequestId = body.before_request_id == null
      ? null
      : requireUuid(body.before_request_id, "before_request_id");
    const latitude = normalizeLatitude(body.latitude, "latitude");
    const longitude = normalizeLongitude(body.longitude, "longitude");
    const scope = normalizeCommunityFeedScope(body.scope);

    if ((beforeRequestedAt == null) != (beforeRequestId == null)) {
      throw makeHttpError(
        400,
        "before_requested_at and before_request_id must be provided together.",
      );
    }

    if ((latitude == null) != (longitude == null)) {
      throw makeHttpError(
        400,
        "latitude and longitude must be provided together.",
      );
    }

    const rows = await withExploreAuthorUsernames(
      await withExploreAuthorProBadges(
        await fetchCommunityIdentificationFeed(
          user.id,
          scope,
          limit,
          { beforeRequestedAt, beforeRequestId },
          { latitude, longitude },
          supabaseAdmin,
        ),
        supabaseAdmin,
      ),
      supabaseAdmin,
    );

    return jsonResponse({ data: rows }, 200);
  })
);
