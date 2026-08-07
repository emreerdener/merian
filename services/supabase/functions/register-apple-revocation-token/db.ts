import type { SupabaseClient } from "@supabase/supabase-js";

export async function appleRevocationRegistrationExists(
  supabaseAdmin: SupabaseClient,
  userId: string,
  registrationId: string,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin.rpc(
    "apple_revocation_registration_exists",
    {
      p_user_id: userId,
      p_registration_id: registrationId,
    },
  );

  if (error || typeof data !== "boolean") {
    throw new Error("Apple credential registration lookup failed.");
  }
  return data;
}

export async function storeAppleRevocationCredential(
  supabaseAdmin: SupabaseClient,
  input: {
    userId: string;
    registrationId: string;
    appleSubject: string;
    refreshToken: string;
  },
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "store_apple_revocation_credential",
    {
      p_user_id: input.userId,
      p_registration_id: input.registrationId,
      p_apple_subject: input.appleSubject,
      p_refresh_token: input.refreshToken,
    },
  );

  if (error) {
    throw new Error("Apple credential persistence failed.");
  }
}
