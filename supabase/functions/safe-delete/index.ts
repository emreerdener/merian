import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    // 1. Queue R2 storage deletion in the background to avoid timeout
    const { error: deletionError } = await supabaseAdmin
      .from("pending_storage_deletions")
      .insert({ target_user_id: user.id, status: "pending" });

    if (deletionError) {
      console.warn(`Could not insert pending deletion record, continuing: ${deletionError.message}`);
    }

    // 2. Apply user tombstone via RPC
    const { error: rpcError } = await supabaseAdmin.rpc("apply_user_tombstone", {
      target_user_id: user.id,
    });

    if (rpcError) {
      throw new Error(`Failed to apply user tombstone: ${rpcError.message}`);
    }

    // 3. Delete auth profile
    const { error: deleteUserError } = await supabaseAdmin.auth.admin.deleteUser(user.id);

    if (deleteUserError) {
      throw new Error(`Failed to delete auth profile: ${deleteUserError.message}`);
    }

    return jsonResponse({
      success: true,
      message: "Account successfully deleted.",
    }, 200);
  })
);
