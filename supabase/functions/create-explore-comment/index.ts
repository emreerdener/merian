// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  assertCanInteractWithExplorePost,
  fetchPublicAuthorIdentity,
  requireUuid,
  syncPublicAuthorIdentity,
} from "../_shared/explore.ts";
import { fetchExplorePostCommentCount, insertExploreComment } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

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

    await assertCanInteractWithExplorePost(postId, user.id, supabaseAdmin);

    await syncPublicAuthorIdentity(user.id, supabaseAdmin);
    const inserted = await insertExploreComment(postId, user.id, rawBody, supabaseAdmin);
    const authorIdentity = await fetchPublicAuthorIdentity(user.id, supabaseAdmin);
    const commentCount = await fetchExplorePostCommentCount(postId, supabaseAdmin);

    return jsonResponse({
      success: true,
      comment: {
        comment_id: inserted.id,
        post_id: inserted.post_id,
        author_user_id: user.id,
        author_name: authorIdentity.authorName,
        author_avatar_url: authorIdentity.authorAvatarUrl,
        body: rawBody,
        created_at: inserted.created_at,
        viewer_can_delete: true,
        viewer_can_moderate: false,
        viewer_can_report: false,
      },
      comment_count: commentCount,
    });
  }),
);
