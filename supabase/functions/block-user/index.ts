import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/validation.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await req.json();
    const paramErr = requireParams(body, ["blocked_id"]);
    if (paramErr) return paramErr;
    const { blocked_id } = body;
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
