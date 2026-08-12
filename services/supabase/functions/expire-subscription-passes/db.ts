import { SupabaseClient } from "@supabase/supabase-js";

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
  const { data, error } = await supabaseAdmin.rpc(
    "refresh_expired_entitlement_projection",
    { p_user_id: userId, p_boundary: boundaryIso },
  );

  if (error) {
    throw new Error(
      `Failed to downgrade expired subscription pass: ${error.message}`,
    );
  }

  if (typeof data !== "boolean") {
    throw new Error(
      "Failed to downgrade expired subscription pass: invalid database response",
    );
  }
  return data;
}
