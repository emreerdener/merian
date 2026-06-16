import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export async function ensureUserExists(
  userId: string,
  supabaseAdmin: SupabaseClient,
) {
  const { error } = await supabaseAdmin
    .from("users")
    .upsert(
      { id: userId, subscription_tier: "free" },
      { onConflict: "id", ignoreDuplicates: true },
    );

  if (error) {
    throw new Error(`Failed to ensure user existence: ${error.message}`);
  }
}

export async function updateUserTier(
  userId: string,
  targetTier: "pro" | "free",
  expiresAt: string | null,
  supabaseAdmin: SupabaseClient,
) {
  const { error } = await supabaseAdmin
    .from("users")
    .update({
      subscription_tier: targetTier,
      subscription_expires_at: expiresAt,
    })
    .eq("id", userId);

  if (error) {
    throw new Error(
      `Failed to set user tier to ${targetTier}: ${error.message}`,
    );
  }
}
