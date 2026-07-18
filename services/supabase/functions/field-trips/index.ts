import { jsonResponse, withEdgeHandler } from "../_shared/edgeHandler.ts";
import { parseJsonBody, requireParams } from "../_shared/http.ts";
import {
  fetchPublicAuthorIdentity,
  hasMutualBlock,
  normalizeCursorTimestamp,
  normalizeLimit,
  requireUuid,
  syncPublicAuthorIdentity,
} from "../_shared/explore.ts";
import {
  applyFieldTripScanProgress,
  assertCanViewFieldTripChallengeEntry,
  assertCanViewFieldTripPublication,
  fetchCommunityFieldTripPublications,
  fetchFieldTripCaptureContext,
  fetchFieldTripCatalog,
  fetchFieldTripChallengeCommentParent,
  fetchFieldTripChallengeDetail,
  fetchFieldTripChallengeEntryComments,
  fetchFieldTripChallengeEntryCounts,
  fetchFieldTripChallengeEntryDetail,
  fetchFieldTripChallengeHashtagsForScan,
  fetchFieldTripChallengePublications,
  fetchFieldTripChallengesCatalog,
  fetchFieldTripCommentParent,
  fetchFieldTripComments,
  fetchFieldTripProfileSummaries,
  fetchFieldTripPublicationCounts,
  fetchFieldTripPublicationDetail,
  fetchFieldTripTemplateDetail,
  fetchRecentFieldTripPublications,
  insertFieldTripChallengeEntryComment,
  insertFieldTripComment,
  joinFieldTripChallenge,
  publishFieldTrip,
  publishFieldTripChallengeEntry,
  setFieldTripChallengeEntryLike,
  setFieldTripLike,
  setPinnedFieldTripPublications,
  startFieldTrip,
} from "./db.ts";

type FieldTripAction =
  | "catalog"
  | "capture_context"
  | "challenges_catalog"
  | "template_detail"
  | "start"
  | "challenge_detail"
  | "join_challenge"
  | "community_publications"
  | "recent_publications"
  | "challenge_publications"
  | "apply_scan_progress"
  | "scan_challenge_hashtags"
  | "profile_summaries"
  | "set_pinned_publications"
  | "publish"
  | "publish_challenge_entry"
  | "detail"
  | "challenge_entry_detail"
  | "set_like"
  | "set_challenge_entry_like"
  | "comments"
  | "challenge_entry_comments"
  | "create_comment"
  | "create_challenge_entry_comment";

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

function normalizeAction(rawAction: unknown): FieldTripAction {
  if (typeof rawAction !== "string") {
    throw makeHttpError(400, "action must be a string.");
  }

  switch (rawAction) {
    case "catalog":
    case "capture_context":
    case "challenges_catalog":
    case "template_detail":
    case "start":
    case "challenge_detail":
    case "join_challenge":
    case "community_publications":
    case "recent_publications":
    case "challenge_publications":
    case "apply_scan_progress":
    case "scan_challenge_hashtags":
    case "profile_summaries":
    case "set_pinned_publications":
    case "publish":
    case "publish_challenge_entry":
    case "detail":
    case "challenge_entry_detail":
    case "set_like":
    case "set_challenge_entry_like":
    case "comments":
    case "challenge_entry_comments":
    case "create_comment":
    case "create_challenge_entry_comment":
      return rawAction;
    default:
      throw makeHttpError(400, "Unsupported Field trip action.");
  }
}

function normalizeCommunityMode(
  rawMode: unknown,
): "smart" | "following" | "recent" {
  if (rawMode == null) return "smart";
  if (typeof rawMode !== "string") {
    throw makeHttpError(400, "mode must be a string.");
  }

  switch (rawMode.trim().toLowerCase()) {
    case "smart":
    case "following":
    case "recent":
      return rawMode.trim().toLowerCase() as "smart" | "following" | "recent";
    default:
      throw makeHttpError(400, "Unsupported Field trip community mode.");
  }
}

