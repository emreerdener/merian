import { SupabaseClient } from "@supabase/supabase-js";

export interface FieldTripCommentRow {
  comment_id: string;
  post_id: string;
  parent_comment_id?: string | null;
  author_user_id: string;
  author_name: string;
  author_username?: string | null;
  author_avatar_url?: string | null;
  body: string;
  created_at: string;
  viewer_can_delete: boolean;
  viewer_can_moderate: boolean;
  viewer_can_report: boolean;
  reply_count?: number;
  reactions: unknown[] | null;
  mentions?: unknown[] | null;
}

export interface InsertedFieldTripComment {
  id: string;
  publication_id: string;
  parent_comment_id?: string | null;
  created_at: string;
}

export interface FieldTripCommentParent {
  id: string;
  publication_id: string;
  user_id: string;
  parent_comment_id?: string | null;
  deleted_at?: string | null;
  moderated_at?: string | null;
}

export interface FieldTripChallengeCommentParent {
  id: string;
  entry_id: string;
  user_id: string;
  parent_comment_id?: string | null;
  deleted_at?: string | null;
  moderated_at?: string | null;
}

export interface InsertedFieldTripChallengeComment {
  id: string;
  entry_id: string;
  parent_comment_id?: string | null;
  created_at: string;
}

export interface FirstFieldTripAchievementProgress {
  kind: "standard_outing" | "seasonal_challenge";
  completed_at: string;
  template_slug: string | null;
  challenge_id: string | null;
}

function parseFirstFieldTripAchievementProgress(
  value: unknown,
): FirstFieldTripAchievementProgress | null {
  if (!isRecord(value)) return null;

  const kind = value.kind;
  const completedAt = value.completed_at;
  if (
    (kind !== "standard_outing" && kind !== "seasonal_challenge") ||
    typeof completedAt !== "string"
  ) {
    throw new Error("Invalid first Field trip achievement progress payload.");
  }

  return {
    kind,
    completed_at: completedAt,
    template_slug: typeof value.template_slug === "string"
      ? value.template_slug
      : null,
    challenge_id: typeof value.challenge_id === "string"
      ? value.challenge_id
      : null,
  };
}

interface StoppedFieldTripProgressRow {
  template_id: string;
  stopped_progress: unknown;
  levels: unknown[];
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mergeStoppedFieldTripProgress(
  template: unknown,
  stoppedRows: StoppedFieldTripProgressRow[],
): unknown {
  if (!isRecord(template) || typeof template.template_id !== "string") {
    return template;
  }

  const stopped = stoppedRows.find((row) =>
    row.template_id === template.template_id
  );
  if (!stopped) return template;

  return {
    ...template,
    stopped_progress: stopped.stopped_progress,
    levels: stopped.levels,
  };
}

async function fetchStoppedFieldTripProgress(
  userId: string,
  templateId: string | null,
  slug: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<StoppedFieldTripProgressRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_stopped_field_trip_progress",
    {
      self_id: userId,
      target_template_id: templateId,
      target_slug: slug,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch stopped Field trip progress: ${error.message}`,
    );
  }

  return Array.isArray(data) ? data as StoppedFieldTripProgressRow[] : [];
}

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export async function fetchFieldTripCatalog(
  userId: string,
  userRegion: string | null,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<unknown[]> {
  const [{ data, error }, stoppedRows] = await Promise.all([
    supabaseAdmin.rpc("get_field_trip_catalog", {
      self_id: userId,
      user_region: userRegion,
      max_limit: limit,
    }),
    fetchStoppedFieldTripProgress(userId, null, null, supabaseAdmin),
  ]);

  if (error) {
    throw new Error(`Failed to fetch Field trip catalog: ${error.message}`);
  }

  return Array.isArray(data)
    ? data.map((template) =>
      mergeStoppedFieldTripProgress(template, stoppedRows)
    )
    : [];
}

export async function fetchFieldTripCaptureContext(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<unknown[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_capture_context",
    { self_id: userId },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip capture context: ${error.message}`,
    );
  }

  return Array.isArray(data) ? data : [];
}

