import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    // 2. Delegate R2 wiping to background limits to prevent Deno timeout
    const { error: deletionError } = await supabaseAdmin
      .from("pending_storage_deletions")
      .insert({ target_user_id: user.id, status: "pending" });

    if (deletionError) {
      console.warn(`Could not insert pending deletion log, continuing local wipe: ${deletionError.message}`);
    }

    // 3. PostgreSQL RPC execution securing global Taxonomy Graph
    const { error: rpcError } = await supabaseAdmin.rpc("apply_user_tombstone", {
      target_user_id: user.id,
    });

    if (rpcError) {
      throw new Error(`Failed to apply user tombstone: ${rpcError.message}`);
    }

    // 4. Delete Auth Configuration globally
    const { error: deleteUserError } = await supabaseAdmin.auth.admin.deleteUser(user.id);

    if (deleteUserError) {
      throw new Error(`Failed to delete internal auth profile: ${deleteUserError.message}`);
    }

    return jsonResponse({
      success: true,
      message: "Account successfully deleted and tombstoned.",
    }, 200);
  })
);