function normalizeRankBucket(rawValue: unknown): number | null {
  if (rawValue == null) return null;
  if (typeof rawValue !== "number" || !Number.isInteger(rawValue)) {
    throw makeHttpError(400, "before_rank_bucket must be an integer.");
  }
  if (rawValue < 0 || rawValue > 10) {
    throw makeHttpError(400, "before_rank_bucket is out of range.");
  }
  return rawValue;
}

function nullableTrimmedString(
  rawValue: unknown,
  maxLength: number,
): string | null {
  if (rawValue == null) return null;
  if (typeof rawValue !== "string") {
    throw makeHttpError(400, "Expected a string value.");
  }

  const trimmed = rawValue.trim();
  if (trimmed.length === 0) return null;
  if (trimmed.length > maxLength) {
    throw makeHttpError(
      400,
      `String value must be ${maxLength} characters or fewer.`,
    );
  }
  return trimmed;
}

function nullableTrimmedStringArray(
  rawValue: unknown,
  maxCount: number,
  maxLength: number,
): string[] {
  if (rawValue == null) return [];
  if (!Array.isArray(rawValue)) {
    throw makeHttpError(400, "Expected an array of strings.");
  }
  if (rawValue.length > maxCount) {
    throw makeHttpError(
      400,
      `Array value must contain ${maxCount} items or fewer.`,
    );
  }

  const values: string[] = [];
  for (const item of rawValue) {
    if (typeof item !== "string") {
      throw makeHttpError(400, "Expected an array of strings.");
    }
    const trimmed = item.trim();
    if (trimmed.length === 0) continue;
    if (trimmed.length > maxLength) {
      throw makeHttpError(
        400,
        `Array string values must be ${maxLength} characters or fewer.`,
      );
    }
    values.push(trimmed);
  }
  return values;
}

function requireUuidArray(
  rawValue: unknown,
  fieldName: string,
  maxCount: number,
): string[] {
  if (!Array.isArray(rawValue)) {
    throw makeHttpError(400, `${fieldName} must be an array.`);
  }
  if (rawValue.length > maxCount) {
    throw makeHttpError(
      400,
      `${fieldName} must contain ${maxCount} ids or fewer.`,
    );
  }

  return rawValue.map((value, index) =>
    requireUuid(value, `${fieldName}[${index}]`)
  );
}