export async function fetchFieldTripTemplateDetail(
  userId: string,
  templateId: string | null,
  slug: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<unknown | null> {
  const [{ data, error }, stoppedRows] = await Promise.all([
    supabaseAdmin.rpc(
      "get_field_trip_template_detail",
      {
        self_id: userId,
        target_template_id: templateId,
        target_slug: slug,
      },
    ),
    fetchStoppedFieldTripProgress(
      userId,
      templateId,
      slug,
      supabaseAdmin,
    ),
  ]);

  if (error) {
    throw new Error(
      `Failed to fetch Field trip template: ${error.message}`,
    );
  }

  return data == null ? null : mergeStoppedFieldTripProgress(data, stoppedRows);
}

export async function startFieldTrip(
  userId: string,
  templateId: string,
  supabaseAdmin: SupabaseClient,
): Promise<unknown> {
  const { data, error } = await supabaseAdmin.rpc("start_field_trip", {
    self_id: userId,
    target_template_id: templateId,
  });

  if (error) {
    throw new Error(`Failed to start Field trip: ${error.message}`);
  }

  if (!data) {
    throw new Error("Failed to start Field trip: missing template detail.");
  }

  return data;
}

export async function stopFieldTrip(
  userId: string,
  userFieldTripId: string,
  supabaseAdmin: SupabaseClient,
): Promise<unknown> {
  const { data: templateId, error } = await supabaseAdmin.rpc(
    "stop_field_trip",
    {
      self_id: userId,
      target_user_field_trip_id: userFieldTripId,
    },
  );

  if (error) {
    throw new Error(`Failed to stop Field trip: ${error.message}`);
  }
  if (typeof templateId !== "string") {
    throw new Error("Failed to stop Field trip: missing template id.");
  }

  const detail = await fetchFieldTripTemplateDetail(
    userId,
    templateId,
    null,
    supabaseAdmin,
  );
  if (!detail) {
    throw new Error("Failed to stop Field trip: missing template detail.");
  }
  return detail;
}

export async function resetFieldTrip(
  userId: string,
  userFieldTripId: string,
  supabaseAdmin: SupabaseClient,
): Promise<unknown> {
  const { data: templateId, error } = await supabaseAdmin.rpc(
    "reset_field_trip",
    {
      self_id: userId,
      target_user_field_trip_id: userFieldTripId,
    },
  );

  if (error) {
    throw new Error(`Failed to reset Field trip: ${error.message}`);
  }
  if (typeof templateId !== "string") {
    throw new Error("Failed to reset Field trip: missing template id.");
  }

  const detail = await fetchFieldTripTemplateDetail(
    userId,
    templateId,
    null,
    supabaseAdmin,
  );
  if (!detail) {
    throw new Error("Failed to reset Field trip: missing template detail.");
  }
  return detail;
}

export async function applyFieldTripScanProgress(
  userId: string,
  scanId: string,
  preferredGoal: {
    userFieldTripId: string;
    itemId: string;
  } | null,
  supabaseAdmin: SupabaseClient,
): Promise<{
  fieldTripUpdates: unknown[];
  challengeUpdates: unknown[];
  firstFieldTripAchievement: FirstFieldTripAchievementProgress | null;
  firstFieldTripAchievementNewlyUnlocked: boolean;
}> {
  const { data, error } = await supabaseAdmin.rpc(
    "apply_field_trip_scan_progress_atomic",
    {
      self_id: userId,
      target_scan_id: scanId,
      preferred_user_field_trip_id: preferredGoal?.userFieldTripId ?? null,
      preferred_item_id: preferredGoal?.itemId ?? null,
    },
  );

  if (error) {
    throw new Error(`Failed to update Field trip progress: ${error.message}`);
  }

  if (!isRecord(data)) {
    throw new Error("Invalid atomic Field trip progress payload.");
  }

  const fieldTripUpdates = Array.isArray(data.field_trip_updates)
    ? data.field_trip_updates
    : [];
  const challengeUpdates = Array.isArray(data.challenge_updates)
    ? data.challenge_updates
    : [];
  const firstFieldTripAchievement = parseFirstFieldTripAchievementProgress(
    data.first_field_trip_achievement,
  );

  return {
    fieldTripUpdates,
    challengeUpdates,
    firstFieldTripAchievement,
    firstFieldTripAchievementNewlyUnlocked:
      data.first_field_trip_achievement_newly_unlocked === true,
  };
}

export async function fetchFieldTripScanContributions(
  userId: string,
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<unknown[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_scan_contributions",
    {
      self_id: userId,
      target_scan_id: scanId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip scan contributions: ${error.message}`,
    );
  }

  return Array.isArray(data) ? data : [];
}

export async function fetchFirstFieldTripAchievementProgress(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<FirstFieldTripAchievementProgress | null> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_first_field_trip_achievement_progress",
    { target_user_id: userId },
  );

  if (error) {
    throw new Error(
      `Failed to fetch first Field trip achievement progress: ${error.message}`,
    );
  }

  return parseFirstFieldTripAchievementProgress(data);
}

export async function fetchRecentFieldTripPublications(
  userId: string,
  userRegion: string | null,
  habitatTags: string[],
  limit: number,
  cursor: {
    beforePublishedAt: string | null;
    beforePublicationId: string | null;
  },
  supabaseAdmin: SupabaseClient,
): Promise<unknown[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_recent_field_trip_publications",
    {
      self_id: userId,
      user_region: userRegion,
      viewer_habitat_tags: habitatTags,
      max_limit: limit,
      before_published_at: cursor.beforePublishedAt,
      before_publication_id: cursor.beforePublicationId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch recent Field trips: ${error.message}`,
    );
  }

  return Array.isArray(data) ? data : [];
}

export async function fetchCommunityFieldTripPublications(
  userId: string,
  mode: "smart" | "following" | "recent",
  templateId: string | null,
  userRegion: string | null,
  habitatTags: string[],
  seasonTags: string[],
  limit: number,
  cursor: {
    beforeRankBucket: number | null;
    beforePublishedAt: string | null;
    beforePublicationId: string | null;
  },
  supabaseAdmin: SupabaseClient,
): Promise<unknown[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_community_publications",
    {
      self_id: userId,
      mode,
      target_template_id: templateId,
      user_region: userRegion,
      viewer_habitat_tags: habitatTags,
      viewer_season_tags: seasonTags,
      max_limit: limit,
      before_rank_bucket: cursor.beforeRankBucket,
      before_published_at: cursor.beforePublishedAt,
      before_publication_id: cursor.beforePublicationId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip community publications: ${error.message}`,
    );
  }

  return Array.isArray(data) ? data : [];
}

export async function fetchFieldTripProfileSummaries(
  userId: string,
  authorUserId: string,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<unknown> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_profile_summaries",
    {
      self_id: userId,
      target_author_user_id: authorUserId,
      max_limit: limit,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip profile summaries: ${error.message}`,
    );
  }

  const basePayload = data != null && typeof data === "object"
    ? data as Record<string, unknown>
    : { active: [], pinned: [], published: [] };

  const { data: badgesData, error: badgesError } = await supabaseAdmin.rpc(
    "get_field_trip_challenge_badges",
    {
      self_id: userId,
      target_author_user_id: authorUserId,
      max_limit: limit,
    },
  );

  if (badgesError) {
    throw new Error(
      `Failed to fetch Field trip challenge badges: ${badgesError.message}`,
    );
  }

  return {
    ...basePayload,
    challenge_badges: Array.isArray(badgesData) ? badgesData : [],
  };
}

