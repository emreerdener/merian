import { serve } from "@std/http/server.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { withEdgeHandler } from "../_shared/edgeHandler.ts";

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

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
}));
