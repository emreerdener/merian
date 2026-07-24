import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  requireUuid,
  withExploreAuthorProBadges,
  withExploreAuthorUsernames,
  withExplorePostHashtags,
  withExplorePostMediaItems,
} from "../_shared/explore.ts";
import { fetchExplorePost } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;

    const paramErr = requireParams(body, ["post_id"]);
    if (paramErr) return paramErr;

    const postId = requireUuid(body.post_id, "post_id");
    let data;
    try {
      const fetchedPost = await fetchExplorePost(
        user.id,
        postId,
        supabaseAdmin,
      );
      data = fetchedPost
        ? (await withExplorePostHashtags(
          await withExplorePostMediaItems(
            await withExploreAuthorUsernames(
              await withExploreAuthorProBadges([fetchedPost], supabaseAdmin),
              supabaseAdmin,
            ),
            supabaseAdmin,
          ),
          supabaseAdmin,
        ))[0]
        : null;
    } catch (error) {
      logStructuredError("explore_notification_open_fetch_failed", {
        user_id: user.id,
        post_id: postId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }

    if (!data) {
      return jsonResponse({ error: "Explore post not found" }, 404);
    }

    return jsonResponse({ data }, 200);
  })
);
