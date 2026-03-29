import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { queueStorageDeletion, applyUserTombstone, deleteAuthProfile } from "./db.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    
    // 1. Queue R2 storage deletion in the background to avoid timeout
    await queueStorageDeletion(user.id, supabaseAdmin);

    // 2. Apply user tombstone via RPC
    await applyUserTombstone(user.id, supabaseAdmin);

    // 3. Delete auth profile
    await deleteAuthProfile(user.id, supabaseAdmin);

    return jsonResponse(
      {
        success: true,
        message: "Account securely deleted and anonymized.",
      },
      200,
    );
  }),
);
