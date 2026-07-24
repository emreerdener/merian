import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { insertUserBlock } from "./db.ts";

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, { limit: "small" });
    if (body instanceof Response) return body;

    const paramErr = requireParams(body, ["blocked_id"]);
    if (paramErr) return paramErr;

    const { blocked_id } = body;

    const UUID_RE =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (typeof blocked_id !== "string" || !UUID_RE.test(blocked_id)) {
      return jsonResponse({ error: "blocked_id must be a valid UUID." }, 400);
    }

    // Defend against self-blocking
    if (blocked_id === user.id) {
      return jsonResponse(
        { error: "Bad Request: You cannot block yourself." },
        400,
      );
    }

    await insertUserBlock(user.id, blocked_id, supabaseAdmin);

    return jsonResponse({
      success: true,
      message: "User successfully blocked.",
    });
  })
);
