// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import { normalizeExploreHashtag, requireUuid } from "../_shared/explore.ts";
import { updateExploreFieldNotes } from "./db.ts";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
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

function normalizeSpeciesCommonName(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw makeHttpError(400, "species_common_name must be a string.");
  }

  const trimmed = value.trim().replace(/\s+/g, " ");
  if (trimmed.length === 0) {
    return null;
  }

  if (trimmed.length > 200) {
    throw makeHttpError(
      400,
      "species_common_name must be 200 characters or fewer.",
    );
  }

  return trimmed;
}

function normalizeHashtags(value: unknown): string[] | undefined {
  if (value == null) return undefined;
  if (!Array.isArray(value)) {
    throw makeHttpError(400, "hashtags must be an array.");
  }

  const tags = value.map((entry) => {
    if (typeof entry !== "string") {
      throw makeHttpError(400, "hashtags must only contain strings.");
    }

    return normalizeExploreHashtag(entry, "hashtags");
  });
  const uniqueTags = [...new Set(tags)];
  if (uniqueTags.length > 5) {
    throw makeHttpError(400, "hashtags cannot contain more than 5 items.");
  }

  return uniqueTags;
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
    const hashtags = normalizeHashtags(body.hashtags);
    const speciesCommonName = Object.hasOwn(body, "species_common_name")
      ? normalizeSpeciesCommonName(body.species_common_name)
      : undefined;
    const row = await updateExploreFieldNotes(
      postId,
      user.id,
      fieldNotes,
      hashtags,
      speciesCommonName,
      supabaseAdmin,
    );

    return jsonResponse({
      success: true,
      post_id: row.id,
      field_notes: row.field_notes,
      hashtags: row.hashtags,
      species_common_name: row.species_common_name,
    });
  })
);
