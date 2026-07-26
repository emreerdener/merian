import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  normalizeLimit,
  requireUuid,
  withExploreAuthorProfileProBadge,
  withExploreAuthorUsernames,
} from "../_shared/explore.ts";
import { fetchFieldTripProfileSummaries } from "../field-trips/db.ts";
import {
  fetchExploreAuthorProfile,
  fetchOwnedExplorePublicationSummary,
} from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;

    const paramErr = requireParams(body, ["author_user_id"]);
    if (paramErr) return paramErr;

    const authorUserId = requireUuid(body.author_user_id, "author_user_id");
    const previewLimit = normalizeLimit(body.preview_limit, 9, 30);
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
    const [
      profileWithProBadge,
      [authorWithUsername],
      previewPosts,
      fieldTrips,
      ownerPublicationSummary,
    ] = await Promise.all([
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
      profile.author_user_id === user.id
        ? fetchOwnedExplorePublicationSummary(user.id, supabaseAdmin)
        : Promise.resolve(null),
    ]);
    const data = {
      ...profileWithProBadge,
      author_username: authorWithUsername.author_username,
      preview_posts: previewPosts,
      field_trips: fieldTrips,
      viewer_can_report: profile.author_user_id !== user.id,
      owner_publication_summary: ownerPublicationSummary,
    };

    return jsonResponse({ data }, 200);
  })
);
