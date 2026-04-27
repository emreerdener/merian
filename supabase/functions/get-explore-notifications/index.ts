// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import { normalizeLimit, normalizeOffset } from "../_shared/explore.ts";
import { fetchExploreNotifications } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      // Body is optional.
    }

    const limit = normalizeLimit(body.limit, 50, 100);
    const offset = normalizeOffset(body.offset);
    let data;
    try {
      data = await fetchExploreNotifications(user.id, limit, offset, supabaseAdmin);
    } catch (error) {
      logStructuredError("explore_notifications_fetch_failed", {
        user_id: user.id,
        limit,
        offset,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }

    return jsonResponse({ data }, 200);
  }),
);
