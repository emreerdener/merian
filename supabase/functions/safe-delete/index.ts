import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.31.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    // Use SERVICE_ROLE_KEY to bypass RLS and delete the core user profile
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAdmin = createClient(supabaseUrl, supabaseKey);

    // 1. Extract userId from authenticated token in the header
    const token = req.headers.get("Authorization")?.replace("Bearer ", "");
    if (!token) {
      throw new Error("Missing authorization header.");
    }

    // Validate the token to ensure the request is authorized exactly for the user being deleted
    const {
      data: { user },
      error: authError,
    } = await supabaseAdmin.auth.getUser(token);
    if (authError || !user) {
      throw new Error("Invalid or expired authorization token.");
    }
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

    return new Response(
      JSON.stringify({
        message: "Account successfully deleted and tombstoned.",
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
        status: 200,
      },
    );
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 500,
    });
  }
});
