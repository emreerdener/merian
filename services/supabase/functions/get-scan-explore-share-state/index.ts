// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { fetchExploreScanShareState } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["scan_id"]);
    if (paramErr) return paramErr;

    const scanId = requireUuid(body.scan_id, "scan_id");
    const data = await fetchExploreScanShareState(
      user.id,
      scanId,
      supabaseAdmin,
    );

    return jsonResponse({
      data: data ?? {
        scan_id: scanId,
        post_id: null,
        shared_at: null,
        location_sharing: "obscured",
      },
    }, 200);
  })
);
