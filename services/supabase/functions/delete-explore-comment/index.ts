// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { fetchDeletableComment, fetchExplorePostCommentCount, removeExploreComment } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["comment_id"]);
    if (paramErr) return paramErr;

    const commentId = requireUuid(body.comment_id, "comment_id");
    const comment = await fetchDeletableComment(commentId, user.id, supabaseAdmin);
    await removeExploreComment(commentId, comment.action, user.id, supabaseAdmin);
    const commentCount = await fetchExplorePostCommentCount(comment.postId, supabaseAdmin);

    return jsonResponse({
      success: true,
      comment_id: commentId,
      comment_count: commentCount,
      action: comment.action,
    });
  }),
);
