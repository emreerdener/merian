import { importPKCS8, SignJWT } from "jose";
import { mapWithConcurrencyLimit } from "../_shared/concurrency.ts";
import { logStructuredError, serveEdge } from "../_shared/edgeHandler.ts";
import { requireUuid } from "../_shared/explore.ts";
import {
  corsHeaders,
  jsonResponse,
  parseJsonBody,
  requireParams,
} from "../_shared/http.ts";
import { authorizeServiceRoleRequestFromEnvironment } from "../_shared/serviceRoleAuth.ts";
import { createServiceRoleClient } from "../_shared/serviceRoleClient.ts";
import {
  clearPushDeviceDeliveryError,
  ExplorePushNotificationPayload,
  fetchEligiblePushDevices,
  fetchExplorePushNotificationPayload,
  markPushDeviceDeliveryFailure,
} from "./db.ts";
import {
  apnsDeliveryExceptionReason,
  type NotificationCopy,
  sendApnsPush,
} from "./delivery.ts";

const APNS_DELIVERY_CONCURRENCY = 8;
let cachedApnsBearerToken: { token: string; expiresAtMs: number } | null = null;

function normalizePrivateKey(rawValue: string): string {
  return rawValue.replace(/\\n/g, "\n").trim();
}

function buildLikeTitle(actorNames: string[], actionCount: number): string {
  const safeCount = Math.max(actionCount, actorNames.length);
  if (actorNames.length >= 2 && safeCount > 2) {
    return `${actorNames[0]}, ${actorNames[1]}, and ${
      safeCount - 2
    } others liked your post`;
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
    return `${actorNames[0]}, ${actorNames[1]}, and ${
      safeCount - 2
    } others ${actionSuffix}`;
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
  if (trimmed.length <= 120) {
    return trimmed || "Open Explore to view the conversation.";
  }
  return `${trimmed.slice(0, 117)}...`;
}

function communityDisplayName(payload: ExplorePushNotificationPayload): string {
  return (
    payload.community_request_display_name ??
      payload.community_taxon_common_name ??
      payload.community_taxon_scientific_name ??
      "the request"
  ).trim() || "the request";
}

function buildNotificationCopy(
  payload: ExplorePushNotificationPayload,
): NotificationCopy {
  if (payload.type === "media_missing") {
    return {
      title: "Media is unavailable on an Explore post",
      body:
        "Open your Scan Library. The post and engagement are preserved while we try to restore it.",
    };
  }

  if (payload.type === "media_restored") {
    return {
      title: "Your Explore post is back",
      body: "Its media was restored automatically.",
    };
  }

  if (payload.type === "community_identification_added") {
    return {
      title: "Someone suggested an ID for your request",
      body: `Open Community to review ${communityDisplayName(payload)}.`,
    };
  }

  if (payload.type === "community_request_resolved") {
    return {
      title: "Your Community request was identified",
      body: `Consensus reached ${communityDisplayName(payload)}.`,
    };
  }

  if (payload.type === "community_identification_helped") {
    return {
      title: "Your ID helped resolve a request",
      body: `The community identified ${communityDisplayName(payload)}.`,
    };
  }

  if (payload.type === "comment") {
    const actorName = typeof payload.triggering_user_name === "string" &&
        payload.triggering_user_name.length > 0
      ? payload.triggering_user_name
      : "Someone";
    return {
      title: `${actorName} commented on your post`,
      body: buildCommentBody(payload.comment_body),
    };
  }

  if (payload.type === "comment_reply") {
    const actorName = typeof payload.triggering_user_name === "string" &&
        payload.triggering_user_name.length > 0
      ? payload.triggering_user_name
      : "Someone";
    return {
      title: payload.is_reply_to_viewer_comment
        ? `${actorName} replied to your comment`
        : `${actorName} replied on your post`,
      body: buildCommentBody(payload.comment_body),
    };
  }

  if (payload.type === "comment_mention") {
    const actorName = typeof payload.triggering_user_name === "string" &&
        payload.triggering_user_name.length > 0
      ? payload.triggering_user_name
      : "Someone";
    return {
      title: `${actorName} mentioned you in a comment`,
      body: buildCommentBody(payload.comment_body),
    };
  }

  const actorNames =
    payload.recent_actor_names?.filter((value): value is string =>
      value.length > 0
    ) ?? [];

  if (payload.type === "comment_reaction") {
    return {
      title: buildCommentReactionTitle(
        actorNames,
        payload.action_count,
        payload.reaction_emoji,
      ),
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

async function getApnsBearerToken(): Promise<string | null> {
  const now = Date.now();
  if (
    cachedApnsBearerToken &&
    cachedApnsBearerToken.expiresAtMs - now > 5 * 60 * 1000
  ) {
    return cachedApnsBearerToken.token;
  }

  const teamId = Deno.env.get("APNS_TEAM_ID");
  const keyId = Deno.env.get("APNS_KEY_ID");
  const privateKey = Deno.env.get("APNS_PRIVATE_KEY");

  if (!teamId || !keyId || !privateKey) {
    return null;
  }

  const importedKey = await importPKCS8(
    normalizePrivateKey(privateKey),
    "ES256",
  );
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

serveEdge(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method Not Allowed" }, 405);
  }

  const auth = authorizeServiceRoleRequestFromEnvironment(req);
  if (!auth.ok) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  const body = await parseJsonBody(req, { limit: "small" });
  if (body instanceof Response) return body;

  const paramErr = requireParams(body, ["notification_id"]);
  if (paramErr) return paramErr;

  const notificationId = requireUuid(body.notification_id, "notification_id");
  const supabaseAdmin = createServiceRoleClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    auth.serverApiKey,
  );

  const payload = await fetchExplorePushNotificationPayload(
    notificationId,
    supabaseAdmin,
  );
  if (!payload) {
    return jsonResponse(
      { success: true, skipped: "notification_not_visible" },
      200,
    );
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

  const devices = await fetchEligiblePushDevices(
    payload.recipient_user_id,
    payload.type,
    supabaseAdmin,
  );
  if (devices.length === 0) {
    return jsonResponse({
      success: true,
      delivered: 0,
      skipped: "no_eligible_devices",
    }, 200);
  }

  const copy = buildNotificationCopy(payload);
  let delivered = 0;
  const failures: Array<{ deviceId: string; reason: string; status: number }> =
    [];

  await mapWithConcurrencyLimit(
    devices,
    APNS_DELIVERY_CONCURRENCY,
    async (device) => {
      try {
        const failure = await sendApnsPush(
          device,
          copy,
          bearerToken,
          apnsTopic,
          payload.notification_id,
          payload.post_id,
          payload.community_request_id,
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
        const reason = apnsDeliveryExceptionReason(error);
        failures.push({
          deviceId: device.id,
          reason,
          status: 500,
        });
        await markPushDeviceDeliveryFailure(
          device.id,
          reason,
          false,
          supabaseAdmin,
        );
        logStructuredError("explore_push_delivery_exception", {
          notification_id: payload.notification_id,
          post_id: payload.post_id,
          device_id: device.id,
          environment: device.environment,
          reason,
          error_name: error instanceof Error ? error.name : typeof error,
        });
      }
    },
  );

  return jsonResponse({
    success: true,
    delivered,
    failed: failures.length,
  }, 200);
});
