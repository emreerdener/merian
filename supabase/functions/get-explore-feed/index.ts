// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  normalizeCursorTimestamp,
  normalizeLimit,
  requireUuid,
} from "../_shared/explore.ts";
import { fetchExploreFeed } from "./db.ts";

function makeHttpError(status: number, message: string): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    let body: Record<string, unknown> = {};
    try {
      body = await req.json();
    } catch {
      // Body is optional.
    }

    const limit = normalizeLimit(body.limit, 20, 100);
    const beforeSharedAt = normalizeCursorTimestamp(body.before_shared_at, "before_shared_at");
    const beforePostId = body.before_post_id == null
      ? null
      : requireUuid(body.before_post_id, "before_post_id");

    if ((beforeSharedAt == null) != (beforePostId == null)) {
      throw makeHttpError(400, "before_shared_at and before_post_id must be provided together.");
    }

    const data = await fetchExploreFeed(
      user.id,
      limit,
      {
        beforeSharedAt,
        beforePostId,
      },
      supabaseAdmin,
    );

    return jsonResponse({ data }, 200);
  }),
);
