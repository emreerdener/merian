import { MEDIA_BUDGETS } from "../mediaBudgets.ts";

// Private primitive seam. The authenticated upload owner reserves full cohorts;
// this per-item helper alone is never an API admission boundary.
export const EVIDENCE_MAX_BYTES = 32 * 1024 * 1024;
export const EVIDENCE_TYPES = [
  "image/jpeg",
  "image/png",
  "image/heic",
  "audio/mp4",
  "video/mp4",
] as const;
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
export interface EvidenceIdentity {
  owner_id: string;
  observation_id: string;
  analysis_id: string;
  media_id: string;
}
export interface EvidenceUpload extends EvidenceIdentity {
  content_type: string;
  byte_count: number;
  sha256: string;
}
export interface EvidenceReceipt extends EvidenceUpload {
  object_id: string;
  expires_at: string;
  ready_at: string | null;
}
export interface EvidenceErasure {
  object_id: string;
  claim_token: string;
}
export interface EvidenceRepository {
  reserve(input: EvidenceUpload): Promise<unknown>;
  complete(identity: EvidenceIdentity, objectId: string): Promise<unknown>;
  readOwned(identity: EvidenceIdentity): Promise<unknown>;
  claimErasure(): Promise<EvidenceErasure | null>;
  finishErasure(claim: EvidenceErasure, success: boolean): Promise<boolean>;
}
export interface EvidenceStorage {
  writeOnce(
    receipt: EvidenceReceipt,
    bytes: Uint8Array,
    signal?: AbortSignal,
  ): Promise<void>;
  signedRead(receipt: EvidenceReceipt): Promise<string>;
  erase(objectId: string): Promise<void>;
}
export function evidenceObjectKey(objectId: string): string {
  if (!uuid.test(objectId)) throw new Error("invalid_history_evidence");
  return `evidence/v1/${objectId}`;
}
function validateIdentity(input: EvidenceIdentity) {
  if (
    ![input.owner_id, input.observation_id, input.analysis_id, input.media_id]
      .every((value) => typeof value === "string" && uuid.test(value)) ||
    new Set([input.observation_id, input.analysis_id, input.media_id]).size !==
      3
  ) throw new Error("invalid_history_evidence");
}
export function parseEvidenceReceipt(
  value: unknown,
  identity: EvidenceIdentity,
  upload?: EvidenceUpload,
): EvidenceReceipt {
  return parseReceipt(
    value,
    identity,
    upload,
    EVIDENCE_TYPES,
    1,
    EVIDENCE_MAX_BYTES,
  );
}
export function parseAudioEvidenceReceipt(
  value: unknown,
  identity: EvidenceIdentity,
  upload: EvidenceUpload,
): EvidenceReceipt {
  const keys = [
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
  ];
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).length !== keys.length ||
    !keys.every((key) => Object.hasOwn(value, key))
  ) {
    throw new Error("invalid_history_evidence");
  }
  return parseReceipt(
    value,
    identity,
    upload,
    ["audio/wav"],
    46,
    MEDIA_BUDGETS.maxAudioRawBytes,
  );
}
function parseReceipt(
  value: unknown,
  identity: EvidenceIdentity,
  upload: EvidenceUpload | undefined,
  types: readonly string[],
  minimum: number,
  maximum: number,
): EvidenceReceipt {
  validateIdentity(identity);
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new Error("invalid_history_evidence");
  }
  const row = value as EvidenceReceipt;
  for (
    const key of [
      "owner_id",
      "observation_id",
      "analysis_id",
      "media_id",
    ] as const
  ) {
    if (row[key] !== identity[key]) throw new Error("invalid_history_evidence");
  }
  evidenceObjectKey(row.object_id);
  if (
    [row.owner_id, row.observation_id, row.analysis_id, row.media_id].includes(
      row.object_id,
    )
  ) throw new Error("invalid_history_evidence");
  if (
    !types.includes(row.content_type) ||
    !Number.isSafeInteger(row.byte_count) || row.byte_count < minimum ||
    row.byte_count > maximum ||
    typeof row.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(row.sha256) ||
    typeof row.expires_at !== "string" ||
    !Number.isFinite(Date.parse(row.expires_at)) ||
    (row.ready_at !== null &&
      (typeof row.ready_at !== "string" ||
        !Number.isFinite(Date.parse(row.ready_at)))) ||
    (upload &&
      (upload.byte_count !== row.byte_count || upload.sha256 !== row.sha256 ||
        upload.content_type !== row.content_type))
  ) throw new Error("invalid_history_evidence");
  return { ...row };
}
export async function evidenceDigest(bytes: Uint8Array): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest("SHA-256", bytes.slice()),
  );
  return Array.from(digest, (byte) => byte.toString(16).padStart(2, "0")).join(
    "",
  );
}
export async function storeObservationEvidence(
  identity: EvidenceIdentity,
  contentType: string,
  bytes: Uint8Array,
  repository: EvidenceRepository,
  storage: EvidenceStorage,
): Promise<EvidenceReceipt> {
  validateIdentity(identity);
  if (
    !(EVIDENCE_TYPES as readonly string[]).includes(contentType) ||
    bytes.byteLength < 1 || bytes.byteLength > EVIDENCE_MAX_BYTES
  ) {
    throw new Error("invalid_history_evidence");
  }
  // Own the buffer across asynchronous hashing/admission to prevent mutation.
  const body = bytes.slice();
  const input: EvidenceUpload = {
    ...identity,
    content_type: contentType,
    byte_count: body.byteLength,
    sha256: await evidenceDigest(body),
  };
  const receipt = parseEvidenceReceipt(
    await repository.reserve(input),
    identity,
    input,
  );
  if (receipt.ready_at === null) {
    if (Date.parse(receipt.expires_at) <= Date.now()) {
      throw new Error("history_evidence_expired");
    }
    await storage.writeOnce(receipt, body);
  }
  // Always recheck the owner/deletion fence, including ready reservation replay.
  const completed = parseEvidenceReceipt(
    await repository.complete(identity, receipt.object_id),
    identity,
    input,
  );
  if (
    completed.object_id !== receipt.object_id || completed.ready_at === null
  ) throw new Error("invalid_history_evidence");
  return completed;
}
export async function readObservationEvidence(
  identity: EvidenceIdentity,
  repository: EvidenceRepository,
  storage: EvidenceStorage,
): Promise<string> {
  validateIdentity(identity);
  const receipt = parseEvidenceReceipt(
    await repository.readOwned(identity),
    identity,
  );
  if (receipt.ready_at === null) throw new Error("history_evidence_not_ready");
  return await storage.signedRead(receipt);
}
export async function eraseObservationEvidenceBatch(
  repository: EvidenceRepository,
  storage: EvidenceStorage,
  limit = 4,
): Promise<number> {
  if (!Number.isSafeInteger(limit) || limit < 1 || limit > 20) {
    throw new Error("invalid_history_evidence");
  }
  let erased = 0;
  for (let n = 0; n < limit; n++) {
    const claim = await repository.claimErasure();
    if (!claim) break;
    evidenceObjectKey(claim.object_id);
    if (!uuid.test(claim.claim_token)) {
      throw new Error("invalid_history_evidence");
    }
    let success = false;
    try {
      await storage.erase(claim.object_id);
      success = true;
    } catch {
      // No raw storage error/key/owner logging. Durable claim retries on failure.
    }
    if (await repository.finishErasure(claim, success) && success) erased++;
  }
  return erased;
}
