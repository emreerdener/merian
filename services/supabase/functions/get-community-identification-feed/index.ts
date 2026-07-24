import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  normalizeCursorTimestamp,
  normalizeLatitude,
  normalizeLimit,
  normalizeLongitude,
  requireUuid,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
  withExplorePostMediaItems,
} from "../_shared/explore.ts";
import { makeHttpError } from "../_shared/communityIdentification.ts";
import { parseJsonBody } from "../_shared/http.ts";
import { fetchCommunityIdentificationFeed } from "./db.ts";
import type {
  CommunityIdentificationFeedScope,
  CommunityIdentificationRequestGroup,
} from "./db.ts";

function normalizeCommunityFeedScope(
  value: unknown,
): CommunityIdentificationFeedScope {
  if (value == null) return "all";
  if (value === "all" || value === "mine") return value;
  throw makeHttpError(400, "scope must be one of: all, mine.");
}

function normalizeCommunityRequestGroup(
  value: unknown,
): CommunityIdentificationRequestGroup {
  if (value == null) return "all";
  if (
    value === "all" ||
    value === "plants" ||
    value === "birds" ||
    value === "insects" ||
    value === "fungi" ||
    value === "mammals" ||
    value === "reptiles_amphibians"
  ) {
    return value;
  }
  throw makeHttpError(
    400,
    "group must be one of: all, plants, birds, insects, fungi, mammals, reptiles_amphibians.",
  );
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, {
      limit: "small",
      allowEmpty: true,
    });
    if (body instanceof Response) return body;

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
    const group = normalizeCommunityRequestGroup(body.group);

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
      await withExplorePostMediaItems(
        await withExploreAuthorProBadges(
          await fetchCommunityIdentificationFeed(
            user.id,
            scope,
            group,
            limit,
            { beforeRequestedAt, beforeRequestId },
            { latitude, longitude },
            supabaseAdmin,
          ),
          supabaseAdmin,
        ),
        supabaseAdmin,
      ),
      supabaseAdmin,
    );

    return jsonResponse({ data: rows }, 200);
  })
);
