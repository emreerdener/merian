import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody } from "../_shared/http.ts";

import { insertFeedbackSurveyResponse } from "./db.ts";
import { parseFeedbackSurveyPayload } from "./validation.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "standard" });
    if (body instanceof Response) return body;

    const payload = parseFeedbackSurveyPayload(body);
    await insertFeedbackSurveyResponse(user.id, payload, supabaseAdmin);

    return jsonResponse({ success: true }, 200);
  })
);
