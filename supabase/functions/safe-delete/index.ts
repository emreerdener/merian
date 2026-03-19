import { serve } from "@std/http/server.ts";
import { withEdgeHandler, jsonResponse } from "../_shared/edgeHandler.ts";

serve((req: Request) => withEdgeHandler(req, async (user, supabaseAdmin) => {
    const userId = user.id;

    // 2. Delegate R2 wiping to background limits to prevent Deno timeout
    const { error: deletionError } = await supabaseAdmin
      .from("pending_storage_deletions")
      .insert({ target_user_id: userId, status: "pending" });

    if (deletionError) {
      console.warn(
        "Could not insert pending deletion log, continuing local wipe:",
        deletionError.message,
      );
    }

    // 3. PostgreSQL RPC execution securing global Taxonomy Graph
    const { error: rpcError } = await supabaseAdmin.rpc(
      "apply_user_tombstone",
      {
        target_user_id: userId,
      },
    );

    if (rpcError) {
      throw new Error(`Failed to apply user tombstone: ${rpcError.message}`);
    }

    // 4. Delete Auth Configuration globally
    const { error: deleteUserError } =
      await supabaseAdmin.auth.admin.deleteUser(userId);

    if (deleteUserError) {
      throw new Error(
        `Failed to delete internal auth profile: ${deleteUserError.message}`,
      );
    }

    return jsonResponse({
        message: "Account successfully deleted and tombstoned.",
      });
}));
