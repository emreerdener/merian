import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const targetUserId = user.id;
    const { ghost_id } = await req.json();

    if (!ghost_id) {
      return jsonResponse({ error: "Missing 'ghost_id' parameter in payload." }, 400);
    }

    if (ghost_id === targetUserId) {
      return jsonResponse({ message: "No merge required: Session already matches target bounds." }, 200);
    }

    // CRITICAL SEC FIX: Validate the requested ghost_id is actually an Anonymous Ghost User natively before obliterating it.
    // This forcibly prevents IDOR Account Takeover (ATO) strikes stealing and deleting fully authenticated Apple/Google profiles.
    const { data: ghostUser, error: ghostUserError } = await supabaseAdmin.auth.admin.getUserById(ghost_id);
    
    if (ghostUserError || !ghostUser?.user) {
      return jsonResponse({ error: "Ghost user account not found or already merged." }, 404);
    }

    if (!ghostUser.user.is_anonymous) {
      console.error(`IDOR ATO Attempt: User ${targetUserId} attempted to blindly steal fully authenticated account ${ghost_id}`);
      return jsonResponse({ error: "Forbidden: The requested profile is fully authenticated and cannot be hijacked." }, 403);
    }

    // Securely transfer PostgreSQL scans ownership from the Ghost UUID to the newly verified session.user.id
    const { error: scansUpdateError } = await supabaseAdmin
      .from("scans")
      .update({ user_id: targetUserId })
      .eq("user_id", ghost_id);

    if (scansUpdateError) {
      console.error(`Scans ownership update failed for ${ghost_id} to ${targetUserId}`);
      throw new Error(`Migration Failed: ${scansUpdateError.message}`);
    }

    // Eradicate Ghost user identity permanently to prevent abandoned orphaned accounts
    const { error: deleteError } = await supabaseAdmin.auth.admin.deleteUser(ghost_id);

    if (deleteError) {
      console.error(`Erasing Ghost ID ${ghost_id} completely failed natively: ${deleteError.message}`);
    }

    return jsonResponse({ 
      success: true, 
      targetUserId,
      message: "Ghost account securely merged and annihilated."
    }, 200);
  })
);
