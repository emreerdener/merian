import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import { verifyGhostUser, transferScans, purgeGhostUser } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const paramErr = requireParams(body, ["ghost_id"]);
    if (paramErr) return paramErr;
    
    const { ghost_id } = body;

    // Redundant client-side fire trap
    if (ghost_id === user.id) {
      return jsonResponse(
        { message: "No merge required: ghost_id matches current user." },
        200,
      );
    }

    // 1. Verify Target Identity
    const verificationErrorResponse = await verifyGhostUser(
      ghost_id,
      user.id,
      supabaseAdmin,
    );
    if (verificationErrorResponse) return verificationErrorResponse;

    // 2. Safely Execute Transfer
    await transferScans(ghost_id, user.id, supabaseAdmin);

    // 3. Purge Empty Ghost Profile
    await purgeGhostUser(ghost_id, supabaseAdmin);

    return jsonResponse(
      {
        success: true,
        targetUserId: user.id,
        message: "Ghost account securely merged and structurally deleted.",
      },
      200,
    );
  }),
);
