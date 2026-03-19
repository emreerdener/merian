import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { withEdgeHandler, jsonResponse } from "../_shared/edgeHandler.ts";

serve((req: Request) => withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await req.json();
    const { blocked_id } = body;

    if (!blocked_id) {
      throw new Error("Missing blocked_id.");
    }

    const blocker_id = user.id;

    const { error } = await supabaseAdmin
      .from("user_blocks")
      .insert({ blocker_id, blocked_id });

    if (error) {
      throw error;
    }

    return jsonResponse({ success: true });
}));
