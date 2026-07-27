import {
  fetchWithDeadline,
  OutboundRequestTimeoutError,
  readResponseTextWithinLimit,
} from "../_shared/outbound.ts";
import type { PushDeviceRow } from "./db.ts";

export interface NotificationCopy {
  title: string;
  body: string;
}

export interface ApnsFailure {
  status: number;
  reason: string;
}

const APNS_REQUEST_TIMEOUT_MS = 10_000;
const APNS_ERROR_RESPONSE_LIMIT_BYTES = 4 * 1024;

function apnsHost(environment: PushDeviceRow["environment"]): string {
  return environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
}

function normalizedBadgeCount(count: number | null | undefined): number {
  return typeof count === "number" && Number.isFinite(count)
    ? Math.max(0, Math.trunc(count))
    : 1;
}

export function apnsDeliveryExceptionReason(error: unknown): string {
  if (error instanceof OutboundRequestTimeoutError) {
    return "RequestTimeout";
  }
  if (error instanceof TypeError || error instanceof DOMException) {
    return "NetworkError";
  }
  return "DeliveryException";
}

export async function sendApnsPush(
  device: PushDeviceRow,
  copy: NotificationCopy,
  bearerToken: string,
  apnsTopic: string,
  notificationId: string,
  postId: string,
  communityRequestId: string | null,
  commentId: string | null,
  parentCommentId: string | null,
  notificationType: string,
  badgeCount: number | null | undefined,
  fetcher: typeof fetch = fetch,
): Promise<ApnsFailure | null> {
  const response = await fetchWithDeadline(
    `${apnsHost(device.environment)}/3/device/${device.device_token}`,
    {
      method: "POST",
      headers: {
        "authorization": `bearer ${bearerToken}`,
        "apns-collapse-id": notificationId,
        "apns-priority": "10",
        "apns-push-type": "alert",
        "apns-topic": apnsTopic,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        aps: {
          alert: copy,
          badge: normalizedBadgeCount(badgeCount),
          sound: "default",
          "thread-id": "explore_activity",
        },
        type: "explore_activity",
        postId,
        communityRequestId,
        commentId,
        parentCommentId,
        notificationId,
        notificationType,
      }),
    },
    {
      fetcher,
      timeoutMs: APNS_REQUEST_TIMEOUT_MS,
    },
  );

  if (response.ok) {
    await response.body?.cancel().catch(() => undefined);
    return null;
  }

  let reason = `HTTP_${response.status}`;
  try {
    const rawBody = await readResponseTextWithinLimit(
      response,
      APNS_ERROR_RESPONSE_LIMIT_BYTES,
    );
    const body = JSON.parse(rawBody) as { reason?: unknown };
    if (
      typeof body.reason === "string" &&
      /^[A-Za-z][A-Za-z0-9_]{0,127}$/.test(body.reason)
    ) {
      reason = body.reason;
    }
  } catch {
    // Keep the stable HTTP reason when APNs returns malformed or oversized
    // diagnostic data.
  }

  return {
    status: response.status,
    reason,
  };
}
