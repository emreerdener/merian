import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { fetchExploreComposerMedia } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const scanId = body.scan_id == null
      ? undefined
      : requireUuid(body.scan_id, "scan_id");
    const postId = body.post_id == null
      ? undefined
      : requireUuid(body.post_id, "post_id");

    if (!scanId && !postId) {
      return jsonResponse({ error: "scan_id or post_id is required." }, 400);
    }

    const data = await fetchExploreComposerMedia(
      user.id,
      { scanId, postId },
      supabaseAdmin,
    );

    return jsonResponse({ data });
  })
);
