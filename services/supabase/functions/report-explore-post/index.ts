import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { fetchReportablePost, upsertExplorePostReport } from "./db.ts";

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
    const paramErr = requireParams(body, ["post_id", "reason"]);
    if (paramErr) return paramErr;

    const postId = requireUuid(body.post_id, "post_id");
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

    const post = await fetchReportablePost(postId, user.id, supabaseAdmin);
    await upsertExplorePostReport({
      postId,
      reporterUserId: user.id,
      postAuthorUserId: post.postAuthorUserId,
      reason,
      details,
    }, supabaseAdmin);

    return jsonResponse({
      success: true,
      post_id: postId,
      message: "Report submitted for moderation.",
    });
  })
);