export async function setPinnedFieldTripPublications(
  userId: string,
  publicationIds: string[],
  supabaseAdmin: SupabaseClient,
): Promise<unknown> {
  const { data, error } = await supabaseAdmin.rpc(
    "set_field_trip_pinned_publications",
    {
      self_id: userId,
      publication_ids: publicationIds,
    },
  );

  if (error) {
    throw new Error(`Failed to update pinned Field trips: ${error.message}`);
  }

  return data ?? { active: [], pinned: [], published: [] };
}

export async function fetchFieldTripPublicationDetail(
  userId: string,
  publicationId: string,
  supabaseAdmin: SupabaseClient,
): Promise<unknown | null> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_publication_detail",
    {
      self_id: userId,
      target_publication_id: publicationId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip publication: ${error.message}`,
    );
  }

  return data ?? null;
}

export async function publishFieldTrip(
  userId: string,
  userFieldTripId: string,
  title: string | null,
  description: string | null,
  aiSummary: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<unknown> {
  const { data, error } = await supabaseAdmin.rpc("publish_field_trip", {
    self_id: userId,
    target_user_field_trip_id: userFieldTripId,
    publication_title: title,
    publication_description: description,
    publication_ai_summary: aiSummary,
  });

  if (error) {
    throw new Error(`Failed to publish Field trip: ${error.message}`);
  }

  const publicationId = typeof data === "object" && data != null &&
      "publication_id" in data
    ? String((data as Record<string, unknown>).publication_id)
    : null;
  if (!publicationId) {
    throw new Error("Failed to publish Field trip: missing publication id.");
  }

  const detail = await fetchFieldTripPublicationDetail(
    userId,
    publicationId,
    supabaseAdmin,
  );
  if (!detail) {
    throw new Error("Failed to publish Field trip: publication not visible.");
  }
  return detail;
}

export async function assertCanViewFieldTripPublication(
  userId: string,
  publicationId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc(
    "can_view_field_trip_publication",
    {
      self_id: userId,
      target_publication_id: publicationId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to resolve Field trip visibility: ${error.message}`,
    );
  }

  if (data !== true) {
    throw makeHttpError(404, "Field trip publication not found.");
  }
}

