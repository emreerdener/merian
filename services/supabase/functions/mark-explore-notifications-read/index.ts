// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { markExploreNotificationsRead } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const marked_count = await markExploreNotificationsRead(user.id, supabaseAdmin);
    return jsonResponse({ success: true, marked_count }, 200);
  }),
);
