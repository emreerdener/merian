import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { markExploreNotificationsRead } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const marked_count = await markExploreNotificationsRead(user.id, supabaseAdmin);
    return jsonResponse({ success: true, marked_count }, 200);
  }),
);
