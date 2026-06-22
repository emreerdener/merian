import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

import { insertFeedbackSurveyResponse } from "./db.ts";
import { parseFeedbackSurveyPayload } from "./validation.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: unknown;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const payload = parseFeedbackSurveyPayload(body);
    await insertFeedbackSurveyResponse(user.id, payload, supabaseAdmin);

    return jsonResponse({ success: true }, 200);
  })
);
