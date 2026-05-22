import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export type ExploreFeedFilter = "recent" | "following" | "trending" | "nearby";

type NestedRelation<T> = T | T[] | null | undefined;

interface ExplorePostLookupRow {
  id: string;
  user_id: string;
  unshared_at: string | null;
  scan?: NestedRelation<
    {
      image_storage_urls?: string[] | null;
      is_tombstoned?: boolean | null;
      geoprivacy?: string | null;
    }
  >;
  author?: NestedRelation<{ is_shadowbanned?: boolean | null }>;
}

function relationValue<T>(value: NestedRelation<T>): T | undefined {
  if (Array.isArray(value)) return value[0];
  return value ?? undefined;
}

function makeHttpError(
  status: number,
  message: string,
): Error & { status: number } {
  const error = new Error(message) as Error & { status: number };
  error.status = status;
  return error;
}

export function requireUuid(value: unknown, fieldName: string): string {
  if (typeof value !== "string" || !UUID_RE.test(value)) {
    throw makeHttpError(400, `${fieldName} must be a valid UUID.`);
  }
  return value;
}

export function normalizeLimit(
  rawValue: unknown,
  fallback: number,
  maxValue: number,
): number {
  if (typeof rawValue !== "number" || !Number.isFinite(rawValue)) {
    return fallback;
  }
  return Math.max(0, Math.min(Math.floor(rawValue), maxValue));
}

export function normalizeOffset(rawValue: unknown): number {
  if (typeof rawValue !== "number" || !Number.isFinite(rawValue)) return 0;
  return Math.max(0, Math.floor(rawValue));
}

export function normalizeCursorTimestamp(
  rawValue: unknown,
  fieldName: string,
): string | null {
  if (rawValue == null) return null;
  if (typeof rawValue !== "string" || !Number.isFinite(Date.parse(rawValue))) {
    throw makeHttpError(
      400,
      `${fieldName} must be a valid ISO 8601 timestamp.`,
    );
  }

  return rawValue;
}

