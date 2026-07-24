import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import {
  parseJsonBody,
  PublicHttpError,
  publicHttpError,
} from "../_shared/http.ts";
import {
  normalizeCursorTimestamp,
  normalizeLimit,
  requireUuid,
} from "../_shared/explore.ts";
import { fetchExploreNotifications } from "./db.ts";

function makeHttpError(
  status: number,
  message: string,
): PublicHttpError {
  return publicHttpError(status, message);
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const body = await parseJsonBody(req, {
      limit: "small",
      allowEmpty: true,
    });
    if (body instanceof Response) return body;

    const limit = normalizeLimit(body.limit, 50, 100);
    const beforeUpdatedAt = normalizeCursorTimestamp(
      body.before_updated_at,
      "before_updated_at",
    );
    const beforeNotificationId = body.before_notification_id == null
      ? null
      : requireUuid(body.before_notification_id, "before_notification_id");

    if ((beforeUpdatedAt == null) != (beforeNotificationId == null)) {
      throw makeHttpError(
        400,
        "before_updated_at and before_notification_id must be provided together.",
      );
    }

    let data;
    try {
      data = await fetchExploreNotifications(
        user.id,
        limit,
        {
          beforeUpdatedAt,
          beforeNotificationId,
        },
        supabaseAdmin,
      );
    } catch (error) {
      logStructuredError("explore_notifications_fetch_failed", {
        user_id: user.id,
        limit,
        before_updated_at: beforeUpdatedAt,
        before_notification_id: beforeNotificationId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }

    return jsonResponse({ data }, 200);
  })
);
