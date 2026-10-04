import { historyUUID, invalidHistory } from "./contract.ts";

export interface PhotoErasureDependencies {
  claim(objectId: string | null): Promise<unknown>;
  erase(objectId: string): Promise<void>;
  finish(
    objectId: string,
    claimToken: string,
    success: boolean,
  ): Promise<boolean>;
}
/** One bounded claim. The optional target is internal worker input, never an
 * authenticated user's authorization to erase a public object. */
export async function erasePublicationPhoto(
  deps: PhotoErasureDependencies,
  target: string | null = null,
) {
  const requested = target === null ? null : historyUUID(target);
  const value = await deps.claim(requested);
  if (value === null) return { claimed: 0, marked: 0, acknowledged: 0 };
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return invalidHistory();
  }
  const row = value as Record<string, unknown>;
  const fields = [
    "object_id",
    "available_at",
    "claim_token",
    "claim_expires_at",
    "erased_at",
    "bound_at",
    "revoked_at",
  ];
  if (
    Object.keys(row).length !== fields.length ||
    fields.some((key) => !Object.hasOwn(row, key))
  ) return invalidHistory();
  for (
    const key of ["available_at", "claim_expires_at", "bound_at", "revoked_at"]
  ) {
    if ((key === "bound_at" || key === "revoked_at") && row[key] === null) {
      continue;
    }
    if (
      typeof row[key] !== "string" ||
      !Number.isFinite(Date.parse(row[key] as string))
    ) return invalidHistory();
  }
  const object = historyUUID(row.object_id),
    claim = historyUUID(row.claim_token);
  if (requested !== null && object !== requested) return invalidHistory();
  if (
    row.erased_at !== null ||
    (row.bound_at !== null && row.revoked_at === null) ||
    typeof row.claim_expires_at !== "string" ||
    !Number.isFinite(Date.parse(row.claim_expires_at))
  ) return invalidHistory();
  // Copy identity before external I/O; caller mutation and account switching
  // cannot redirect either the storage operation or its acknowledgement.
  let marked = false;
  try {
    await deps.erase(object);
    marked = true;
  } catch { /* Keep durable retry. */ }
  let acknowledged = false;
  try {
    acknowledged = await deps.finish(object, claim, marked) === true;
  } catch { /* Claim expiry recovers a lost acknowledgement. */ }
  return {
    claimed: 1,
    marked: marked ? 1 : 0,
    acknowledged: acknowledged ? 1 : 0,
  };
}
