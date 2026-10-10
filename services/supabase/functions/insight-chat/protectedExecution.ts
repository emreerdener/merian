import type { SupabaseClient } from "@supabase/supabase-js";
import {
  type StoredInsightChatTurnRequest,
  validateStoredTurnRequest,
} from "./storedContext.ts";
import {
  boundedStoredJSON,
  exactStoredObject,
  immutableStoredCopy,
  invalidStoredContext,
  storedObject,
  storedUUID,
} from "./storedContextContract.ts";

function model(value: unknown): "gemini-2.5-flash" {
  if (value !== "gemini-2.5-flash") return invalidStoredContext();
  return value;
}
export function parseProtectedChatQuota(value: unknown) {
  boundedStoredJSON(value, 1024);
  const marker = storedObject(value);
  if (marker.status === "held") {
    exactStoredObject(marker, ["status"]);
    return Object.freeze({ status: "held" as const });
  }
  const row = exactStoredObject(marker, [
    "status",
    "reservation_id",
    "lease_token",
    "lease_expires_at",
    "model",
  ]);
  if (
    row.status !== "reserved" || typeof row.lease_expires_at !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/
      .test(row.lease_expires_at) ||
    !Number.isFinite(Date.parse(row.lease_expires_at))
  ) return invalidStoredContext();
  return Object.freeze({
    status: "reserved" as const,
    reservationId: storedUUID(row.reservation_id),
    leaseToken: storedUUID(row.lease_token),
    leaseExpiresAt: row.lease_expires_at,
    model: model(row.model),
  });
}
export function parseProtectedChatDispatch(value: unknown) {
  boundedStoredJSON(value, 256);
  const marker = storedObject(value);
  if (marker.status === "held") {
    exactStoredObject(marker, ["status"]);
    return Object.freeze({ status: "held" as const });
  }
  const row = exactStoredObject(marker, ["status", "model"]);
  if (row.status !== "dispatch_granted") return invalidStoredContext();
  return Object.freeze({
    status: "dispatch_granted" as const,
    model: model(row.model),
  });
}
/** Unknown responses never prove unused quota or confer permission to dispatch. */
export class ProtectedChatExecutionUnknown extends Error {
  constructor() {
    super("field_chat_execution_held");
    this.name = "ProtectedChatExecutionUnknown";
  }
}
export interface ProtectedChatDispatchRequest {
  readonly ownerId: string;
  readonly scanId: string;
  readonly clientMessageId: string;
  readonly reservationId: string;
  readonly leaseToken: string;
}
/** A fixed, first-attempt-only RPC. This is deliberately not a generic quota capability. */
export async function reserveProtectedChatQuota(
  client: SupabaseClient,
  input: StoredInsightChatTurnRequest,
  ipHash: string,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  const request = validateStoredTurnRequest(input);
  if (!/^[0-9a-f]{64}$/.test(ipHash)) return invalidStoredContext();
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    deadline.throwIfAborted();
    const { data, error } = await client.rpc(
      "reserve_protected_insight_chat_quota",
      {
        p_user_id: request.ownerId,
        p_scan_id: request.scanId,
        p_client_message_id: request.clientMessageId,
        p_message_text: request.messageText,
        p_displayed_ticket: request.displayedTicket,
        p_context_version: 1,
        p_ip_hash: ipHash,
      },
    ).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    if (error) throw new ProtectedChatExecutionUnknown();
    return parseProtectedChatQuota(data);
  } catch {
    throw new ProtectedChatExecutionUnknown();
  }
}
/** Only a fresh, successfully decoded return permits one immediate provider call. Never retry this RPC. */
export async function grantProtectedChatDispatch(
  client: SupabaseClient,
  input: ProtectedChatDispatchRequest,
  signal: AbortSignal,
) {
  signal.throwIfAborted();
  boundedStoredJSON(input, 512);
  exactStoredObject(input, [
    "ownerId",
    "scanId",
    "clientMessageId",
    "reservationId",
    "leaseToken",
  ]);
  Object.values(input).forEach(storedUUID);
  const request = immutableStoredCopy(input);
  const deadline = AbortSignal.any([signal, AbortSignal.timeout(5000)]);
  try {
    deadline.throwIfAborted();
    const { data, error } = await client.rpc(
      "grant_protected_insight_chat_dispatch",
      {
        p_user_id: request.ownerId,
        p_scan_id: request.scanId,
        p_client_message_id: request.clientMessageId,
        p_reservation_id: request.reservationId,
        p_lease_token: request.leaseToken,
      },
    ).retry(false).abortSignal(deadline);
    deadline.throwIfAborted();
    if (error) throw new ProtectedChatExecutionUnknown();
    return parseProtectedChatDispatch(data);
  } catch {
    throw new ProtectedChatExecutionUnknown();
  }
}
