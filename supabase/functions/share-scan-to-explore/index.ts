// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { requireUuid, syncPublicAuthorIdentity } from "../_shared/explore.ts";
import { fetchShareEligibleScan, upsertExplorePost } from "./db.ts";

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

    await fetchShareEligibleScan(scanId, user.id, supabaseAdmin);
    await syncPublicAuthorIdentity(user.id, supabaseAdmin);
    const post = await upsertExplorePost(scanId, user.id, supabaseAdmin);

    return jsonResponse({
      success: true,
      post_id: post.id,
      scan_id: scanId,
      shared_at: post.shared_at,
    });
  }),
);