Deno.serve((req: Request) =>
  withEdgeHandler(req, async (user, supabaseAdmin) => {
    const parsedBody = await parseJsonBody(req);
    if (parsedBody instanceof Response) return parsedBody;
    const body = parsedBody;

    const paramErr = requireParams(body, ["action"]);
    if (paramErr) return paramErr;

    const action = normalizeAction(body.action);

    switch (action) {
      case "capture_context": {
        const data = await fetchFieldTripCaptureContext(
          user.id,
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "catalog": {
        const limit = normalizeLimit(body.limit, 40, 80);
        const userRegion = nullableTrimmedString(body.user_region, 80);
        const data = await fetchFieldTripCatalog(
          user.id,
          userRegion,
          limit,
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "challenges_catalog": {
        const limit = normalizeLimit(body.limit, 20, 60);
        const userRegion = nullableTrimmedString(body.user_region, 80);
        const data = await fetchFieldTripChallengesCatalog(
          user.id,
          userRegion,
          limit,
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "template_detail": {
        const templateId = body.template_id == null
          ? null
          : requireUuid(body.template_id, "template_id");
        const slug = nullableTrimmedString(body.slug, 90);
        if (templateId == null && slug == null) {
          throw makeHttpError(400, "template_id or slug is required.");
        }

        const data = await fetchFieldTripTemplateDetail(
          user.id,
          templateId,
          slug,
          supabaseAdmin,
        );
        if (!data) {
          return jsonResponse({ error: "Field trip template not found" }, 404);
        }
        return jsonResponse({ data });
      }

      case "start": {
        const actionErr = requireParams(body, ["template_id"]);
        if (actionErr) return actionErr;
        const templateId = requireUuid(body.template_id, "template_id");
        const data = await startFieldTrip(
          user.id,
          templateId,
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "challenge_detail": {
        const challengeId = body.challenge_id == null
          ? null
          : requireUuid(body.challenge_id, "challenge_id");
        const slug = nullableTrimmedString(body.slug, 90);
        if (challengeId == null && slug == null) {
          throw makeHttpError(400, "challenge_id or slug is required.");
        }
        const entriesLimit = normalizeLimit(body.entries_limit, 12, 30);
        const data = await fetchFieldTripChallengeDetail(
          user.id,
          challengeId,
          slug,
          entriesLimit,
          supabaseAdmin,
        );
        if (!data) {
          return jsonResponse({ error: "Field trip challenge not found" }, 404);
        }
        return jsonResponse({ data });
      }

      case "join_challenge": {
        const actionErr = requireParams(body, ["challenge_id"]);
        if (actionErr) return actionErr;
        const challengeId = requireUuid(body.challenge_id, "challenge_id");
        const data = await joinFieldTripChallenge(
          user.id,
          challengeId,
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "recent_publications": {
        const limit = normalizeLimit(body.limit, 20, 60);
        const userRegion = nullableTrimmedString(body.user_region, 80);
        const habitatTags = nullableTrimmedStringArray(
          body.habitat_tags,
          12,
          80,
        );
        const beforePublishedAt = normalizeCursorTimestamp(
          body.before_published_at,
          "before_published_at",
        );
        const beforePublicationId = body.before_publication_id == null
          ? null
          : requireUuid(body.before_publication_id, "before_publication_id");

        if ((beforePublishedAt == null) != (beforePublicationId == null)) {
          throw makeHttpError(
            400,
            "before_published_at and before_publication_id must be provided together.",
          );
        }

        const data = await fetchRecentFieldTripPublications(
          user.id,
          userRegion,
          habitatTags,
          limit,
          { beforePublishedAt, beforePublicationId },
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "community_publications": {
        const limit = normalizeLimit(body.limit, 20, 60);
        const mode = normalizeCommunityMode(body.mode);
        const templateId = body.template_id == null
          ? null
          : requireUuid(body.template_id, "template_id");
        const userRegion = nullableTrimmedString(body.user_region, 80);
        const habitatTags = nullableTrimmedStringArray(
          body.habitat_tags,
          12,
          80,
        );
        const seasonTags = nullableTrimmedStringArray(
          body.season_tags,
          8,
          80,
        );
        const beforeRankBucket = normalizeRankBucket(body.before_rank_bucket);
        const beforePublishedAt = normalizeCursorTimestamp(
          body.before_published_at,
          "before_published_at",
        );
        const beforePublicationId = body.before_publication_id == null
          ? null
          : requireUuid(body.before_publication_id, "before_publication_id");

        const hasCursor = beforeRankBucket != null ||
          beforePublishedAt != null ||
          beforePublicationId != null;
        if (
          hasCursor &&
          (beforeRankBucket == null ||
            beforePublishedAt == null ||
            beforePublicationId == null)
        ) {
          throw makeHttpError(
            400,
            "before_rank_bucket, before_published_at, and before_publication_id must be provided together.",
          );
        }

        const data = await fetchCommunityFieldTripPublications(
          user.id,
          mode,
          templateId,
          userRegion,
          habitatTags,
          seasonTags,
          limit,
          { beforeRankBucket, beforePublishedAt, beforePublicationId },
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "challenge_publications": {
        const actionErr = requireParams(body, ["challenge_id"]);
        if (actionErr) return actionErr;
        const challengeId = requireUuid(body.challenge_id, "challenge_id");
        const limit = normalizeLimit(body.limit, 20, 60);
        const beforePublishedAt = normalizeCursorTimestamp(
          body.before_published_at,
          "before_published_at",
        );
        const beforeEntryId = body.before_entry_id == null
          ? null
          : requireUuid(body.before_entry_id, "before_entry_id");

        if ((beforePublishedAt == null) != (beforeEntryId == null)) {
          throw makeHttpError(
            400,
            "before_published_at and before_entry_id must be provided together.",
          );
        }

        const data = await fetchFieldTripChallengePublications(
          user.id,
          challengeId,
          limit,
          { beforePublishedAt, beforeEntryId },
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "apply_scan_progress": {
        const actionErr = requireParams(body, ["scan_id"]);
        if (actionErr) return actionErr;
        const scanId = requireUuid(body.scan_id, "scan_id");
        const progress = await applyFieldTripScanProgress(
          user.id,
          scanId,
          supabaseAdmin,
        );
        return jsonResponse({
          data: progress.fieldTripUpdates,
          challenge_updates: progress.challengeUpdates,
        });
      }

      case "scan_challenge_hashtags": {
        const actionErr = requireParams(body, ["scan_id"]);
        if (actionErr) return actionErr;
        const scanId = requireUuid(body.scan_id, "scan_id");
        const data = await fetchFieldTripChallengeHashtagsForScan(
          user.id,
          scanId,
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "profile_summaries": {
        const actionErr = requireParams(body, ["author_user_id"]);
        if (actionErr) return actionErr;
        const authorUserId = requireUuid(body.author_user_id, "author_user_id");
        const limit = normalizeLimit(body.limit, 6, 12);
        const data = await fetchFieldTripProfileSummaries(
          user.id,
          authorUserId,
          limit,
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "set_pinned_publications": {
        const actionErr = requireParams(body, ["publication_ids"]);
        if (actionErr) return actionErr;
        const publicationIds = requireUuidArray(
          body.publication_ids,
          "publication_ids",
          3,
        );
        const data = await setPinnedFieldTripPublications(
          user.id,
          publicationIds,
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "publish": {
        const actionErr = requireParams(body, ["user_field_trip_id"]);
        if (actionErr) return actionErr;
        const userFieldTripId = requireUuid(
          body.user_field_trip_id,
          "user_field_trip_id",
        );
        const title = nullableTrimmedString(body.title, 90);
        const description = nullableTrimmedString(body.description, 1200);
        const aiSummary = nullableTrimmedString(body.ai_summary, 1200);
        const data = await publishFieldTrip(
          user.id,
          userFieldTripId,
          title,
          description,
          aiSummary,
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "publish_challenge_entry": {
        const actionErr = requireParams(body, ["participation_id"]);
        if (actionErr) return actionErr;
        const participationId = requireUuid(
          body.participation_id,
          "participation_id",
        );
        const title = nullableTrimmedString(body.title, 90);
        const description = nullableTrimmedString(body.description, 1200);
        const data = await publishFieldTripChallengeEntry(
          user.id,
          participationId,
          title,
          description,
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "detail": {
        const actionErr = requireParams(body, ["publication_id"]);
        if (actionErr) return actionErr;
        const publicationId = requireUuid(
          body.publication_id,
          "publication_id",
        );
        const data = await fetchFieldTripPublicationDetail(
          user.id,
          publicationId,
          supabaseAdmin,
        );
        if (!data) {
          return jsonResponse(
            { error: "Field trip publication not found" },
            404,
          );
        }
        return jsonResponse({ data });
      }

      case "challenge_entry_detail": {
        const actionErr = requireParams(body, ["entry_id"]);
        if (actionErr) return actionErr;
        const entryId = requireUuid(body.entry_id, "entry_id");
        const data = await fetchFieldTripChallengeEntryDetail(
          user.id,
          entryId,
          supabaseAdmin,
        );
        if (!data) {
          return jsonResponse(
            { error: "Field trip challenge entry not found" },
            404,
          );
        }
        return jsonResponse({ data });
      }

      case "set_like": {
        const actionErr = requireParams(body, ["publication_id", "liked"]);
        if (actionErr) return actionErr;
        const publicationId = requireUuid(
          body.publication_id,
          "publication_id",
        );
        if (typeof body.liked !== "boolean") {
          return jsonResponse({ error: "liked must be a boolean." }, 400);
        }
        await assertCanViewFieldTripPublication(
          user.id,
          publicationId,
          supabaseAdmin,
        );
        await setFieldTripLike(
          publicationId,
          user.id,
          body.liked,
          supabaseAdmin,
        );
        const counts = await fetchFieldTripPublicationCounts(
          publicationId,
          supabaseAdmin,
        );
        return jsonResponse({
          success: true,
          publication_id: publicationId,
          viewer_has_liked: body.liked,
          like_count: counts.likeCount,
          comment_count: counts.commentCount,
        });
      }

      case "set_challenge_entry_like": {
        const actionErr = requireParams(body, ["entry_id", "liked"]);
        if (actionErr) return actionErr;
        const entryId = requireUuid(body.entry_id, "entry_id");
        if (typeof body.liked !== "boolean") {
          return jsonResponse({ error: "liked must be a boolean." }, 400);
        }
        await assertCanViewFieldTripChallengeEntry(
          user.id,
          entryId,
          supabaseAdmin,
        );
        await setFieldTripChallengeEntryLike(
          entryId,
          user.id,
          body.liked,
          supabaseAdmin,
        );
        const counts = await fetchFieldTripChallengeEntryCounts(
          entryId,
          supabaseAdmin,
        );
        return jsonResponse({
          success: true,
          entry_id: entryId,
          viewer_has_liked: body.liked,
          like_count: counts.likeCount,
          comment_count: counts.commentCount,
        });
      }

      case "comments": {
        const actionErr = requireParams(body, ["publication_id"]);
        if (actionErr) return actionErr;
        const publicationId = requireUuid(
          body.publication_id,
          "publication_id",
        );
        const limit = normalizeLimit(body.limit, 50, 100);
        const afterCreatedAt = normalizeCursorTimestamp(
          body.after_created_at,
          "after_created_at",
        );
        const afterCommentId = body.after_comment_id == null
          ? null
          : requireUuid(body.after_comment_id, "after_comment_id");

        if ((afterCreatedAt == null) != (afterCommentId == null)) {
          throw makeHttpError(
            400,
            "after_created_at and after_comment_id must be provided together.",
          );
        }

        const data = await fetchFieldTripComments(
          user.id,
          publicationId,
          limit,
          { afterCreatedAt, afterCommentId },
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "challenge_entry_comments": {
        const actionErr = requireParams(body, ["entry_id"]);
        if (actionErr) return actionErr;
        const entryId = requireUuid(body.entry_id, "entry_id");
        const limit = normalizeLimit(body.limit, 50, 100);
        const afterCreatedAt = normalizeCursorTimestamp(
          body.after_created_at,
          "after_created_at",
        );
        const afterCommentId = body.after_comment_id == null
          ? null
          : requireUuid(body.after_comment_id, "after_comment_id");

        if ((afterCreatedAt == null) != (afterCommentId == null)) {
          throw makeHttpError(
            400,
            "after_created_at and after_comment_id must be provided together.",
          );
        }

        const data = await fetchFieldTripChallengeEntryComments(
          user.id,
          entryId,
          limit,
          { afterCreatedAt, afterCommentId },
          supabaseAdmin,
        );
        return jsonResponse({ data });
      }

      case "create_comment": {
        const actionErr = requireParams(body, ["publication_id", "body"]);
        if (actionErr) return actionErr;
        const publicationId = requireUuid(
          body.publication_id,
          "publication_id",
        );
        const parentCommentId = body.parent_comment_id == null
          ? null
          : requireUuid(body.parent_comment_id, "parent_comment_id");
        const rawBody = typeof body.body === "string" ? body.body.trim() : "";
        if (rawBody.length === 0) {
          return jsonResponse(
            { error: "body must be a non-empty string." },
            400,
          );
        }
        if (rawBody.length > 500) {
          return jsonResponse(
            { error: "body must be 500 characters or fewer." },
            400,
          );
        }

        await assertCanViewFieldTripPublication(
          user.id,
          publicationId,
          supabaseAdmin,
        );
        if (parentCommentId != null) {
          const parent = await fetchFieldTripCommentParent(
            parentCommentId,
            publicationId,
            supabaseAdmin,
          );
          if (
            parent.user_id !== user.id &&
            await hasMutualBlock(user.id, parent.user_id, supabaseAdmin)
          ) {
            return jsonResponse({
              error: "You cannot reply to this Field trip comment.",
            }, 403);
          }
        }

        await syncPublicAuthorIdentity(user.id, supabaseAdmin);
        const inserted = await insertFieldTripComment(
          publicationId,
          user.id,
          rawBody,
          parentCommentId,
          supabaseAdmin,
        );
        const authorIdentity = await fetchPublicAuthorIdentity(
          user.id,
          supabaseAdmin,
        );
        const counts = await fetchFieldTripPublicationCounts(
          publicationId,
          supabaseAdmin,
        );

        return jsonResponse({
          success: true,
          comment: {
            comment_id: inserted.id,
            post_id: inserted.publication_id,
            parent_comment_id: inserted.parent_comment_id ?? null,
            author_user_id: user.id,
            author_name: authorIdentity.authorName,
            author_username: authorIdentity.authorUsername,
            author_avatar_url: authorIdentity.authorAvatarUrl,
            body: rawBody,
            created_at: inserted.created_at,
            viewer_can_delete: true,
            viewer_can_moderate: false,
            viewer_can_report: false,
            reply_count: 0,
            reactions: [],
            mentions: [],
          },
          comment_count: counts.commentCount,
        });
      }

      case "create_challenge_entry_comment": {
        const actionErr = requireParams(body, ["entry_id", "body"]);
        if (actionErr) return actionErr;
        const entryId = requireUuid(body.entry_id, "entry_id");
        const parentCommentId = body.parent_comment_id == null
          ? null
          : requireUuid(body.parent_comment_id, "parent_comment_id");
        const rawBody = typeof body.body === "string" ? body.body.trim() : "";
        if (rawBody.length === 0) {
          return jsonResponse(
            { error: "body must be a non-empty string." },
            400,
          );
        }
        if (rawBody.length > 500) {
          return jsonResponse(
            { error: "body must be 500 characters or fewer." },
            400,
          );
        }

        await assertCanViewFieldTripChallengeEntry(
          user.id,
          entryId,
          supabaseAdmin,
        );
        if (parentCommentId != null) {
          const parent = await fetchFieldTripChallengeCommentParent(
            parentCommentId,
            entryId,
            supabaseAdmin,
          );
          if (
            parent.user_id !== user.id &&
            await hasMutualBlock(user.id, parent.user_id, supabaseAdmin)
          ) {
            return jsonResponse({
              error: "You cannot reply to this Field trip challenge comment.",
            }, 403);
          }
        }

        await syncPublicAuthorIdentity(user.id, supabaseAdmin);
        const inserted = await insertFieldTripChallengeEntryComment(
          entryId,
          user.id,
          rawBody,
          parentCommentId,
          supabaseAdmin,
        );
        const authorIdentity = await fetchPublicAuthorIdentity(
          user.id,
          supabaseAdmin,
        );
        const counts = await fetchFieldTripChallengeEntryCounts(
          entryId,
          supabaseAdmin,
        );

        return jsonResponse({
          success: true,
          comment: {
            comment_id: inserted.id,
            post_id: inserted.entry_id,
            parent_comment_id: inserted.parent_comment_id ?? null,
            author_user_id: user.id,
            author_name: authorIdentity.authorName,
            author_username: authorIdentity.authorUsername,
            author_avatar_url: authorIdentity.authorAvatarUrl,
            body: rawBody,
            created_at: inserted.created_at,
            viewer_can_delete: true,
            viewer_can_moderate: false,
            viewer_can_report: false,
            reply_count: 0,
            reactions: [],
            mentions: [],
          },
          comment_count: counts.commentCount,
        });
      }
    }
  })
);
