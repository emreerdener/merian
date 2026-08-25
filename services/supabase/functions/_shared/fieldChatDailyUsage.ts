import type { SupabaseClient } from "@supabase/supabase-js";
import { publicHttpError } from "./http.ts";

function usageUnavailable() {
  return publicHttpError(
    503,
    "Field Chat admission accounting is temporarily unavailable.",
    "field_chat_admission_unavailable",
    2,
  );
}

export async function countAllFieldChatSendsToday(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  let result: {
    data: unknown;
    error: { message: string } | null;
  };
  try {
    result = await supabaseAdmin.rpc("get_field_chat_daily_usage", {
      p_user_id: userId,
    }).abortSignal(AbortSignal.timeout(5_000));
  } catch {
    throw usageUnavailable();
  }

  if (
    result.error ||
    !Number.isSafeInteger(result.data) ||
    (result.data as number) < 0
  ) {
    throw usageUnavailable();
  }
  return result.data as number;
}
