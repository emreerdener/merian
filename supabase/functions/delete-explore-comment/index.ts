// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { fetchDeletableComment, fetchExplorePostCommentCount, softDeleteComment } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["comment_id"]);
    if (paramErr) return paramErr;

    const commentId = requireUuid(body.comment_id, "comment_id");
    const comment = await fetchDeletableComment(commentId, user.id, supabaseAdmin);
    await softDeleteComment(commentId, supabaseAdmin);
    const commentCount = await fetchExplorePostCommentCount(comment.postId, supabaseAdmin);

    return jsonResponse({
      success: true,
      comment_id: commentId,
      comment_count: commentCount,
    });
  }),
);
