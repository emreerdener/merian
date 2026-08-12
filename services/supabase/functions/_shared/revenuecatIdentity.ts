const CANONICAL_UUID_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export class RevenueCatIdentityError extends Error {
  constructor(message = "RevenueCat App User ID must be a UUID.") {
    super(message);
    this.name = "RevenueCatIdentityError";
  }
}

/**
 * RevenueCat App User IDs are case-sensitive. PostgreSQL emits UUIDs in
 * lowercase, while Merian's canonical provider identity is uppercase.
 */
export function canonicalRevenueCatAppUserID(value: string): string {
  const normalized = value.trim();
  if (!CANONICAL_UUID_PATTERN.test(normalized)) {
    throw new RevenueCatIdentityError();
  }
  return normalized.toUpperCase();
}
