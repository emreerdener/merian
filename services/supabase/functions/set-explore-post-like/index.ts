import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  assertCanInteractWithExplorePost,
  requireUuid,
} from "../_shared/explore.ts";
import { fetchExplorePostLikeCount, setExplorePostLike } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["post_id", "liked"]);
    if (paramErr) return paramErr;

    const postId = requireUuid(body.post_id, "post_id");
    if (typeof body.liked !== "boolean") {
      return jsonResponse({ error: "liked must be a boolean." }, 400);
    }

    await assertCanInteractWithExplorePost(postId, user.id, supabaseAdmin);

    await setExplorePostLike(postId, user.id, body.liked, supabaseAdmin);
    const likeCount = await fetchExplorePostLikeCount(postId, supabaseAdmin);

    return jsonResponse({
      success: true,
      post_id: postId,
      viewer_has_liked: body.liked,
      like_count: likeCount,
    });
  }),
);
