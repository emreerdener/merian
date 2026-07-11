import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import {
  normalizeLimit,
  refreshExploreAuthorStateBestEffort,
  requireUuid,
  withExploreAuthorProfileProBadge,
  withExploreAuthorUsernames,
} from "../_shared/explore.ts";
import { fetchFieldTripProfileSummaries } from "../field-trips/db.ts";
import { fetchExploreAuthorProfile } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["author_user_id"]);
    if (paramErr) return paramErr;

    const authorUserId = requireUuid(body.author_user_id, "author_user_id");
    const previewLimit = normalizeLimit(body.preview_limit, 9, 30);
    await refreshExploreAuthorStateBestEffort(
      user.id,
      supabaseAdmin,
      "get-explore-author-profile",
    );

    const profile = await fetchExploreAuthorProfile(
      user.id,
      authorUserId,
      previewLimit,
      supabaseAdmin,
    );

    if (!profile) {
      return jsonResponse({ error: "Explore author profile not found" }, 404);
    }

    // These enrichments are independent. Running them together keeps profile latency
    // bounded by the slowest lookup instead of adding every database round trip.
    const [profileWithProBadge, [authorWithUsername], previewPosts, fieldTrips] =
      await Promise.all([
        withExploreAuthorProfileProBadge(profile, supabaseAdmin),
        withExploreAuthorUsernames(
          [{ author_user_id: profile.author_user_id }],
          supabaseAdmin,
        ),
        Array.isArray(profile.preview_posts)
          ? withExploreAuthorUsernames(
            profile.preview_posts as Array<{ author_user_id: string }>,
            supabaseAdmin,
          )
          : Promise.resolve(profile.preview_posts),
        fetchFieldTripProfileSummaries(
          user.id,
          authorUserId,
          6,
          supabaseAdmin,
        ),
      ]);
    const data = {
      ...profileWithProBadge,
      author_username: authorWithUsername.author_username,
      preview_posts: previewPosts,
      field_trips: fieldTrips,
    };

    return jsonResponse({ data }, 200);
  })
);
