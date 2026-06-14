// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import { importPKCS8, SignJWT } from "https://esm.sh/jose@5.9.6";
import { mapWithConcurrencyLimit } from "../_shared/concurrency.ts";
import { logStructuredError } from "../_shared/edgeHandler.ts";
import { requireUuid } from "../_shared/explore.ts";
import { corsHeaders, jsonResponse, requireParams, timingSafeCompare } from "../_shared/http.ts";
import {
  clearPushDeviceDeliveryError,
  ExplorePushNotificationPayload,
  fetchEligiblePushDevices,
  fetchExplorePushNotificationPayload,
  markPushDeviceDeliveryFailure,
  PushDeviceRow,
} from "./db.ts";

type ApnsEnvironment = "sandbox" | "production";

interface NotificationCopy {
  title: string;
  body: string;
}

interface ApnsFailure {
  status: number;
  reason: string;
}

const APNS_DELIVERY_CONCURRENCY = 8;
let cachedApnsBearerToken: { token: string; expiresAtMs: number } | null = null;

function normalizePrivateKey(rawValue: string): string {
  return rawValue.replace(/\\n/g, "\n").trim();
}

function apnsHost(environment: ApnsEnvironment): string {
  return environment === "sandbox"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
}

function buildLikeTitle(actorNames: string[], actionCount: number): string {
  const safeCount = Math.max(actionCount, actorNames.length);
  if (actorNames.length >= 2 && safeCount > 2) {
    return `${actorNames[0]}, ${actorNames[1]}, and ${safeCount - 2} others liked your post`;
  }
  if (actorNames.length >= 2) {
    return `${actorNames[0]} and ${actorNames[1]} liked your post`;
  }
  if (actorNames.length == 1 && safeCount > 1) {
    return `${actorNames[0]} and ${safeCount - 1} others liked your post`;
  }
  return `${actorNames[0] ?? "Someone"} liked your post`;
}

function buildCommentReactionTitle(
  actorNames: string[],
  actionCount: number,
  reactionEmoji: string | null,
): string {
  const safeCount = Math.max(actionCount, actorNames.length);
  const trimmedEmoji = reactionEmoji?.trim();
  const actionSuffix = trimmedEmoji && trimmedEmoji.length > 0
    ? `reacted ${trimmedEmoji} to your comment`
    : "reacted to your comment";

  if (actorNames.length >= 2 && safeCount > 2) {
    return `${actorNames[0]}, ${actorNames[1]}, and ${safeCount - 2} others ${actionSuffix}`;
  }
  if (actorNames.length >= 2) {
    return `${actorNames[0]} and ${actorNames[1]} ${actionSuffix}`;
  }
  if (actorNames.length == 1 && safeCount > 1) {
    return `${actorNames[0]} and ${safeCount - 1} others ${actionSuffix}`;
  }
  return `${actorNames[0] ?? "Someone"} ${actionSuffix}`;
}

function buildCommentBody(commentBody: string | null): string {
  const trimmed = (commentBody ?? "").trim();
  if (trimmed.length <= 120) return trimmed || "Open Explore to view the conversation.";
  return `${trimmed.slice(0, 117)}...`;
}

function buildNotificationCopy(
  payload: ExplorePushNotificationPayload,
): NotificationCopy {
  if (payload.type === "comment") {
    const actorName = typeof payload.triggering_user_name === "string" && payload.triggering_user_name.length > 0
      ? payload.triggering_user_name
      : "Someone";
    return {
      title: `${actorName} commented on your post`,
      body: buildCommentBody(payload.comment_body),
    };
  }

  if (payload.type === "comment_reply") {
    const actorName = typeof payload.triggering_user_name === "string" && payload.triggering_user_name.length > 0
      ? payload.triggering_user_name
      : "Someone";
    return {
      title: payload.is_reply_to_viewer_comment
        ? `${actorName} replied to your comment`
        : `${actorName} replied on your post`,
      body: buildCommentBody(payload.comment_body),
    };
  }

  const actorNames = payload.recent_actor_names?.filter((value): value is string => value.length > 0) ?? [];

  if (payload.type === "comment_reaction") {
    return {
      title: buildCommentReactionTitle(actorNames, payload.action_count, payload.reaction_emoji),
      body: buildCommentBody(payload.comment_body),
    };
  }

  return {
    title: buildLikeTitle(actorNames, payload.action_count),
    body: "Open Explore to see the activity on your post.",
  };
}

function isTerminalApnsReason(reason: string): boolean {
  return [
    "BadDeviceToken",
    "DeviceTokenNotForTopic",
    "Unregistered",
  ].includes(reason);
}

function normalizedBadgeCount(count: number | null | undefined): number {
  return typeof count === "number" && Number.isFinite(count)
    ? Math.max(0, Math.trunc(count))
    : 1;
}

