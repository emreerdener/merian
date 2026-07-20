import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import {
  assertCanInteractWithExplorePost,
  normalizeLimit,
  requireUuid,
} from "../_shared/explore.ts";
import { fetchReplyParent } from "../create-explore-comment/db.ts";
import { fetchExploreMentionSuggestions } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["post_id"]);
    if (paramErr) return paramErr;

    const postId = requireUuid(body.post_id, "post_id");
    const parentCommentId = body.parent_comment_id == null
      ? null
      : requireUuid(body.parent_comment_id, "parent_comment_id");
    const query = typeof body.query === "string" ? body.query : "";
    const limit = normalizeLimit(body.limit, 8, 12);

    await assertCanInteractWithExplorePost(postId, user.id, supabaseAdmin);
    if (parentCommentId != null) {
      await fetchReplyParent(parentCommentId, postId, supabaseAdmin);
    }

    const data = await fetchExploreMentionSuggestions(
      user.id,
      postId,
      parentCommentId,
      query,
      limit,
      supabaseAdmin,
    );

    return jsonResponse({ data }, 200);
  })
);
