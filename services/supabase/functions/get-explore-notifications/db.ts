import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface ExploreNotificationRow {
  notification_id: string;
  post_id?: string | null;
  community_request_id?: string | null;
  type:
    | "like_aggregated"
    | "comment"
    | "comment_reaction"
    | "comment_reply"
    | "comment_mention"
    | "follow"
    | "community_identification_added"
    | "community_request_resolved"
    | "community_identification_helped";
  comment_id?: string | null;
  parent_comment_id?: string | null;
  reaction_emoji?: string | null;
  triggering_user_id?: string | null;
  triggering_user_name?: string | null;
  comment_body?: string | null;
  recent_actor_names?: string[] | null;
  action_count: number;
  is_read: boolean;
  is_reply_to_viewer_comment?: boolean | null;
  community_taxon_common_name?: string | null;
  community_taxon_scientific_name?: string | null;
  community_request_display_name?: string | null;
  created_at: string;
  updated_at: string;
}

interface ExploreNotificationsCursor {
  beforeUpdatedAt: string | null;
  beforeNotificationId: string | null;
}

export async function fetchExploreNotifications(
  userId: string,
  limit: number,
  cursor: ExploreNotificationsCursor,
  supabaseAdmin: SupabaseClient,
): Promise<ExploreNotificationRow[]> {
  const { data, error } = await supabaseAdmin.rpc("get_explore_notifications", {
    self_id: userId,
    max_limit: limit,
    before_updated_at: cursor.beforeUpdatedAt,
    before_notification_id: cursor.beforeNotificationId,
  });

  if (error) {
    throw new Error(`Failed to fetch Explore notifications: ${error.message}`);
  }

  return (data ?? []) as ExploreNotificationRow[];
}
