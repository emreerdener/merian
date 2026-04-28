// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  fetchInteractiveExplorePost,
  hasMutualBlock,
  requireUuid,
} from "../_shared/explore.ts";
import { fetchExplorePostLikeCount, setExplorePostLike } from "./db.ts";

serve((req: Request) =>
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

    const post = await fetchInteractiveExplorePost(postId, supabaseAdmin);
    if (post.ownerUserId !== user.id && await hasMutualBlock(user.id, post.ownerUserId, supabaseAdmin)) {
      return jsonResponse({ error: "You cannot interact with this Explore post." }, 403);
    }

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
