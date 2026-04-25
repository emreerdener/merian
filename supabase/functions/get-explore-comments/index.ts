// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { normalizeLimit, normalizeOffset, requireUuid } from "../_shared/explore.ts";
import { fetchExploreComments } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown>;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["post_id"]);
    if (paramErr) return paramErr;

    const postId = requireUuid(body.post_id, "post_id");
    const limit = normalizeLimit(body.limit, 50, 100);
    const offset = normalizeOffset(body.offset);

    const data = await fetchExploreComments(user.id, postId, limit, offset, supabaseAdmin);
    return jsonResponse({ data }, 200);
  }),
);
