import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  parseJsonBody,
  PublicHttpError,
  publicHttpError,
} from "../_shared/http.ts";
import {
  normalizeCursorTimestamp,
  normalizeLimit,
  requireUuid,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
  withExplorePostHashtags,
  withExplorePostMediaItems,
} from "../_shared/explore.ts";
import { fetchExploreAuthorPosts } from "./db.ts";

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

    const authorUserId = requireUuid(body.author_user_id, "author_user_id");
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
            await fetchExploreAuthorPosts(
              user.id,
              authorUserId,
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
