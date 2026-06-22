import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { hasRecentExportJob, queueExportJob } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let requestBody;
    try {
      requestBody = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const { includePreciseCoordinates = false, exportScope = "personal" } =
      requestBody;
    const userId = user.id;

    const VALID_EXPORT_SCOPES = new Set(["personal", "global"]);
    if (!VALID_EXPORT_SCOPES.has(exportScope)) {
      return jsonResponse(
        { error: `Invalid exportScope. Must be one of: ${[...VALID_EXPORT_SCOPES].join(", ")}.` },
        400,
      );
    }

    if (typeof includePreciseCoordinates !== "boolean") {
      return jsonResponse(
        { error: "includePreciseCoordinates must be a boolean." },
        400,
      );
    }

    // 1. Rate Limit: Ensure only 1 export per 24 hours
    const hasLimiterHit = await hasRecentExportJob(userId, supabaseAdmin);

    if (hasLimiterHit) {
      return jsonResponse(
        {
          error: "Rate Limit Exceeded",
          message: "You can only request one DwC-A export every 24 hours.",
        },
        429,
      );
    }

    // 2. Queue the Export for the Heavy Worker Webhook.
    // queueExportJob returns false when a concurrent request already inserted a pending
    // job (TOCTOU race — both requests passed the rate-limit SELECT before either INSERT).
    const queued = await queueExportJob(
      userId,
      exportScope,
      includePreciseCoordinates,
      supabaseAdmin,
    );

    if (!queued) {
      return jsonResponse(
        {
          error: "Rate Limit Exceeded",
          message: "An export job is already pending for your account.",
        },
        429,
      );
    }

    return jsonResponse(
      { success: true, message: "Export job queued successfully." },
      200,
    );
  }),
);
