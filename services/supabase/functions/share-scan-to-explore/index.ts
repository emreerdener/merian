import {
  jsonResponse,
  runBackground,
  withEdgeHandler,
} from "../_shared/edgeHandler.ts";
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
import type { SelectedExplorePostMediaItem } from "./db.ts";
import { trackPostHogEvent } from "../_shared/posthog.ts";
import { exploreShareFailureReason } from "../_shared/exploreAudioTelemetry.ts";
import {
  deriveAIRequestId,
  reserveAIProviderCall,
  resolveAIRequestId,
} from "../_shared/aiQuota.ts";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

function normalizeRestoredObjectKeys(
  value: unknown,
  userId: string,
  fieldName = "restored_object_keys",
  maxItems = 5,
): string[] {
  if (value == null) return [];
  if (!Array.isArray(value)) {
    throw makeHttpError(400, `${fieldName} must be an array.`);
  }

  const normalized = value.map((entry) => {
    if (typeof entry !== "string") {
      throw makeHttpError(
        400,
        `${fieldName} must only contain strings.`,
      );
    }
    return entry.trim();
  }).filter((entry) => entry.length > 0);

  if (normalized.length > maxItems) {
    throw makeHttpError(
      400,
      `${fieldName} cannot contain more than ${maxItems} item${
        maxItems === 1 ? "" : "s"
      }.`,
    );
  }

  const expectedPrefix = `staging/${userId.toLowerCase()}/`;
  if (!normalized.every((entry) => entry.startsWith(expectedPrefix))) {
    throw makeHttpError(
      400,
      `${fieldName} must belong to the current user.`,
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

function normalizeMediaItems(
  value: unknown,
): SelectedExplorePostMediaItem[] | undefined {
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
    const sourceIndex = sourceMediaId ? undefined : normalizeNonNegativeInteger(
      record.source_index,
      "media_items.source_index",
    );
    const orderIndex = Object.hasOwn(record, "order_index")
      ? normalizeNonNegativeInteger(
        record.order_index,
        "media_items.order_index",
      )
      : index;

    const normalized: SelectedExplorePostMediaItem = {
      kind,
      source_media_id: sourceMediaId || undefined,
      source_index: sourceIndex,
      order_index: orderIndex,
    };

    if (kind === "video" && Object.hasOwn(record, "thumbnail_source_index")) {
      normalized.thumbnail_source_index = normalizeNonNegativeInteger(
        record.thumbnail_source_index,
        "media_items.thumbnail_source_index",
      );
    } else if (Object.hasOwn(record, "thumbnail_source_index")) {
      throw makeHttpError(
        400,
        "Only video media can include a thumbnail source.",
      );
    }

    return normalized;
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
    const restoredVideoObjectKeys = normalizeRestoredObjectKeys(
      body.restored_video_object_keys,
      user.id,
      "restored_video_object_keys",
    );
    const restoredAudioObjectKeys = normalizeRestoredObjectKeys(
      body.restored_audio_object_keys,
      user.id,
      "restored_audio_object_keys",
      2,
    );
    const speciesCommonName = normalizeSpeciesCommonName(
      body.species_common_name,
    );
    const fieldNotes = normalizeFieldNotes(body.field_notes);
    const hashtags = normalizeHashtags(body.hashtags);
    const requestedLocationSharing = normalizeLocationSharing(
      body.location_sharing,
    );
    const mediaItems = normalizeMediaItems(body.media_items);
    let moderationParentRequestId: string | null = null;

    runBackground(trackPostHogEvent(user.id, "ExplorePostShareStarted", {
      event_source: "supabase_edge",
      requested_audio_clip_count: mediaItems?.filter((item) =>
        item.kind === "audio"
      ).length ?? null,
    }));

    try {
      const scan = await fetchShareEligibleScan(
        scanId,
        user.id,
        restoredObjectKeys,
        restoredVideoObjectKeys,
        restoredAudioObjectKeys,
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
        scan,
        user.id,
        speciesCommonName,
        fieldNotes,
        locationSharing,
        mediaItems,
        supabaseAdmin,
        {
          beforeProvider: async ({ checksumSha256, policyVersion }) => {
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
            });
          },
        },
      );
      await replaceExplorePostHashtags(post.id, hashtags, supabaseAdmin);
      await markResolvedCommunityRequestPublishedToExplore(
        post.id,
        user.id,
        supabaseAdmin,
      );
      runBackground(trackPostHogEvent(user.id, "ExplorePostShared", {
        event_source: "supabase_edge",
        has_audio: post.audible_media_count > 0,
        audio_clip_count: post.audio_clip_count,
        is_mixed_media: post.audio_clip_count > 0 &&
          post.media_kinds.some((kind) => kind !== "audio"),
        location_sharing: locationSharing,
      }));
      return jsonResponse({
        success: true,
        post_id: post.id,
        scan_id: scanId,
        shared_at: post.shared_at,
        location_sharing: locationSharing,
        publication_status: post.publication_status,
      });
    } catch (error) {
      runBackground(trackPostHogEvent(user.id, "ExplorePostShareFailed", {
        event_source: "supabase_edge",
        reason: exploreShareFailureReason(error),
      }));
      throw error;
    }
  })
);
