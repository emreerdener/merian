// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/validation.ts";
import { insertUserBlock } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["blocked_id"]);
    if (paramErr) return paramErr;
    
    const { blocked_id } = body;

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
  }),
);
