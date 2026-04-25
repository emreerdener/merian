// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import {
  fetchInteractiveExplorePost,
  fetchPublicAuthorName,
  hasMutualBlock,
  requireUuid,
  syncPublicAuthorIdentity,
} from "../_shared/explore.ts";
import { fetchExplorePostCommentCount, insertExploreComment } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["post_id", "body"]);
    if (paramErr) return paramErr;

    const postId = requireUuid(body.post_id, "post_id");
    const rawBody = typeof body.body === "string" ? body.body.trim() : "";
    if (rawBody.length === 0) {
      return jsonResponse({ error: "body must be a non-empty string." }, 400);
    }
    if (rawBody.length > 500) {
      return jsonResponse({ error: "body must be 500 characters or fewer." }, 400);
    }

    const post = await fetchInteractiveExplorePost(postId, supabaseAdmin);
    if (post.ownerUserId !== user.id && await hasMutualBlock(user.id, post.ownerUserId, supabaseAdmin)) {
      return jsonResponse({ error: "You cannot interact with this Explore post." }, 403);
    }

    await syncPublicAuthorIdentity(user.id, supabaseAdmin);
    const inserted = await insertExploreComment(postId, user.id, rawBody, supabaseAdmin);
    const authorName = await fetchPublicAuthorName(user.id, supabaseAdmin);
    const commentCount = await fetchExplorePostCommentCount(postId, supabaseAdmin);

    return jsonResponse({
      success: true,
      comment: {
        comment_id: inserted.id,
        post_id: inserted.post_id,
        author_user_id: user.id,
        author_name: authorName,
        body: rawBody,
        created_at: inserted.created_at,
        viewer_can_delete: true,
      },
      comment_count: commentCount,
    });
  }),
);
