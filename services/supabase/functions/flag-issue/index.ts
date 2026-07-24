import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";

import { insertFlagRecord, markScanAsFlagged } from "./db.ts";

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

    // 1. Insert a moderation queue record
    await insertFlagRecord(
      scanId,
      user.id,
      flagReason,
      userSuggestion,
      supabaseAdmin,
    );

    // 2. Mark the scan as flagged natively
    await markScanAsFlagged(
      scanId,
      flagReason,
      userSuggestion,
      supabaseAdmin,
    );

    return jsonResponse(
      { success: true, message: "Report submitted for moderation." },
      200,
    );
  })
);
