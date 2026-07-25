import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { fetchUnreadExploreNotificationCount } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const unread_count = await fetchUnreadExploreNotificationCount(
      user.id,
      supabaseAdmin,
    );
    return jsonResponse({ unread_count }, 200);
  })
);
