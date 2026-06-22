import { jsonResponse, logStructuredError, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { fetchScanOwnership } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await req.json();

    const paramError = requireParams(body, ["scan_id"]);
    if (paramError) return paramError;

    const { scan_id } = body;

    try {
      const exists = await fetchScanOwnership(scan_id, user.id, supabaseAdmin);
      return jsonResponse({ status: exists ? "found" : "not_found" }, 200);
    } catch (error) {
      logStructuredError("check_scan_status_failed", {
        scan_id,
        error: error instanceof Error ? error.message : String(error),
      });
      return jsonResponse({ error: "Internal Server Error" }, 500);
    }
  })
);