export async function setFieldTripLike(
  publicationId: string,
  userId: string,
  liked: boolean,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  if (liked) {
    const { error } = await supabaseAdmin
      .from("field_trip_publication_likes")
      .upsert(
        { publication_id: publicationId, user_id: userId },
        { onConflict: "publication_id,user_id", ignoreDuplicates: true },
      );

    if (error) {
      throw new Error(`Failed to like Field trip: ${error.message}`);
    }
    return;
  }

  const { error } = await supabaseAdmin
    .from("field_trip_publication_likes")
    .delete()
    .eq("publication_id", publicationId)
    .eq("user_id", userId);

  if (error) {
    throw new Error(`Failed to unlike Field trip: ${error.message}`);
  }
}

export async function fetchFieldTripPublicationCounts(
  publicationId: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ likeCount: number; commentCount: number }> {
  const { data, error } = await supabaseAdmin
    .from("field_trip_publications")
    .select("like_count,comment_count")
    .eq("id", publicationId)
    .single();

  if (error || !data) {
    throw new Error(
      `Failed to fetch Field trip counts: ${error?.message ?? "No data"}`,
    );
  }

  return {
    likeCount: Number(data.like_count ?? 0),
    commentCount: Number(data.comment_count ?? 0),
  };
}

export async function fetchFieldTripComments(
  userId: string,
  publicationId: string,
  limit: number,
  cursor: { afterCreatedAt: string | null; afterCommentId: string | null },
  supabaseAdmin: SupabaseClient,
): Promise<FieldTripCommentRow[]> {
  const { data, error } = await supabaseAdmin.rpc("get_field_trip_comments", {
    self_id: userId,
    target_publication_id: publicationId,
    max_limit: limit,
    after_created_at: cursor.afterCreatedAt,
    after_comment_id: cursor.afterCommentId,
  });

  if (error) {
    throw new Error(`Failed to fetch Field trip comments: ${error.message}`);
  }

  return (data ?? []) as FieldTripCommentRow[];
}

export async function fetchFieldTripCommentParent(
  parentCommentId: string,
  publicationId: string,
  supabaseAdmin: SupabaseClient,
): Promise<FieldTripCommentParent> {
  const { data, error } = await supabaseAdmin
    .from("field_trip_publication_comments")
    .select(
      "id,publication_id,user_id,parent_comment_id,deleted_at,moderated_at",
    )
    .eq("id", parentCommentId)
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Field trip parent comment not found.");
  }

  const parent = data as FieldTripCommentParent;
  if (parent.publication_id !== publicationId) {
    throw makeHttpError(
      400,
      "parent_comment_id must belong to the same Field trip.",
    );
  }
  if (parent.parent_comment_id != null) {
    throw makeHttpError(400, "Replies can only target top-level comments.");
  }
  if (parent.deleted_at != null || parent.moderated_at != null) {
    throw makeHttpError(
      404,
      "Field trip parent comment is no longer available.",
    );
  }

  return parent;
}

