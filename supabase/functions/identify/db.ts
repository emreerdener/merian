import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { hasTierCached, setTierCache } from "../_shared/tierCache.ts";

export async function upsertGhostUserIfMissing(
  userId: string,
  supabaseAdmin: SupabaseClient,
) {
  if (!hasTierCached(userId)) {
    const { data: existingUser } = await supabaseAdmin
      .from("users")
      .select("subscription_tier")
      .eq("id", userId)
      .maybeSingle();
    if (existingUser) {
      setTierCache(userId, existingUser.subscription_tier as string);
    } else {
      // Ghost user — create the record required for the scans FK constraint.
      await supabaseAdmin
        .from("users")
        .upsert(
          { id: userId, subscription_tier: "free" },
          { onConflict: "id", ignoreDuplicates: true },
        );
      setTierCache(userId, "free");
    }
  }
}
