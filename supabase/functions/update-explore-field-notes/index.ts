// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { requireUuid } from "../_shared/explore.ts";
import { updateExploreFieldNotes } from "./db.ts";

function makeHttpError(status: number, message: string): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

function normalizeFieldNotes(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw makeHttpError(400, "field_notes must be a string or null.");
  }

  const trimmed = value.trim();
  if (trimmed.length === 0) {
    return null;
  }

  if (trimmed.length > 1000) {
    throw makeHttpError(400, "field_notes must be 1000 characters or fewer.");
  }

  return trimmed;
}

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["post_id"]);
    if (paramErr) return paramErr;

    const postId = requireUuid(body.post_id, "post_id");
    const fieldNotes = normalizeFieldNotes(body.field_notes);
    const row = await updateExploreFieldNotes(postId, user.id, fieldNotes, supabaseAdmin);

    return jsonResponse({
      success: true,
      post_id: row.id,
      field_notes: row.field_notes,
    });
  }),
);
