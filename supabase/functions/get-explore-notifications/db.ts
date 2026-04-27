import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface ExploreNotificationRow {
  notification_id: string;
  post_id: string;
  type: "like_aggregated" | "comment";
  comment_id?: string | null;
  triggering_user_id?: string | null;
  triggering_user_name?: string | null;
  comment_body?: string | null;
  recent_actor_names?: string[] | null;
  action_count: number;
  is_read: boolean;
  created_at: string;
  updated_at: string;
}

export async function fetchExploreNotifications(
  userId: string,
  limit: number,
  offset: number,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreNotificationRow[]> {
  const { data, error } = await supabaseAdmin.rpc("get_explore_notifications", {
    self_id: userId,
    max_limit: limit,
    notification_offset: offset,
  });

  if (error) {
    throw new Error(`Failed to fetch Explore notifications: ${error.message}`);
  }

  return (data ?? []) as ExploreNotificationRow[];
}
