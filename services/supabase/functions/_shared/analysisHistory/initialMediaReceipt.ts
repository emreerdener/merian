import { exactObject, historyUUID } from "./contract.ts";
import { INITIAL_ORIGINAL_MAX_BYTES } from "./initialEvidenceManifest.ts";
import {
  type EvidenceIdentity,
  type EvidenceReceipt,
  parseCompletedMediaReceipt,
} from "./evidence.ts";

/** Durable ordinary evidence has no allocation expiry. Delivery still uses the
 * same bounded private signed URL; this is not a public/export capability. */
export type InitialMediaReceipt =
  & Omit<EvidenceReceipt, "expires_at" | "ready_at">
  & {
    readonly schema_version: 2;
    readonly expires_at: null;
    readonly ready_at: string;
  };
export type OriginalMediaReceipt =
  & Omit<InitialMediaReceipt, "schema_version">
  & {
    readonly schema_version: 3;
    readonly artifact_role: string;
  };
export type CompletedMediaReceipt =
  | EvidenceReceipt
  | InitialMediaReceipt
  | OriginalMediaReceipt;
function invalidHistory(): never {
  throw new Error("invalid_history_evidence");
}

export function parseResolvedMediaReceipt(
  value: unknown,
  identity: EvidenceIdentity,
  protocol: 1 | 2 | 3,
  previous?: CompletedMediaReceipt,
): CompletedMediaReceipt {
  try {
    return parseReceipt(value, identity, protocol, previous);
  } catch {
    return invalidHistory();
  }
}

function parseReceipt(
  value: unknown,
  identity: EvidenceIdentity,
  protocol: 1 | 2 | 3,
  previous?: CompletedMediaReceipt,
): CompletedMediaReceipt {
  if (!value || typeof value !== "object" || !("schema_version" in value)) {
    if (previous && "schema_version" in previous) return invalidHistory();
    return parseCompletedMediaReceipt(value, identity, previous);
  }
  const original = value.schema_version === 3;
  if (
    (protocol !== 2 && protocol !== 3) || (original && protocol !== 3) ||
    (previous && !("schema_version" in previous))
  ) {
    return invalidHistory();
  }
  const row = exactObject(value, [
    "schema_version",
    "owner_id",
    "observation_id",
    "analysis_id",
    "media_id",
    "content_type",
    "byte_count",
    "sha256",
    "object_id",
    "expires_at",
    "ready_at",
    ...(original ? ["artifact_role"] : []),
  ]);
  const identities = Object.values(identity).map(historyUUID);
  const object = historyUUID(row.object_id);
  if (new Set([...identities, object]).size !== 5) return invalidHistory();
  for (const [key, expected] of Object.entries(identity)) {
    if (row[key] !== expected) return invalidHistory();
  }
  const type = row.content_type;
  const role = row.artifact_role;
  if (original) {
    const allowed: Record<string, readonly string[]> = {
      source_image: [
        "image/jpeg",
        "image/png",
        "image/webp",
        "image/heic",
        "image/heif",
      ],
      prepared_image: ["image/jpeg", "image/png"],
      inference_frame: ["image/jpeg", "image/png"],
      source_audio: ["audio/wav", "audio/mp4"],
      source_companion_audio: ["audio/wav", "audio/mp4"],
      prepared_audio: ["audio/wav"],
      prepared_companion_audio: ["audio/wav"],
      source_video: ["video/mp4"],
      playback_video: ["video/mp4"],
    };
    if (
      typeof role !== "string" || !Object.hasOwn(allowed, role) ||
      typeof type !== "string" || !allowed[role].includes(type)
    ) return invalidHistory();
  }
  const max = type === "video/mp4"
    ? 12_582_912
    : type === "audio/wav" || type === "audio/mp4"
    ? 2_700_000
    : original && role === "source_image"
    ? INITIAL_ORIGINAL_MAX_BYTES
    : 5_242_880;
  if (
    row.schema_version !== (original ? 3 : 2) || row.expires_at !== null ||
    typeof type !== "string" ||
    ![
      "image/jpeg",
      "image/png",
      "image/webp",
      "image/heic",
      "image/heif",
      "audio/mp4",
      "audio/wav",
      "video/mp4",
    ].includes(type) ||
    typeof row.byte_count !== "number" ||
    !Number.isSafeInteger(row.byte_count) ||
    row.byte_count < (type === "audio/wav" ? 46 : 1) || row.byte_count > max ||
    typeof row.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(row.sha256) ||
    typeof row.ready_at !== "string" ||
    !Number.isFinite(Date.parse(row.ready_at))
  ) {
    return invalidHistory();
  }
  const common = {
    ...identity,
    object_id: object,
    content_type: type,
    byte_count: row.byte_count,
    sha256: row.sha256,
    expires_at: null,
    ready_at: row.ready_at,
  };
  const receipt: InitialMediaReceipt | OriginalMediaReceipt =
    original && typeof role === "string"
      ? Object.freeze({
        ...common,
        schema_version: 3 as const,
        artifact_role: role,
      })
      : Object.freeze({ ...common, schema_version: 2 as const });
  if (
    previous &&
    (Object.keys(receipt).length !== Object.keys(previous).length ||
      Object.entries(receipt).some(([key, member]) =>
        !Object.entries(previous).some(([oldKey, oldValue]) =>
          key === oldKey && member === oldValue
        )
      ))
  ) return invalidHistory();
  return receipt;
}
