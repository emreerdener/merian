import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import {
  parseJsonBody,
  PublicHttpError,
  publicHttpError,
  requireParams,
} from "../_shared/http.ts";
import { normalizeExploreHashtag, requireUuid } from "../_shared/explore.ts";
import { updateExploreFieldNotes } from "./db.ts";
import type { ExistingExplorePostMediaSelection } from "./db.ts";
import {
  deriveAIRequestId,
  reserveAIProviderCall,
  resolveAIRequestId,
} from "../_shared/aiQuota.ts";

function makeHttpError(
  status: number,
  message: string,
): PublicHttpError {
  return publicHttpError(status, message);
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

function normalizeLocationSharing(value: unknown): string | undefined {
  if (value == null) return undefined;
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

function normalizeMediaItems(
  value: unknown,
): ExistingExplorePostMediaSelection[] | undefined {
  if (value == null) return undefined;
  if (!Array.isArray(value)) {
    throw makeHttpError(400, "media_items must be an array.");
  }
  if (value.length === 0) {
    throw makeHttpError(400, "media_items must include at least one item.");
  }

  return value.map((entry, index) => {
    if (entry == null || typeof entry !== "object" || Array.isArray(entry)) {
      throw makeHttpError(400, "media_items entries must be objects.");
    }

    const record = entry as Record<string, unknown>;
    const kind = record.kind;
    if (kind !== "image" && kind !== "video" && kind !== "audio") {
      throw makeHttpError(
        400,
        "media_items can only include image, video, or audio.",
      );
    }
    const sourceMediaId = typeof record.source_media_id === "string"
      ? record.source_media_id.trim()
      : null;
    const url = typeof record.url === "string" ? record.url.trim() : null;
    if (!sourceMediaId && !url) {
      throw makeHttpError(400, "media_items requires source_media_id or url.");
    }

    const orderIndex = Object.hasOwn(record, "order_index")
      ? normalizeNonNegativeInteger(
        record.order_index,
        "media_items.order_index",
      )
      : index;
    const thumbnailUrl = typeof record.thumbnail_url === "string"
      ? record.thumbnail_url.trim()
      : null;

    if (kind === "video" && !sourceMediaId && !thumbnailUrl) {
      throw makeHttpError(400, "Selected video media requires a thumbnail.");
    }

    return {
      kind,
      source_media_id: sourceMediaId || undefined,
      url: url || undefined,
      thumbnail_url: thumbnailUrl,
      order_index: orderIndex,
    };
  });
}

function normalizeNonNegativeInteger(
  value: unknown,
  fieldName: string,
): number {
  if (!Number.isInteger(value) || (value as number) < 0) {
    throw makeHttpError(400, `${fieldName} must be a non-negative integer.`);
  }

  return value as number;
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req, { limit: "standard" });
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
    const locationSharing = Object.hasOwn(body, "location_sharing")
      ? normalizeLocationSharing(body.location_sharing)
      : undefined;
    const mediaItems = normalizeMediaItems(body.media_items);
    let moderationParentRequestId: string | null = null;
    const row = await updateExploreFieldNotes(
      postId,
      user.id,
      fieldNotes,
      hashtags,
      speciesCommonName,
      locationSharing,
      mediaItems,
      supabaseAdmin,
      {
        beforeProvider: async ({
          checksumSha256,
          policyVersion,
          originalAnalysisId,
        }) => {
          moderationParentRequestId ??= resolveAIRequestId(
            req,
            body.ai_request_id,
          );
          const requestId = await deriveAIRequestId(
            moderationParentRequestId,
            `${checksumSha256}:${policyVersion}`,
          );
          return await reserveAIProviderCall(req, supabaseAdmin, {
            userId: user.id,
            operation: "explore_audio_moderation",
            requestId,
            originalAnalysisId: originalAnalysisId ?? null,
          });
        },
      },
    );

    return jsonResponse({
      success: true,
      post_id: row.id,
      field_notes: row.field_notes,
      hashtags: row.hashtags,
      species_common_name: row.species_common_name,
      location_sharing: row.location_sharing,
    });
  })
);
