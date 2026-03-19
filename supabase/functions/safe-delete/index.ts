import { serve } from "@std/http/server.ts";
import { createClient } from "@supabase/supabase-js";

import { requireAuth } from "../_shared/auth.ts";
import { corsHeaders } from "../_shared/cors.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
// Use SERVICE_ROLE_KEY to bypass RLS and delete the core user profile
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user, response } = await requireAuth(req, supabaseAdmin);
    if (response) return response;

    const userId = user!.id;

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

    return new Response(
      JSON.stringify({
        message: "Account successfully deleted and tombstoned.",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
