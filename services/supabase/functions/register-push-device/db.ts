import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export interface PushDeviceRegistrationInput {
  deviceToken: string;
  platform: "ios";
  environment: "sandbox" | "production";
  exploreEnabled: boolean;
  commentMentionsEnabled: boolean;
  communityIdentificationsEnabled: boolean;
}

export async function upsertPushDeviceRegistration(
  userId: string,
  input: PushDeviceRegistrationInput,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin
    .from("user_push_devices")
    .upsert({
      user_id: userId,
      device_token: input.deviceToken,
      platform: input.platform,
      environment: input.environment,
      explore_enabled: input.exploreEnabled,
      comment_mentions_enabled: input.commentMentionsEnabled,
      community_identifications_enabled: input.communityIdentificationsEnabled,
      is_active: true,
      last_registered_at: new Date().toISOString(),
      last_error_at: null,
      last_error_reason: null,
    }, {
      onConflict: "device_token,platform,environment",
      ignoreDuplicates: false,
    });

  if (error) {
    throw new Error(`Failed to register push device: ${error.message}`);
  }
}
