// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireUuid, syncPublicAuthorIdentity } from "../_shared/explore.ts";
import { fetchShareEligibleScan, upsertExplorePost } from "./db.ts";

function makeHttpError(status: number, message: string): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

function normalizeRestoredObjectKeys(value: unknown, userId: string): string[] {
  if (value == null) return [];
  if (!Array.isArray(value)) {
    throw makeHttpError(400, "restored_object_keys must be an array.");
  }

  const normalized = value.map((entry) => {
    if (typeof entry !== "string") {
      throw makeHttpError(400, "restored_object_keys must only contain strings.");
    }
    return entry.trim();
  }).filter((entry) => entry.length > 0);

  if (normalized.length > 5) {
    throw makeHttpError(400, "restored_object_keys cannot contain more than 5 items.");
  }

  const expectedPrefix = `staging/${userId.toLowerCase()}/`;
  if (!normalized.every((entry) => entry.startsWith(expectedPrefix))) {
    throw makeHttpError(400, "restored_object_keys must belong to the current user.");
  }

  return normalized;
}

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["scan_id"]);
    if (paramErr) return paramErr;

    const scanId = requireUuid(body.scan_id, "scan_id");
    const restoredObjectKeys = normalizeRestoredObjectKeys(body.restored_object_keys, user.id);

    await fetchShareEligibleScan(scanId, user.id, restoredObjectKeys, supabaseAdmin);
    await syncPublicAuthorIdentity(user.id, supabaseAdmin);
    const post = await upsertExplorePost(scanId, user.id, supabaseAdmin);

    return jsonResponse({
      success: true,
      post_id: post.id,
      scan_id: scanId,
      shared_at: post.shared_at,
    });
  }),
);
