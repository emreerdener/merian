import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export async function fetchUnreadExploreNotificationCount(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  const { data, error } = await supabaseAdmin.rpc("get_unread_explore_notification_count", {
    self_id: userId,
  });

  if (error) {
    throw new Error(`Failed to fetch Explore unread notification count: ${error.message}`);
  }

  return Number(data ?? 0);
}
