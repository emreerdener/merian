// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { normalizeLimit, normalizeOffset } from "../_shared/explore.ts";
import { fetchExploreFeed } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      // Body is optional.
    }

    const limit = normalizeLimit(body.limit, 20, 100);
    const offset = normalizeOffset(body.offset);
    const data = await fetchExploreFeed(user.id, limit, offset, supabaseAdmin);

    return jsonResponse({ data }, 200);
  }),
);
