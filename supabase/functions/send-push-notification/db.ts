import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface ExplorePushNotificationPayload {
  notification_id: string;
  recipient_user_id: string;
  post_id: string;
  type: "like_aggregated" | "comment" | "comment_reaction";
  action_count: number;
  reaction_emoji: string | null;
  comment_body: string | null;
  triggering_user_name: string | null;
  recent_actor_names: string[] | null;
}

export interface PushDeviceRow {
  id: string;
  device_token: string;
  platform: "ios";
  environment: "sandbox" | "production";
  explore_enabled: boolean;
  is_active: boolean;
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
  supabaseAdmin: SupabaseClient,
): Promise<PushDeviceRow[]> {
  const { data, error } = await supabaseAdmin
    .from("user_push_devices")
    .select("id, device_token, platform, environment, explore_enabled, is_active")
    .eq("user_id", userId)
    .eq("platform", "ios")
    .eq("explore_enabled", true)
    .eq("is_active", true);

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
    throw new Error(`Failed to update push delivery error state: ${error.message}`);
  }
}
