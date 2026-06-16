import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface ExpiredSubscriptionPassUser {
  id: string;
}

export async function fetchExpiredSubscriptionPassUsers(
  boundaryIso: string,
  supabaseAdmin: SupabaseClient,
  limit = 100,
): Promise<ExpiredSubscriptionPassUser[]> {
  const { data, error } = await supabaseAdmin
    .from("users")
    .select("id")
    .eq("subscription_tier", "pro")
    .not("subscription_expires_at", "is", null)
    .lte("subscription_expires_at", boundaryIso)
    .order("subscription_expires_at", { ascending: true })
    .limit(limit);

  if (error) {
    throw new Error(
      `Failed to fetch expired subscription passes: ${error.message}`,
    );
  }

  return (data ?? []) as ExpiredSubscriptionPassUser[];
}

export async function downgradeExpiredSubscriptionPass(
  userId: string,
  boundaryIso: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from("users")
    .update({
      subscription_tier: "free",
      subscription_expires_at: null,
    })
    .eq("id", userId)
    .eq("subscription_tier", "pro")
    .not("subscription_expires_at", "is", null)
    .lte("subscription_expires_at", boundaryIso)
    .select("id");

  if (error) {
    throw new Error(
      `Failed to downgrade expired subscription pass: ${error.message}`,
    );
  }

  return (data ?? []).length > 0;
}
