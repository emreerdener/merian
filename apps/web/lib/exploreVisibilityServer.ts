import "server-only";
import { createAdminSupabaseClient } from "./supabaseAdmin";

let activeChecks = 0;
const CHECK_LIMIT = 32;

export async function publicVisibility(
  ids: string[],
  signal: AbortSignal,
): Promise<{ visible: string[] }> {
  if (activeChecks >= CHECK_LIMIT) throw new Error("Visibility busy");
  activeChecks++;
  try {
    const client = createAdminSupabaseClient();
    if (!client) throw new Error("Visibility unavailable");
    const { data, error } = await client.rpc(
      "get_public_web_explore_visibility",
      { p_post_ids: ids },
    )
      .abortSignal(AbortSignal.any([signal, AbortSignal.timeout(3000)]));
    if (
      error || !Array.isArray(data) ||
      data.some((row) => !ids.includes(row?.post_id))
    ) throw new Error("Visibility unavailable");
    return { visible: data.map((row) => row.post_id) };
  } finally {
    activeChecks--;
  }
}
