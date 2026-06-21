// deno-lint-ignore no-import-prefix
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  normalizeExploreHashtag,
  requireUuid,
  syncPublicAuthorIdentity,
} from "../_shared/explore.ts";
import {
  assertCommunityRequestCanPublishToExplore,
  fetchShareEligibleScan,
  markResolvedCommunityRequestPublishedToExplore,
  replaceExplorePostHashtags,
  upsertExplorePost,
} from "./db.ts";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
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
      throw makeHttpError(
        400,
        "restored_object_keys must only contain strings.",
      );
    }
    return entry.trim();
  }).filter((entry) => entry.length > 0);

  if (normalized.length > 5) {
    throw makeHttpError(
      400,
      "restored_object_keys cannot contain more than 5 items.",
    );
  }

  const expectedPrefix = `staging/${userId.toLowerCase()}/`;
  if (!normalized.every((entry) => entry.startsWith(expectedPrefix))) {
    throw makeHttpError(
      400,
      "restored_object_keys must belong to the current user.",
    );
  }

  return normalized;
}

function normalizeFieldNotes(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw makeHttpError(400, "field_notes must be a string.");
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

function normalizeHashtags(value: unknown): string[] {
  if (value == null) return [];
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

function normalizeLocationSharing(value: unknown): string | null {
  if (value == null) return null;
  if (typeof value !== "string") {
    throw makeHttpError(400, "location_sharing must be a string.");
  }

  const normalized = value.trim().toLowerCase();
  if (
    normalized === "open" || normalized === "obscured" ||
    normalized === "private"
  ) {
    return normalized;
  }

  if (normalized === "hidden") {
    return "private";
  }

  throw makeHttpError(
    400,
    "location_sharing must be open, obscured, or private.",
  );
}

serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["scan_id"]);
    if (paramErr) return paramErr;

    const scanId = requireUuid(body.scan_id, "scan_id");
    const restoredObjectKeys = normalizeRestoredObjectKeys(
      body.restored_object_keys,
      user.id,
    );
    const speciesCommonName = normalizeSpeciesCommonName(
      body.species_common_name,
    );
    const fieldNotes = normalizeFieldNotes(body.field_notes);
    const hashtags = normalizeHashtags(body.hashtags);
    const requestedLocationSharing = normalizeLocationSharing(
      body.location_sharing,
    );

    const scan = await fetchShareEligibleScan(
      scanId,
      user.id,
      restoredObjectKeys,
      supabaseAdmin,
    );
    await assertCommunityRequestCanPublishToExplore(
      scanId,
      user.id,
      supabaseAdmin,
    );
    const locationSharing = requestedLocationSharing ?? scan.geoprivacy;
    await syncPublicAuthorIdentity(user.id, supabaseAdmin);
    const post = await upsertExplorePost(
      scanId,
      user.id,
      speciesCommonName,
      fieldNotes,
      locationSharing,
      supabaseAdmin,
    );
    await replaceExplorePostHashtags(post.id, hashtags, supabaseAdmin);
    await markResolvedCommunityRequestPublishedToExplore(
      post.id,
      user.id,
      supabaseAdmin,
    );

    return jsonResponse({
      success: true,
      post_id: post.id,
      scan_id: scanId,
      shared_at: post.shared_at,
      location_sharing: locationSharing,
    });
  })
);
