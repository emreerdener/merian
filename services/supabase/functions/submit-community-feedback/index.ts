import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";

import { insertCommunityFeedback } from "./db.ts";
import { parseCommunityFeedbackPayload } from "./validation.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;

    const payload = parseCommunityFeedbackPayload(body);
    await insertCommunityFeedback(user.id, payload, supabaseAdmin);

    return jsonResponse({ success: true }, 200);
  })
);
