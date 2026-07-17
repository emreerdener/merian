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
  const { data, error } = await supabaseAdmin.rpc("get_field_trip_catalog", {
    self_id: userId,
    user_region: userRegion,
    max_limit: limit,
  });

  if (error) {
    throw new Error(`Failed to fetch Field Trip catalog: ${error.message}`);
  }

  return Array.isArray(data) ? data : [];
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
      `Failed to fetch Field Trip capture context: ${error.message}`,
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
  const { data, error } = await supabaseAdmin.rpc(
    "get_field_trip_template_detail",
    {
      self_id: userId,
      target_template_id: templateId,
      target_slug: slug,
    },
  );

  if (error) {
    throw new Error(
      `Failed to fetch Field Trip template: ${error.message}`,
    );
  }

  return data ?? null;
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
    throw new Error(`Failed to start Field Trip: ${error.message}`);
  }

  if (!data) {
    throw new Error("Failed to start Field Trip: missing template detail.");
  }

  return data;
}

export async function applyFieldTripScanProgress(
  userId: string,
  scanId: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ fieldTripUpdates: unknown[]; challengeUpdates: unknown[] }> {
  const { data, error } = await supabaseAdmin.rpc(
    "apply_field_trip_scan_progress",
    {
      self_id: userId,
      target_scan_id: scanId,
    },
  );

  if (error) {
    throw new Error(`Failed to update Field Trip progress: ${error.message}`);
  }

  const { data: challengeData, error: challengeError } = await supabaseAdmin
    .rpc(
      "apply_field_trip_challenge_scan_progress",
      {
        self_id: userId,
        target_scan_id: scanId,
      },
    );

  if (challengeError) {
    throw new Error(
      `Failed to update Field Trip challenge progress: ${challengeError.message}`,
    );
  }

  return {
    fieldTripUpdates: Array.isArray(data) ? data : [],
    challengeUpdates: Array.isArray(challengeData) ? challengeData : [],
  };
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
      `Failed to fetch recent Field Trips: ${error.message}`,
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
      `Failed to fetch Field Trip community publications: ${error.message}`,
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
      `Failed to fetch Field Trip profile summaries: ${error.message}`,
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
      `Failed to fetch Field Trip challenge badges: ${badgesError.message}`,
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
    throw new Error(`Failed to update pinned Field Trips: ${error.message}`);
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
      `Failed to fetch Field Trip publication: ${error.message}`,
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
    throw new Error(`Failed to publish Field Trip: ${error.message}`);
  }

  const publicationId = typeof data === "object" && data != null &&
      "publication_id" in data
    ? String((data as Record<string, unknown>).publication_id)
    : null;
  if (!publicationId) {
    throw new Error("Failed to publish Field Trip: missing publication id.");
  }

  const detail = await fetchFieldTripPublicationDetail(
    userId,
    publicationId,
    supabaseAdmin,
  );
  if (!detail) {
    throw new Error("Failed to publish Field Trip: publication not visible.");
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
      `Failed to resolve Field Trip visibility: ${error.message}`,
    );
  }

  if (data !== true) {
    throw makeHttpError(404, "Field Trip publication not found.");
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
      throw new Error(`Failed to like Field Trip: ${error.message}`);
    }
    return;
  }

  const { error } = await supabaseAdmin
    .from("field_trip_publication_likes")
    .delete()
    .eq("publication_id", publicationId)
    .eq("user_id", userId);

  if (error) {
    throw new Error(`Failed to unlike Field Trip: ${error.message}`);
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
      `Failed to fetch Field Trip counts: ${error?.message ?? "No data"}`,
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
    throw new Error(`Failed to fetch Field Trip comments: ${error.message}`);
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
    throw makeHttpError(404, "Field Trip parent comment not found.");
  }

  const parent = data as FieldTripCommentParent;
  if (parent.publication_id !== publicationId) {
    throw makeHttpError(
      400,
      "parent_comment_id must belong to the same Field Trip.",
    );
  }
  if (parent.parent_comment_id != null) {
    throw makeHttpError(400, "Replies can only target top-level comments.");
  }
  if (parent.deleted_at != null || parent.moderated_at != null) {
    throw makeHttpError(
      404,
      "Field Trip parent comment is no longer available.",
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
      `Failed to create Field Trip comment: ${
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
      `Failed to fetch Field Trip challenges: ${error.message}`,
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
      `Failed to fetch Field Trip challenge: ${error.message}`,
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
    throw new Error(`Failed to join Field Trip challenge: ${error.message}`);
  }

  if (!data) {
    throw new Error("Failed to join Field Trip challenge: missing detail.");
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
      `Failed to fetch Field Trip challenge entries: ${error.message}`,
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
      `Failed to fetch Field Trip challenge hashtags: ${error.message}`,
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
      `Failed to fetch Field Trip challenge entry: ${error.message}`,
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
      `Failed to publish Field Trip challenge entry: ${error.message}`,
    );
  }

  const entryId = typeof data === "object" && data != null && "entry_id" in data
    ? String((data as Record<string, unknown>).entry_id)
    : null;
  if (!entryId) {
    throw new Error(
      "Failed to publish Field Trip challenge entry: missing entry id.",
    );
  }

  const detail = await fetchFieldTripChallengeEntryDetail(
    userId,
    entryId,
    supabaseAdmin,
  );
  if (!detail) {
    throw new Error(
      "Failed to publish Field Trip challenge entry: entry not visible.",
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
      `Failed to resolve Field Trip challenge visibility: ${error.message}`,
    );
  }

  if (data !== true) {
    throw makeHttpError(404, "Field Trip challenge entry not found.");
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
        `Failed to like Field Trip challenge entry: ${error.message}`,
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
      `Failed to unlike Field Trip challenge entry: ${error.message}`,
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
      `Failed to fetch Field Trip challenge entry counts: ${
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
      `Failed to fetch Field Trip challenge entry comments: ${error.message}`,
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
    throw makeHttpError(404, "Field Trip challenge parent comment not found.");
  }

  const parent = data as FieldTripChallengeCommentParent;
  if (parent.entry_id !== entryId) {
    throw makeHttpError(
      400,
      "parent_comment_id must belong to the same Field Trip challenge entry.",
    );
  }
  if (parent.parent_comment_id != null) {
    throw makeHttpError(400, "Replies can only target top-level comments.");
  }
  if (parent.deleted_at != null || parent.moderated_at != null) {
    throw makeHttpError(
      404,
      "Field Trip challenge parent comment is no longer available.",
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
      `Failed to create Field Trip challenge entry comment: ${
        error?.message ?? "Unknown error"
      }`,
    );
  }

  return data as InsertedFieldTripChallengeComment;
}
