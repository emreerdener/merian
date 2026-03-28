import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const { includePreciseCoordinates = false, exportScope = "user" } = await req.json();
    const userId = user.id;

    // 1. Rate Limit: Ensure only 1 export per 24 hours
    const { data: recentJobs, error: selectError } = await supabaseAdmin
      .from("export_jobs")
      .select("created_at")
      .eq("user_id", userId)
      .gte("created_at", new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString())
      .limit(1);

    if (selectError) {
      throw new Error(`Failed to verify rate limit: ${selectError.message}`);
    }

    if (recentJobs && recentJobs.length > 0) {
      return jsonResponse(
        { error: "Rate Limit Exceeded", message: "You can only request one DwC-A export every 24 hours." },
        429
      );
    }

    // 2. Queue the Export
    const { error } = await supabaseAdmin
      .from("export_jobs")
      .insert({
        user_id: userId,
        export_scope: exportScope,
        include_precise_coordinates: includePreciseCoordinates,
        status: "pending",
      });

    if (error) {
      throw new Error(`Failed to queue export job: ${error.message}`);
    }

    return jsonResponse({ success: true, message: "Export job queued successfully." }, 200);
  })
);
