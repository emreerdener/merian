import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/http.ts";
import {
  purgeGhostUser,
  transferCollections,
  transferExplorePosts,
  transferScans,
  transferUserFollows,
  verifyGhostUser,
} from "./db.ts";

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

    const UUID_RE =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (typeof ghost_id !== "string" || !UUID_RE.test(ghost_id)) {
      return jsonResponse({ error: "ghost_id must be a valid UUID." }, 400);
    }

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
    await transferCollections(ghost_id, user.id, supabaseAdmin);
    await transferExplorePosts(ghost_id, user.id, supabaseAdmin);
    await transferUserFollows(ghost_id, user.id, supabaseAdmin);

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
  })
);
