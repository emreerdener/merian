/** Public boundary: only caller-supplied public IDs and their current eligibility. */
export const VISIBILITY_BATCH_SIZE = 128;
export const VISIBILITY_LEASE_MS = 6000;
export const VISIBILITY_POLL_MS = 2000;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function visibilityIds(value: unknown): string[] | null {
  if (
    !Array.isArray(value) || value.length < 1 ||
    value.length > VISIBILITY_BATCH_SIZE ||
    value.some((id) => typeof id !== "string" || !uuid.test(id))
  ) return null;
  return [...new Set((value as string[]).map((id) => id.toLowerCase()))];
}
export function visibilityResult(
  value: unknown,
  requested: string[],
): string[] {
  if (
    !value || typeof value !== "object" || !("visible" in value) ||
    !Array.isArray(value.visible)
  ) {
    throw new Error("Invalid visibility response");
  }
  const allowed = new Set(requested);
  if (
    value.visible.length > requested.length ||
    value.visible.some((id: unknown) =>
      typeof id !== "string" || !allowed.has(id)
    )
  ) {
    throw new Error("Invalid visibility response");
  }
  return [...new Set(value.visible)] as string[];
}
