import { parseJsonBody } from "../_shared/http.ts";
import { postReactionCapability } from "../_shared/exploreReactions.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { markExploreNotificationsRead } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "small", allowEmpty: true });
    if (body instanceof Response) return body;
    const marked_count = await markExploreNotificationsRead(
      user.id,
      supabaseAdmin,
      postReactionCapability(body.supports_post_reactions),
    );
    return jsonResponse({ success: true, marked_count }, 200);
  })
);
