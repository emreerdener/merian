const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isExplorePostId = (value: string) => uuid.test(value);
export type ExploreCursor = { sharedAt: string; postId: string };

export function decodeExploreCursor(
  value: string | null,
): ExploreCursor | null {
  if (value === null) return null;
  if (value.length > 256 || !/^[A-Za-z0-9_-]+$/.test(value)) {
    throw new Error("Invalid cursor");
  }
  const parsed = JSON.parse(Buffer.from(value, "base64url").toString("utf8"));
  if (
    !Array.isArray(parsed) || parsed.length !== 3 || parsed[0] !== 1 ||
    typeof parsed[1] !== "string" || typeof parsed[2] !== "string" ||
    !uuid.test(parsed[2]) ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/
      .test(parsed[1]) ||
    !Number.isFinite(Date.parse(parsed[1]))
  ) throw new Error("Invalid cursor");
  return { sharedAt: parsed[1], postId: parsed[2] };
}

export function encodeExploreCursor(cursor: ExploreCursor): string {
  // Preserve PostgreSQL microseconds; Date.toISOString would drop tie precision.
  return Buffer.from(JSON.stringify([1, cursor.sharedAt, cursor.postId]))
    .toString("base64url");
}
