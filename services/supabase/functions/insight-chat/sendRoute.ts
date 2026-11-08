import type { SupabaseClient } from "@supabase/supabase-js";
import {
  boundedStoredJSON,
  exactStoredObject,
  immutableStoredCopy,
  storedUUID,
} from "./storedContextContract.ts";

/** Server authority, not client protocol fields, chooses the send boundary. */
export async function insightChatRequiresContext(
  client: SupabaseClient,
  input: { readonly ownerId: string; readonly scanId: string },
  signal: AbortSignal,
): Promise<boolean> {
  signal.throwIfAborted();
  exactStoredObject(input, ["ownerId", "scanId"]);
  const request = immutableStoredCopy({
    ownerId: storedUUID(input.ownerId),
    scanId: storedUUID(input.scanId),
  });
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    deadline.throwIfAborted();
    const { data, error } = await client.rpc("get_insight_chat_send_route", {
      p_user_id: request.ownerId,
      p_scan_id: request.scanId,
    }).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    if (error) throw new Error();
    boundedStoredJSON(data, 64);
    const row = exactStoredObject(data, ["requires_context"]);
    if (typeof row.requires_context !== "boolean") throw new Error();
    return row.requires_context;
  } catch {
    // Unknown route never permits a mutable legacy send.
    throw new Error("field_chat_context_unavailable");
  }
}
