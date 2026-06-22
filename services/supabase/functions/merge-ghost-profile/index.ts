import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { syncPublicAuthorIdentity } from "../_shared/explore.ts";
import { requireParams } from "../_shared/http.ts";
import {
  purgeGhostUser,
  transferCommunityRequests,
  transferCollections,
  transferExplorePosts,
  transferScans,
  transferUserFollows,
  verifyGhostUser,
} from "./db.ts";

Deno.serve((req: Request) =>
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

    const ghostId = ghost_id.toLowerCase();
    const targetUserId = user.id.toLowerCase();

    // Redundant client-side fire trap
    if (ghostId === targetUserId) {
      await syncPublicAuthorIdentity(targetUserId, supabaseAdmin);
      return jsonResponse(
        {
          success: true,
          targetUserId,
          message: "No merge required: current user identity refreshed.",
        },
        200,
      );
    }

    // 1. Verify Target Identity
    const verificationErrorResponse = await verifyGhostUser(
      ghostId,
      targetUserId,
      supabaseAdmin,
    );
    if (verificationErrorResponse) return verificationErrorResponse;

    // 2. Safely Execute Transfer
    await transferScans(ghostId, targetUserId, supabaseAdmin);
    await transferCollections(ghostId, targetUserId, supabaseAdmin);
    await transferExplorePosts(ghostId, targetUserId, supabaseAdmin);
    await transferCommunityRequests(ghostId, targetUserId, supabaseAdmin);
    await transferUserFollows(ghostId, targetUserId, supabaseAdmin);
    await syncPublicAuthorIdentity(targetUserId, supabaseAdmin);

    // 3. Purge Empty Ghost Profile
    await purgeGhostUser(ghostId, supabaseAdmin);

    return jsonResponse(
      {
        success: true,
        targetUserId,
        message: "Ghost account securely merged and structurally deleted.",
      },
      200,
    );
  })
);
