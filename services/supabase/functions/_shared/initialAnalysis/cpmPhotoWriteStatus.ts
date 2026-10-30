/** Historical observation only. Null, bound and closed never grant dispatch. */
import schema from "./cpm-photo-write-status-schema-v1.json" with {
  type: "json",
};
import { matchesInitialSchema } from "./schema.ts";
import {
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaTime,
  mediaUUID,
} from "./mediaBinding.ts";

export interface CpmPhotoStatusIdentity {
  readonly owner: string;
  readonly scan: string;
  readonly assignment_digest: string;
  readonly object: string;
  readonly allocation_created_at_ms: number;
  readonly allocation_expires_at_ms: number;
}
export interface CpmPhotoWriteStatus {
  readonly version: 1;
  readonly authority: "none";
  readonly scan_id: string;
  readonly assignment_digest: string;
  readonly object_id: string;
  readonly attempt:
    | Readonly<{
      attempt_id: string;
      state: "bound" | "may_have_issued";
      created_at_ms: number;
      capability_expires_at_ms: number;
      write_closed: boolean;
    }>
    | null;
}
export interface CpmPhotoStatusBridge {
  readStatus(
    identity: CpmPhotoStatusIdentity,
    saved: CpmPhotoWriteStatus | null,
    signal: AbortSignal,
  ): Promise<CpmPhotoWriteStatus>;
}

/** Owner comes from authentication, all other facts from the saved allocation.
 * Validating this value does not authenticate it or grant database access. */
export function snapshotCpmPhotoStatusIdentity(
  value: unknown,
): CpmPhotoStatusIdentity {
  const r = mediaRecord(value, [
    "owner",
    "scan",
    "assignment_digest",
    "object",
    "allocation_created_at_ms",
    "allocation_expires_at_ms",
  ]);
  const created = mediaTime(r.allocation_created_at_ms);
  const expires = mediaTime(r.allocation_expires_at_ms);
  if (created > 8_639_999_998_200_000 || expires !== created + 1_800_000) {
    throw initialMediaUnavailable();
  }
  return Object.freeze({
    owner: mediaUUID(r.owner),
    scan: mediaUUID(r.scan),
    assignment_digest: mediaDigest(r.assignment_digest),
    object: mediaUUID(r.object),
    allocation_created_at_ms: created,
    allocation_expires_at_ms: expires,
  });
}

/** Exact SQL clocks and monotonic saved facts; expiry is not a recovery cutoff.
 * The transport bounds bytes before parsing. This closed schema bounds values. */
export function decodeCpmPhotoWriteStatus(
  value: unknown,
  identity: CpmPhotoStatusIdentity,
  saved: CpmPhotoWriteStatus | null = null,
): CpmPhotoWriteStatus {
  const i = snapshotCpmPhotoStatusIdentity(identity);
  if (!matchesInitialSchema(value, schema)) throw initialMediaUnavailable();
  // The executable schema above checks every property, enum, type and bound.
  const v = value as CpmPhotoWriteStatus;
  if (
    v.scan_id !== i.scan || v.assignment_digest !== i.assignment_digest ||
    v.object_id !== i.object
  ) {
    throw initialMediaUnavailable();
  }
  const a = v.attempt;
  if (
    a !== null && (a.created_at_ms < i.allocation_created_at_ms ||
      a.created_at_ms >= i.allocation_expires_at_ms ||
      a.capability_expires_at_ms !==
        Math.min(i.allocation_expires_at_ms, a.created_at_ms + 600_000) ||
      (a.write_closed && a.state !== "may_have_issued"))
  ) throw initialMediaUnavailable();
  const old = saved === null
    ? null
    : decodeCpmPhotoWriteStatus(saved, i).attempt;
  if (
    old !== null && (a === null || a.attempt_id !== old.attempt_id ||
      a.created_at_ms !== old.created_at_ms ||
      a.capability_expires_at_ms !== old.capability_expires_at_ms ||
      (old.state === "may_have_issued" && a.state !== old.state) ||
      (old.write_closed && !a.write_closed))
  ) {
    throw initialMediaUnavailable();
  }
  return Object.freeze({
    version: 1,
    authority: "none",
    scan_id: i.scan,
    assignment_digest: i.assignment_digest,
    object_id: i.object,
    attempt: a === null ? null : Object.freeze({ ...a }),
  });
}
