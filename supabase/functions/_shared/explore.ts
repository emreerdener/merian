import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

type NestedRelation<T> = T | T[] | null | undefined;

interface ExplorePostLookupRow {
  id: string;
  user_id: string;
  unshared_at: string | null;
  scan?: NestedRelation<{ image_storage_urls?: string[] | null; is_tombstoned?: boolean | null; geoprivacy?: string | null }>;
  author?: NestedRelation<{ is_shadowbanned?: boolean | null }>;
}

function relationValue<T>(value: NestedRelation<T>): T | undefined {
  if (Array.isArray(value)) return value[0];
  return value ?? undefined;
}

function makeHttpError(status: number, message: string): Error & { status: number } {
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

export function normalizeLimit(rawValue: unknown, fallback: number, maxValue: number): number {
  if (typeof rawValue !== "number" || !Number.isFinite(rawValue)) return fallback;
  return Math.max(0, Math.min(Math.floor(rawValue), maxValue));
}

export function normalizeOffset(rawValue: unknown): number {
  if (typeof rawValue !== "number" || !Number.isFinite(rawValue)) return 0;
  return Math.max(0, Math.floor(rawValue));
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
    throw new Error(`Failed to fetch public author name: ${error?.message ?? "No name found"}`);
  }

  return data.public_author_name as string;
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
      author:users!inner(is_shadowbanned)
    `)
    .eq("id", postId)
    .single();

  if (error || !data) {
    throw makeHttpError(404, "Explore post not found.");
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
