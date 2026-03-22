import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) => 
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await req.json();
    const { blocked_id } = body;

    if (!blocked_id) {
      throw new Error("Missing 'blocked_id' parameter in payload.");
    }

    // Register the block across the edge securely.
    // If a collision occurs, withEdgeHandler safely intercepts the error boundary.
    const { error } = await supabaseAdmin
      .from("user_blocks")
      .insert({ 
        blocker_id: user.id, 
        blocked_id 
      });

    if (error) throw error;

    return jsonResponse({ 
      success: true, 
      message: "User successfully blocked." 
    });
  })
);
