import { SupabaseClient } from "@supabase/supabase-js";

export async function markExploreNotificationsRead(
  userId: string,
  supabaseAdmin: SupabaseClient,
  supportsPostReactions = false,
): Promise<number> {
  const { data, error } = await supabaseAdmin.rpc(
    supportsPostReactions
      ? "mark_explore_notifications_read_with_reactions"
      : "mark_explore_notifications_read",
    {
      self_id: userId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to mark Explore notifications read: ${error.message}`,
    );
  }

  return Number(data ?? 0);
}