export async function insertFieldTripComment(
  publicationId: string,
  userId: string,
  body: string,
  parentCommentId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<InsertedFieldTripComment> {
  const { data, error } = await supabaseAdmin
    .from("field_trip_publication_comments")
    .insert({
      publication_id: publicationId,
      user_id: userId,
      body,
      parent_comment_id: parentCommentId,
    })
    .select("id,publication_id,parent_comment_id,created_at")
    .single();

  if (error || !data) {
    throw new Error(
      `Failed to create Field trip comment: ${
        error?.message ?? "Unknown error"
      }`,
    );
  }

  return data as InsertedFieldTripComment;
}

export async function fetchFieldTripChallengesCatalog(
  userId: string,
  userRegion: string | null,
  limit: number,
  supabaseAdmin: SupabaseClient,
): Promise<unknown[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_challenges_catalog",
    {
      self_id: userId,
      user_region: userRegion,
      max_limit: limit,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip challenges: ${error.message}`,
    );
  }

  return Array.isArray(data) ? data : [];
}

export async function fetchFieldTripChallengeDetail(
  userId: string,
  challengeId: string | null,
  slug: string | null,
  entriesLimit: number,
  supabaseAdmin: SupabaseClient,
): Promise<unknown | null> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_challenge_detail",
    {
      self_id: userId,
      target_challenge_id: challengeId,
      target_slug: slug,
      entries_limit: entriesLimit,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip challenge: ${error.message}`,
    );
  }

  return data ?? null;
}

export async function joinFieldTripChallenge(
  userId: string,
  challengeId: string,
  supabaseAdmin: SupabaseClient,
): Promise<unknown> {
  const { data, error } = await supabaseAdmin.rpc(
    "join_field_trip_challenge",
    {
      self_id: userId,
      target_challenge_id: challengeId,
    },
  );

  if (error) {
    throw new Error(`Failed to join Field trip challenge: ${error.message}`);
  }

  if (!data) {
    throw new Error("Failed to join Field trip challenge: missing detail.");
  }

  return data;
}

export async function fetchFieldTripChallengePublications(
  userId: string,
  challengeId: string,
  limit: number,
  cursor: {
    beforePublishedAt: string | null;
    beforeEntryId: string | null;
  },
  supabaseAdmin: SupabaseClient,
): Promise<unknown[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_challenge_publications",
    {
      self_id: userId,
      target_challenge_id: challengeId,
      max_limit: limit,
      before_published_at: cursor.beforePublishedAt,
      before_entry_id: cursor.beforeEntryId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip challenge entries: ${error.message}`,
    );
  }

  return Array.isArray(data) ? data : [];
}

export async function fetchFieldTripChallengeHashtagsForScan(
  userId: string,
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<string[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_challenge_hashtags_for_scan",
    {
      self_id: userId,
      target_scan_id: scanId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip challenge hashtags: ${error.message}`,
    );
  }

  return Array.isArray(data)
    ? data.filter((value): value is string => typeof value === "string")
    : [];
}

export async function fetchFieldTripChallengeEntryDetail(
  userId: string,
  entryId: string,
  supabaseAdmin: SupabaseClient,
): Promise<unknown | null> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_challenge_entry_detail",
    {
      self_id: userId,
      target_entry_id: entryId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip challenge entry: ${error.message}`,
    );
  }

  return data ?? null;
}

export async function publishFieldTripChallengeEntry(
  userId: string,
  participationId: string,
  title: string | null,
  description: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<unknown> {
  const { data, error } = await supabaseAdmin.rpc(
    "publish_field_trip_challenge_entry",
    {
      self_id: userId,
      target_participation_id: participationId,
      entry_title: title,
      entry_description: description,
    },
  );

  if (error) {
    throw new Error(
      `Failed to publish Field trip challenge entry: ${error.message}`,
    );
  }

  const entryId = typeof data === "object" && data != null && "entry_id" in data
    ? String((data as Record<string, unknown>).entry_id)
    : null;
  if (!entryId) {
    throw new Error(
      "Failed to publish Field trip challenge entry: missing entry id.",
    );
  }

  const detail = await fetchFieldTripChallengeEntryDetail(
    userId,
    entryId,
    supabaseAdmin,
  );
  if (!detail) {
    throw new Error(
      "Failed to publish Field trip challenge entry: entry not visible.",
    );
  }
  return detail;
}

export async function assertCanViewFieldTripChallengeEntry(
  userId: string,
  entryId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { data, error } = await supabaseAdmin.rpc(
    "can_view_field_trip_challenge_entry",
    {
      self_id: userId,
      target_entry_id: entryId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to resolve Field trip challenge visibility: ${error.message}`,
    );
  }

  if (data !== true) {
    throw makeHttpError(404, "Field trip challenge entry not found.");
  }
}

