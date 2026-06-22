import {
  jsonResponse,
  logStructuredError,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
import {
  normalizeCursorTimestamp,
  normalizeLimit,
  refreshExploreAuthorStateBestEffort,
  requireUuid,
} from "../_shared/explore.ts";
import { fetchExploreNotifications } from "./db.ts";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      // Body is optional.
    }

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

    await refreshExploreAuthorStateBestEffort(
      user.id,
      supabaseAdmin,
      "get-explore-notifications",
    );

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
