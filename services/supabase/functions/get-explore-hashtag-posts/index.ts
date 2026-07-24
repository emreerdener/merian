import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  parseJsonBody,
  PublicHttpError,
  publicHttpError,
} from "../_shared/http.ts";
import {
  normalizeCursorTimestamp,
  normalizeExploreHashtag,
  normalizeLimit,
  requireUuid,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
  withExplorePostHashtags,
  withExplorePostMediaItems,
} from "../_shared/explore.ts";
import { fetchExploreHashtagPosts } from "./db.ts";

function makeHttpError(
  status: number,
  message: string,
): PublicHttpError {
  return publicHttpError(status, message);
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, {
      limit: "small",
      allowEmpty: true,
    });
    if (body instanceof Response) return body;

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