async function getApnsBearerToken(): Promise<string | null> {
  const now = Date.now();
  if (cachedApnsBearerToken && cachedApnsBearerToken.expiresAtMs - now > 5 * 60 * 1000) {
    return cachedApnsBearerToken.token;
  }

  const teamId = Deno.env.get("APNS_TEAM_ID");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");

  if (!teamId || !keyId || !privateKey) {
    return null;
  }

  const importedKey = await importPKCS8(normalizePrivateKey(privateKey), "ES256");
  const issuedAtSeconds = Math.floor(now / 1000);
  const token = await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: keyId })
    .setIssuer(teamId)
    .setIssuedAt(issuedAtSeconds)
    .setExpirationTime(issuedAtSeconds + 60 * 60)
    .sign(importedKey);

  cachedApnsBearerToken = {
    token,
    expiresAtMs: now + 55 * 60 * 1000,
  };

  return token;
}

async function sendApnsPush(
  device: PushDeviceRow,
  copy: NotificationCopy,
  bearerToken: string,
  apnsTopic: string,
  notificationId: string,
  postId: string,
  commentId: string | null,
  parentCommentId: string | null,
  notificationType: string,
  badgeCount: number | null | undefined,
): Promise<ApnsFailure | null> {
  const response = await fetch(`${apnsHost(device.environment)}/3/device/${device.device_token}`, {
    method: "POST",
    headers: {
      "authorization": `bearer ${bearerToken}`,
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
      commentId,
      parentCommentId,
      notificationId,
      notificationType,
    }),
  });

  if (response.ok) {
    return null;
  }

  let reason = `HTTP_${response.status}`;
  try {
    const body = await response.json() as { reason?: string };
    if (typeof body.reason === "string" && body.reason.length > 0) {
      reason = body.reason;
    }
  } catch {
    // Keep the default reason when APNs does not return JSON.
  }

  return {
    status: response.status,
    reason,
  };
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const expectedAuth = `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`;
  const providedAuth = req.headers.get("Authorization") ?? "";
  if (!timingSafeCompare(providedAuth, expectedAuth)) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const paramErr = requireParams(body, ["notification_id"]);
  if (paramErr) return paramErr;

  const notificationId = requireUuid(body.notification_id, "notification_id");
  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  const payload = await fetchExplorePushNotificationPayload(notificationId, supabaseAdmin);
  if (!payload) {
    return jsonResponse({ success: true, skipped: "notification_not_visible" }, 200);
  }

  const bearerToken = await getApnsBearerToken();
  const apnsTopic = Deno.env.get("APNS_TOPIC");
  if (!bearerToken || !apnsTopic) {
    logStructuredError("explore_push_configuration_missing", {
      notification_id: payload.notification_id,
      post_id: payload.post_id,
    });
    return jsonResponse({ success: true, skipped: "apns_not_configured" }, 200);
  }

  const devices = await fetchEligiblePushDevices(payload.recipient_user_id, supabaseAdmin);
  if (devices.length === 0) {
    return jsonResponse({ success: true, delivered: 0, skipped: "no_eligible_devices" }, 200);
  }

  const copy = buildNotificationCopy(payload);
  let delivered = 0;
  const failures: Array<{ deviceId: string; reason: string; status: number }> = [];

  await mapWithConcurrencyLimit(devices, APNS_DELIVERY_CONCURRENCY, async (device) => {
    try {
      const failure = await sendApnsPush(
        device,
        copy,
        bearerToken,
        apnsTopic,
        payload.notification_id,
        payload.post_id,
        payload.comment_id,
        payload.parent_comment_id,
        payload.type,
        payload.unread_count,
      );

      if (!failure) {
        delivered += 1;
        await clearPushDeviceDeliveryError(device.id, supabaseAdmin);
        return;
      }

      failures.push({
        deviceId: device.id,
        reason: failure.reason,
        status: failure.status,
      });
      await markPushDeviceDeliveryFailure(
        device.id,
        failure.reason,
        isTerminalApnsReason(failure.reason),
        supabaseAdmin,
      );
      logStructuredError("explore_push_delivery_failed", {
        notification_id: payload.notification_id,
        post_id: payload.post_id,
        device_id: device.id,
        environment: device.environment,
        status: failure.status,
        reason: failure.reason,
      });
    } catch (error) {
      const reason = error instanceof Error ? error.message : String(error);
      failures.push({
        deviceId: device.id,
        reason,
        status: 500,
      });
      await markPushDeviceDeliveryFailure(device.id, reason, false, supabaseAdmin);
      logStructuredError("explore_push_delivery_exception", {
        notification_id: payload.notification_id,
        post_id: payload.post_id,
        device_id: device.id,
        environment: device.environment,
        reason,
      });
    }
  });

  return jsonResponse({
    success: true,
    delivered,
    failed: failures.length,
  }, 200);
});
