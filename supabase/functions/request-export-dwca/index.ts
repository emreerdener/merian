// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { hasRecentExportJob, queueExportJob } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let requestBody;
    try {
      requestBody = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const { includePreciseCoordinates = false, exportScope = "user" } =
      requestBody;
    const userId = user.id;

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

    // 2. Queue the Export for the Heavy Worker Webhook
    await queueExportJob(
      userId,
      exportScope,
      includePreciseCoordinates,
      supabaseAdmin,
    );

    return jsonResponse(
      { success: true, message: "Export job queued successfully." },
      200,
    );
  }),
);
