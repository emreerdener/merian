import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireUuid } from "../_shared/explore.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireReportableUser, upsertUserReport } from "./db.ts";

const REASONS = new Set([
  "Spam",
  "Harassment",
  "Impersonation",
  "Inappropriate profile",
  "Other",
]);

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;
    const paramError = requireParams(body, ["reported_user_id", "reason"]);
    if (paramError) return paramError;
    const reportedUserId = requireUuid(
      body.reported_user_id,
      "reported_user_id",
    );
    const reason = typeof body.reason === "string" ? body.reason.trim() : "";
    if (!REASONS.has(reason)) {
      return jsonResponse({ error: "Invalid report reason." }, 400);
    }

    const details = typeof body.details === "string"
      ? body.details.trim()
      : null;
    if (details && details.length > 1000) {
      return jsonResponse(
        { error: "Report details must be 1,000 characters or fewer." },
        400,
      );
    }

    await requireReportableUser(user.id, reportedUserId, supabaseAdmin);
    await upsertUserReport({
      reporterUserId: user.id,
      reportedUserId,
      reason,
      details: details || null,
    }, supabaseAdmin);

    return jsonResponse({
      success: true,
      reported_user_id: reportedUserId,
      message: "Report submitted for moderation.",
    }, 200);
  })
);
