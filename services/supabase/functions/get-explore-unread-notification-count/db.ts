import { SupabaseClient } from "@supabase/supabase-js";

export async function fetchUnreadExploreNotificationCount(
  userId: string,
  supabaseAdmin: SupabaseClient,
  supportsPostReactions = false,
): Promise<number> {
  const { data, error } = await supabaseAdmin.rpc(
    supportsPostReactions
      ? "get_unread_explore_notification_count_with_reactions"
      : "get_unread_explore_notification_count",
    {
      self_id: userId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Explore unread notification count: ${error.message}`,
    );
  }

  return Number(data ?? 0);
}
