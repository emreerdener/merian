import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { fetchReportableComment, upsertExploreCommentReport } from "./db.ts";

const VALID_REPORT_REASONS = new Set([
  "Spam",
  "Harassment",
  "Inappropriate content",
  "Other",
]);

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req, { limit: "small" });
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["comment_id", "reason"]);
    if (paramErr) return paramErr;

    const commentId = requireUuid(body.comment_id, "comment_id");
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    const details = typeof body.details === "string"
      ? body.details.trim().slice(0, 500)
      : null;

    if (!VALID_REPORT_REASONS.has(reason)) {
      return jsonResponse(
        {
          error: `Invalid reason. Must be one of: ${
            [...VALID_REPORT_REASONS].join(", ")
          }.`,
        },
        400,
      );
    }

    const comment = await fetchReportableComment(
      commentId,
      user.id,
      supabaseAdmin,
    );
    await upsertExploreCommentReport({
      commentId: comment.commentId,
      postId: comment.postId,
      reporterUserId: user.id,
      commentAuthorUserId: comment.commentAuthorUserId,
      reason,
      details,
    }, supabaseAdmin);

    return jsonResponse({
      success: true,
      comment_id: commentId,
      message: "Report submitted for moderation.",
    }, 200);
  })
);