export function normalizeExploreHashtag(
  rawValue: unknown,
  fieldName: string,
): string {
  if (typeof rawValue !== "string") {
    throw makeHttpError(400, `${fieldName} must be a hashtag.`);
  }

  const normalized = rawValue
    .trim()
    .replace(/^#+/, "")
    .toLowerCase();

  if (!/^[a-z0-9][a-z0-9_]{1,39}$/.test(normalized)) {
    throw makeHttpError(
      400,
      `${fieldName} must be 2 to 40 letters, numbers, or underscores.`,
    );
  }

  return normalized;
}

export function normalizeExploreFeedFilter(
  rawValue: unknown,
): ExploreFeedFilter {
  if (rawValue == null) return "recent";
  if (
    rawValue === "recent" || rawValue === "following" ||
    rawValue === "trending" || rawValue === "nearby"
  ) {
    return rawValue;
  }

  throw makeHttpError(
    400,
    "filter must be one of: recent, following, trending, nearby.",
  );
}

export function normalizeNonNegativeInteger(
  rawValue: unknown,
  fieldName: string,
): number | null {
  if (rawValue == null) return null;
  if (
    typeof rawValue !== "number" || !Number.isInteger(rawValue) || rawValue < 0
  ) {
    throw makeHttpError(400, `${fieldName} must be a non-negative integer.`);
  }

  return rawValue;
}

export function normalizeLatitude(
  rawValue: unknown,
  fieldName: string,
): number | null {
  if (rawValue == null) return null;
  if (
    typeof rawValue !== "number" || !Number.isFinite(rawValue) ||
    rawValue < -90 || rawValue > 90
  ) {
    throw makeHttpError(400, `${fieldName} must be a valid latitude.`);
  }

  return rawValue;
}

export function normalizeLongitude(
  rawValue: unknown,
  fieldName: string,
): number | null {
  if (rawValue == null) return null;
  if (
    typeof rawValue !== "number" || !Number.isFinite(rawValue) ||
    rawValue < -180 || rawValue > 180
  ) {
    throw makeHttpError(400, `${fieldName} must be a valid longitude.`);
  }

  return rawValue;
}

export async function syncPublicAuthorIdentity(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc("refresh_public_author_identity", {
    target_user_id: userId,
  });

  if (error) {
    throw new Error(`Failed to sync public author identity: ${error.message}`);
  }
}

export async function syncPublicAuthorIdentityBestEffort(
  userId: string,
  supabaseAdmin: SupabaseClient,
  context: string,
): Promise<void> {
  try {
    await syncPublicAuthorIdentity(userId, supabaseAdmin);
  } catch (error) {
    console.warn("public_author_identity_sync_failed", {
      context,
      user_id: userId,
      error: error instanceof Error ? error.message : String(error),
    });
  }
}

export async function repairExplorePostOwnershipBestEffort(
  userId: string,
  supabaseAdmin: SupabaseClient,
  context: string,
): Promise<void> {
  const { error } = await supabaseAdmin.rpc(
    "repair_explore_post_ownership_for_user",
    {
      target_user_id: userId,
    },
  );

  if (error) {
    console.warn("explore_post_ownership_repair_failed", {
      context,
      user_id: userId,
      error: error.message,
    });
  }
}

export async function refreshExploreAuthorStateBestEffort(
  userId: string,
  supabaseAdmin: SupabaseClient,
  context: string,
): Promise<void> {
  await syncPublicAuthorIdentityBestEffort(userId, supabaseAdmin, context);
  await repairExplorePostOwnershipBestEffort(userId, supabaseAdmin, context);
}

export async function fetchPublicAuthorName(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<string> {
  const { data, error } = await supabaseAdmin
    .from("users")
    .select("public_author_name")
    .eq("id", userId)
    .single();

  if (error || !data?.public_author_name) {
    throw new Error(
      `Failed to fetch public author name: ${
        error?.message ?? "No name found"
      }`,
    );
  }

  return data.public_author_name as string;
}

export async function fetchPublicAuthorIdentity(
  userId: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ authorName: string; authorAvatarUrl: string | null }> {
  const { data, error } = await supabaseAdmin
    .from("users")
    .select("public_author_name,public_avatar_url")
    .eq("id", userId)
    .single();

  if (error || !data?.public_author_name) {
    throw new Error(
      `Failed to fetch public author identity: ${
        error?.message ?? "No identity found"
      }`,
    );
  }

  return {
    authorName: data.public_author_name as string,
    authorAvatarUrl: (data.public_avatar_url as string | null | undefined) ??
      null,
  };
}

export interface ExploreAuthorProBadgeProjection {
  author_user_id: string;
  author_is_pro?: boolean;
}

export interface ExplorePostHashtagProjection {
  post_id: string;
  hashtags?: string[];
}

interface ExploreAuthorProfileProBadgeProjection {
  author_user_id: string;
  author_is_pro?: boolean;
  preview_posts?: unknown[];
}

interface AuthorSubscriptionTierRow {
  id: string;
  subscription_tier: string | null;
}

interface ExplorePostHashtagRow {
  post_id: string;
  tag: string;
}

export async function withExplorePostHashtags<
  T extends ExplorePostHashtagProjection,
>(
  rows: T[],
  supabaseAdmin: SupabaseClient,
): Promise<Array<T & { hashtags: string[] }>> {
  const postIds = Array.from(
    new Set(
      rows
        .map((row) => row.post_id?.toLowerCase())
        .filter((id): id is string => Boolean(id)),
    ),
  );

  if (postIds.length === 0) {
    return rows.map((row) => ({ ...row, hashtags: [] }));
  }

  const { data, error } = await supabaseAdmin
    .from("explore_post_hashtags")
    .select("post_id,tag")
    .in("post_id", postIds)
    .order("tag", { ascending: true });

  if (error) {
    throw new Error(`Failed to fetch Explore post hashtags: ${error.message}`);
  }

  const hashtagsByPostId = new Map<string, string[]>();
  for (const row of (data ?? []) as ExplorePostHashtagRow[]) {
    const normalizedPostId = row.post_id.toLowerCase();
    const tags = hashtagsByPostId.get(normalizedPostId) ?? [];
    tags.push(row.tag);
    hashtagsByPostId.set(normalizedPostId, tags);
  }

  return rows.map((row) => ({
    ...row,
    hashtags: hashtagsByPostId.get(row.post_id.toLowerCase()) ?? [],
  }));
}

export async function withExploreAuthorProBadges<
  T extends ExploreAuthorProBadgeProjection,
>(
  rows: T[],
  supabaseAdmin: SupabaseClient,
): Promise<Array<T & { author_is_pro: boolean }>> {
  const authorIds = Array.from(
    new Set(
      rows
        .map((row) => row.author_user_id?.toLowerCase())
        .filter((id): id is string => Boolean(id)),
    ),
  );

  if (authorIds.length === 0) {
    return rows.map((row) => ({ ...row, author_is_pro: false }));
  }

  const { data, error } = await supabaseAdmin
    .from("users")
    .select("id,subscription_tier")
    .in("id", authorIds);

  if (error) {
    throw new Error(
      `Failed to fetch Explore author pro state: ${error.message}`,
    );
  }

  const proAuthorIds = new Set(
    ((data ?? []) as AuthorSubscriptionTierRow[])
      .filter((row) => row.subscription_tier === "pro")
      .map((row) => row.id.toLowerCase()),
  );

  return rows.map((row) => ({
    ...row,
    author_is_pro: proAuthorIds.has(row.author_user_id.toLowerCase()),
  }));
}

export async function withExploreAuthorProfileProBadge<
  T extends ExploreAuthorProfileProBadgeProjection,
>(
  profile: T,
  supabaseAdmin: SupabaseClient,
): Promise<T & { author_is_pro: boolean; preview_posts?: unknown[] }> {
  const [authorProjection] = await withExploreAuthorProBadges(
    [{ author_user_id: profile.author_user_id }],
    supabaseAdmin,
  );
  const previewPosts = Array.isArray(profile.preview_posts)
    ? await withExploreAuthorProBadges(
      profile.preview_posts as ExploreAuthorProBadgeProjection[],
      supabaseAdmin,
    )
    : profile.preview_posts;

  return {
    ...profile,
    author_is_pro: authorProjection.author_is_pro,
    preview_posts: previewPosts,
  };
}

export async function hasMutualBlock(
  userId: string,
  otherUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from("user_blocks")
    .select("blocker_id, blocked_id")
    .or(
      `and(blocker_id.eq.${userId},blocked_id.eq.${otherUserId}),and(blocker_id.eq.${otherUserId},blocked_id.eq.${userId})`,
    )
    .limit(1);

  if (error) {
    throw new Error(`Failed to resolve block state: ${error.message}`);
  }

  return (data?.length ?? 0) > 0;
}

export async function fetchInteractiveExplorePost(
  postId: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ id: string; ownerUserId: string }> {
  const { data, error } = await supabaseAdmin
    .from("explore_posts")
    .select(`
      id,
      user_id,
      unshared_at,
      scan:scans!inner(image_storage_urls,is_tombstoned,geoprivacy),
      author:users!explore_posts_user_id_fkey!inner(is_shadowbanned)
    `)
    .eq("id", postId)
    .single();

  if (error || !data) {
    throw makeHttpError(
      404,
      error
        ? `DB Error: ${error.message} - ${error.details || ""}`
        : "Explore post not found.",
    );
  }

  const typedRow = data as ExplorePostLookupRow;
  const scan = relationValue(typedRow.scan);
  const author = relationValue(typedRow.author);
  const imageUrls = scan?.image_storage_urls ?? [];

  if (typedRow.unshared_at != null) {
    throw makeHttpError(404, "Explore post is no longer shared.");
  }

  if (scan?.is_tombstoned) {
    throw makeHttpError(404, "Explore post is no longer available.");
  }

  if ((imageUrls?.length ?? 0) == 0) {
    throw makeHttpError(404, "Explore post is no longer available.");
  }

  if (scan?.geoprivacy === "private") {
    throw makeHttpError(404, "Explore post is no longer available.");
  }

  if (author?.is_shadowbanned) {
    throw makeHttpError(404, "Explore post is no longer available.");
  }

  return { id: typedRow.id, ownerUserId: typedRow.user_id };
}

export async function assertCanInteractWithExplorePost(
  postId: string,
  requesterUserId: string,
  supabaseAdmin: SupabaseClient,
): Promise<{ id: string; ownerUserId: string }> {
  const post = await fetchInteractiveExplorePost(postId, supabaseAdmin);

  if (
    post.ownerUserId !== requesterUserId &&
    await hasMutualBlock(requesterUserId, post.ownerUserId, supabaseAdmin)
  ) {
    throw makeHttpError(403, "You cannot interact with this Explore post.");
  }

  return post;
}
