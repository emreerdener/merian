// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/validation.ts";

import { insertFlagRecord, markScanAsFlagged } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["scanId", "flagReason"]);
    if (paramErr) return paramErr;
    
    const { scanId, flagReason, userSuggestion } = body;

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
  }),
);
