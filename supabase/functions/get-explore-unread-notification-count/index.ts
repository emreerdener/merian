// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { fetchUnreadExploreNotificationCount } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const unread_count = await fetchUnreadExploreNotificationCount(user.id, supabaseAdmin);
    return jsonResponse({ unread_count }, 200);
  }),
);
