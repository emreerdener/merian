import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { requireParams } from "../_shared/validation.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await req.json();
    const paramErr = requireParams(body, ["ghost_id"]);
    if (paramErr) return paramErr;
    const { ghost_id } = body;

    if (ghost_id === user.id) {
      return jsonResponse({ message: "No merge required: ghost_id matches current user." }, 200);
    }

    // Verify the target is an anonymous (guest) account to prevent IDOR account takeover.
    const { data: ghostUser, error: ghostUserError } = await supabaseAdmin.auth.admin.getUserById(ghost_id);

    if (ghostUserError || !ghostUser?.user) {
      return jsonResponse({ error: "Ghost user not found or already merged." }, 404);
    }

    if (!ghostUser.user.is_anonymous) {
      console.warn(`IDOR attempt: User ${user.id} tried to merge authenticated account ${ghost_id}`);
      return jsonResponse({ error: "Forbidden: The target account is not a guest account." }, 403);
    }

    // Transfer scan ownership from the ghost account to the authenticated user
    const { error: scansUpdateError } = await supabaseAdmin
      .from("scans")
      .update({ user_id: user.id })
      .eq("user_id", ghost_id);

    if (scansUpdateError) {
      console.error(`Scans transfer failed from ${ghost_id} to ${user.id}`);
      throw new Error(`Migration failed: ${scansUpdateError.message}`);
    }

    // Delete the guest account after successful transfer
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(ghost_id);

    if (deleteError) {
      console.warn(`Failed to delete ghost user ${ghost_id}: ${deleteError.message}`);
    }

    return jsonResponse({
      success: true,
      targetUserId: user.id,
      message: "Ghost account merged and deleted."
    }, 200);
  })
);
