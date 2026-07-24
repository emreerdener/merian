import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { fetchExploreScanShareState } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;

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
        community_request_id: null,
        community_request_status: null,
        is_explore_feed_visible: false,
        location_sharing: "obscured",
      },
    }, 200);
  })
);
