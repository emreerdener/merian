import { SupabaseClient } from "@supabase/supabase-js";

export interface ExplorePushNotificationPayload {
  notification_id: string;
  recipient_user_id: string;
  post_id: string;
  community_request_id: string | null;
  comment_id: string | null;
  parent_comment_id: string | null;
  type:
    | "like_aggregated"
    | "comment"
    | "comment_reaction"
    | "comment_reply"
    | "comment_mention"
    | "community_identification_added"
    | "community_request_resolved"
    | "community_identification_helped"
    | "media_missing"
    | "media_restored";
  action_count: number;
  reaction_emoji: string | null;
  comment_body: string | null;
  triggering_user_name: string | null;
  recent_actor_names: string[] | null;
  is_reply_to_viewer_comment: boolean | null;
  community_taxon_common_name: string | null;
  community_taxon_scientific_name: string | null;
  community_request_display_name: string | null;
  unread_count?: number | null;
}

export interface PushDeviceRow {
  id: string;
  device_token: string;
  platform: "ios";
  environment: "sandbox" | "production";
  explore_enabled: boolean;
  comment_mentions_enabled: boolean;
  community_identifications_enabled: boolean;
  is_active: boolean;
}

function isCommunityNotificationType(
  notificationType: ExplorePushNotificationPayload["type"],
): boolean {
  return notificationType === "community_identification_added" ||
    notificationType === "community_request_resolved" ||
    notificationType === "community_identification_helped";
}

export async function fetchExplorePushNotificationPayload(
  notificationId: string,
  supabaseAdmin: SupabaseClient,
): Promise<ExplorePushNotificationPayload | null> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_explore_push_notification_payload",
    { target_notification_id: notificationId },
  );

  if (error) {
    throw new Error(`Failed to fetch Explore push payload: ${error.message}`);
  }

  const rows = (data ?? []) as ExplorePushNotificationPayload[];
  return rows[0] ?? null;
}

export async function fetchEligiblePushDevices(
  userId: string,
  notificationType: ExplorePushNotificationPayload["type"],
  supabaseAdmin: SupabaseClient,
): Promise<PushDeviceRow[]> {
  let query = supabaseAdmin
    .from("user_push_devices")
    .select(
      "id, device_token, platform, environment, explore_enabled, comment_mentions_enabled, community_identifications_enabled, is_active",
    )
    .eq("user_id", userId)
    .eq("platform", "ios")
    .eq("is_active", true);

  if (notificationType === "comment_mention") {
    query = query.eq("comment_mentions_enabled", true);
  } else if (isCommunityNotificationType(notificationType)) {
    query = query.eq("community_identifications_enabled", true);
  } else {
    query = query.eq("explore_enabled", true);
  }

  const { data, error } = await query;

  if (error) {
    throw new Error(`Failed to fetch Explore push devices: ${error.message}`);
  }

  return (data ?? []) as PushDeviceRow[];
}

export async function clearPushDeviceDeliveryError(
  deviceId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("user_push_devices")
    .update({
      last_error_at: null,
      last_error_reason: null,
    })
    .eq("id", deviceId);

  if (error) {
    throw new Error(`Failed to clear push delivery error: ${error.message}`);
  }
}

export async function markPushDeviceDeliveryFailure(
  deviceId: string,
  reason: string,
  deactivate: boolean,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("user_push_devices")
    .update({
      is_active: deactivate ? false : true,
      last_error_at: new Date().toISOString(),
      last_error_reason: reason,
    })
    .eq("id", deviceId);

  if (error) {
    throw new Error(
      `Failed to update push delivery error state: ${error.message}`,
    );
  }
}
