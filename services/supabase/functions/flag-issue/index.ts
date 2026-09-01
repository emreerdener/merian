import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  parseJsonBody,
  publicHttpError,
  requireParams,
} from "../_shared/http.ts";
import {
  fetchReportablePost,
  upsertExplorePostReport,
} from "../report-explore-post/db.ts";
import {
  isLegacyCommunityPostReport,
  resolveLegacyCommunityPostReport,
  submitOwnedFlagIssue,
} from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;

    const paramErr = requireParams(body, ["scanId", "flagReason"]);
    if (paramErr) return paramErr;

    const { scanId, flagReason, userSuggestion } = body;

    const UUID_RE =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (typeof scanId !== "string" || !UUID_RE.test(scanId)) {
      return jsonResponse({ error: "scanId must be a valid UUID." }, 400);
    }

    const VALID_FLAG_REASONS = new Set([
      "Incorrect species",
      "Inappropriate content",
      "Bad image quality",
      "Other",
    ]);

    if (
      typeof flagReason !== "string" ||
      !VALID_FLAG_REASONS.has(flagReason)
    ) {
      return jsonResponse(
        {
          error: `Invalid flagReason. Must be one of: ${
            [...VALID_FLAG_REASONS].join(", ")
          }.`,
        },
        400,
      );
    }
    if (
      userSuggestion !== undefined &&
      typeof userSuggestion !== "string"
    ) {
      return jsonResponse(
        { error: "userSuggestion must be a string." },
        400,
      );
    }

    const result = await submitOwnedFlagIssue(
      scanId,
      user.id,
      flagReason,
      userSuggestion as string | undefined,
      supabaseAdmin,
    );
    if (result === "not_found") {
      throw publicHttpError(404, "Scan is not available for reporting.");
    }

    if (result === "not_owner") {
      if (
        !isLegacyCommunityPostReport(
          flagReason,
          userSuggestion as string | undefined,
        )
      ) {
        throw publicHttpError(404, "Scan is not available for reporting.");
      }

      const target = await resolveLegacyCommunityPostReport(
        scanId,
        user.id,
        supabaseAdmin,
      );
      const post = await fetchReportablePost(
        target.postId,
        user.id,
        supabaseAdmin,
      );
      await upsertExplorePostReport({
        postId: target.postId,
        reporterUserId: user.id,
        postAuthorUserId: post.postAuthorUserId,
        reason: flagReason,
        details: userSuggestion as string,
      }, supabaseAdmin);
    }

    return jsonResponse(
      { success: true, message: "Report submitted for moderation." },
      200,
    );
  })
);
