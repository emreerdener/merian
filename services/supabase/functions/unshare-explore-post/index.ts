import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { ensureOwnedExplorePost, unshareExplorePost } from "./db.ts";

Deno.serve((req: Request) =>
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

    await ensureOwnedExplorePost(postId, user.id, supabaseAdmin);
    await unshareExplorePost(postId, supabaseAdmin);

    return jsonResponse({ success: true, post_id: postId }, 200);
  }),
);
