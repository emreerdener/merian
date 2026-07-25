import type { SupabaseClient } from "@supabase/supabase-js";

export async function accountDeletionIsActive(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc(
    "account_deletion_is_active",
    { p_user_id: userId },
  );
  if (error || typeof data !== "boolean") {
    throw new Error("Could not verify the account-deletion upload fence.");
  }
  return data;
}
