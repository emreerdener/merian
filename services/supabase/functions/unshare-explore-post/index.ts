import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { ensureOwnedExplorePost, unshareExplorePost } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;

    const paramErr = requireParams(body, ["post_id"]);
    if (paramErr) return paramErr;

    const postId = requireUuid(body.post_id, "post_id");

    await ensureOwnedExplorePost(postId, user.id, supabaseAdmin);
    await unshareExplorePost(postId, supabaseAdmin);

    return jsonResponse({ success: true, post_id: postId }, 200);
  })
);