export async function setFieldTripChallengeEntryLike(
  entryId: string,
  userId: string,
  liked: boolean,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  if (liked) {
    const { error } = await supabaseAdmin
      .from("field_trip_challenge_entry_likes")
      .upsert(
        { entry_id: entryId, user_id: userId },
        { onConflict: "entry_id,user_id", ignoreDuplicates: true },
      );

    if (error) {
      throw new Error(
        `Failed to like Field trip challenge entry: ${error.message}`,
      );
    }
    return;
  }

  const { error } = await supabaseAdmin
    .from("field_trip_challenge_entry_likes")
    .delete()
    .eq("entry_id", entryId)
    .eq("user_id", userId);

  if (error) {
    throw new Error(
      `Failed to unlike Field trip challenge entry: ${error.message}`,
    );
  }
}

export async function fetchFieldTripChallengeEntryCounts(
  entryId: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ likeCount: number; commentCount: number }> {
  const { data, error } = await supabaseAdmin
    .from("field_trip_challenge_entries")
    .select("like_count,comment_count")
    .eq("id", entryId)
    .single();

  if (error || !data) {
    throw new Error(
      `Failed to fetch Field trip challenge entry counts: ${
        error?.message ?? "No data"
      }`,
    );
  }

  return {
    likeCount: Number(data.like_count ?? 0),
    commentCount: Number(data.comment_count ?? 0),
  };
}

export async function fetchFieldTripChallengeEntryComments(
  userId: string,
  entryId: string,
  limit: number,
  cursor: { afterCreatedAt: string | null; afterCommentId: string | null },
  supabaseAdmin: SupabaseClient,
): Promise<FieldTripCommentRow[]> {
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_challenge_entry_comments",
    {
      self_id: userId,
      target_entry_id: entryId,
      max_limit: limit,
      after_created_at: cursor.afterCreatedAt,
      after_comment_id: cursor.afterCommentId,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field trip challenge entry comments: ${error.message}`,
    );
  }

  return (data ?? []) as FieldTripCommentRow[];
}

export async function fetchFieldTripChallengeCommentParent(
  parentCommentId: string,
  entryId: string,
  supabaseAdmin: SupabaseClient,
): Promise<FieldTripChallengeCommentParent> {
  const { data, error } = await supabaseAdmin
    .from("field_trip_challenge_entry_comments")
    .select("id,entry_id,user_id,parent_comment_id,deleted_at,moderated_at")
    .eq("id", parentCommentId)
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Field trip challenge parent comment not found.");
  }

  const parent = data as FieldTripChallengeCommentParent;
  if (parent.entry_id !== entryId) {
    throw makeHttpError(
      400,
      "parent_comment_id must belong to the same Field trip challenge entry.",
    );
  }
  if (parent.parent_comment_id != null) {
    throw makeHttpError(400, "Replies can only target top-level comments.");
  }
  if (parent.deleted_at != null || parent.moderated_at != null) {
    throw makeHttpError(
      404,
      "Field trip challenge parent comment is no longer available.",
    );
  }

  return parent;
}

export async function insertFieldTripChallengeEntryComment(
  entryId: string,
  userId: string,
  body: string,
  parentCommentId: string | null,
  supabaseAdmin: SupabaseClient,
): Promise<InsertedFieldTripChallengeComment> {
  const { data, error } = await supabaseAdmin
    .from("field_trip_challenge_entry_comments")
    .insert({
      entry_id: entryId,
      user_id: userId,
      body,
      parent_comment_id: parentCommentId,
    })
    .select("id,entry_id,parent_comment_id,created_at")
    .single();

  if (error || !data) {
    throw new Error(
      `Failed to create Field trip challenge entry comment: ${
        error?.message ?? "Unknown error"
      }`,
    );
  }

  return data as InsertedFieldTripChallengeComment;
}
