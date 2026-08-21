import type { SupabaseClient } from "@supabase/supabase-js";

const FIELD_CHAT_MESSAGE_TABLES = [
  "insight_chat_messages",
  "explore_post_chat_messages",
  "species_dictionary_chat_messages",
] as const;

async function countTableSendsToday(
  table: (typeof FIELD_CHAT_MESSAGE_TABLES)[number],
  userId: string,
  start: string,
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  const { count, error } = await supabaseAdmin
    .from(table)
    .select("id", { count: "exact", head: true })
    .eq("user_id", userId)
    .eq("role", "user")
    .gte("created_at", start);
  if (error) {
    throw new Error(`Failed to count Field Chat sends: ${error.message}`);
  }
  return count ?? 0;
}

export async function countAllFieldChatSendsToday(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<number> {
  const start = new Date();
  start.setUTCHours(0, 0, 0, 0);
  const counts = await Promise.all(
    FIELD_CHAT_MESSAGE_TABLES.map((table) =>
      countTableSendsToday(
        table,
        userId,
        start.toISOString(),
        supabaseAdmin,
      )
    ),
  );
  return counts.reduce((total, count) => total + count, 0);
}
