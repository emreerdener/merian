import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  normalizeCursorTimestamp,
  normalizeExploreHashtag,
  normalizeLimit,
  refreshExploreAuthorStateBestEffort,
  requireUuid,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
  withExplorePostMediaItems,
  withExplorePostHashtags,
} from "../_shared/explore.ts";
import { fetchExploreHashtagPosts } from "./db.ts";

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

    const hashtag = normalizeExploreHashtag(body.hashtag, "hashtag");
    const limit = normalizeLimit(body.limit, 30, 100);
    const beforeSharedAt = normalizeCursorTimestamp(
      body.before_shared_at,
      "before_shared_at",
    );
    const beforePostId = body.before_post_id == null
      ? null
      : requireUuid(body.before_post_id, "before_post_id");

    if ((beforeSharedAt == null) != (beforePostId == null)) {
      throw makeHttpError(
        400,
        "before_shared_at and before_post_id must be provided together.",
      );
    }

    await refreshExploreAuthorStateBestEffort(
      user.id,
      supabaseAdmin,
      "get-explore-hashtag-posts",
    );

    const data = await withExplorePostHashtags(
      await withExplorePostMediaItems(
        await withExploreAuthorUsernames(
          await withExploreAuthorProBadges(
            await fetchExploreHashtagPosts(
              user.id,
              hashtag,
              limit,
              beforeSharedAt,
              beforePostId,
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
