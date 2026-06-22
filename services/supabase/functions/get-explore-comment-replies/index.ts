import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import {
  normalizeCursorTimestamp,
  normalizeLimit,
  refreshExploreAuthorStateBestEffort,
  requireUuid,
  withExploreAuthorUsernames,
} from "../_shared/explore.ts";
import { fetchExploreCommentReplies } from "./db.ts";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["parent_comment_id"]);
    if (paramErr) return paramErr;

    const parentCommentId = requireUuid(
      body.parent_comment_id,
      "parent_comment_id",
    );
    const limit = normalizeLimit(body.limit, 25, 100);
    const afterCreatedAt = normalizeCursorTimestamp(
      body.after_created_at,
      "after_created_at",
    );
    const afterCommentId = body.after_comment_id == null
      ? null
      : requireUuid(body.after_comment_id, "after_comment_id");

    if ((afterCreatedAt == null) != (afterCommentId == null)) {
      throw makeHttpError(
        400,
        "after_created_at and after_comment_id must be provided together.",
      );
    }

    await refreshExploreAuthorStateBestEffort(
      user.id,
      supabaseAdmin,
      "get-explore-comment-replies",
    );

    const data = await withExploreAuthorUsernames(
      await fetchExploreCommentReplies(
        user.id,
        parentCommentId,
        limit,
        {
          afterCreatedAt,
          afterCommentId,
        },
        supabaseAdmin,
      ),
      supabaseAdmin,
    );
    return jsonResponse({ data }, 200);
  })
);
