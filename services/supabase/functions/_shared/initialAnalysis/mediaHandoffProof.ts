/** Pure retained-media proof codecs. No issuance, byte I/O or execution authority. */
import { validateAdmittedProof } from "./admittedProof.ts";
import {
  type AdmissionDestinationMapping,
  type AdmissionMediaBinding,
} from "./admissionMetadata.ts";
import {
  hex,
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import type { InitialHandoffProfile } from "./handoffProfile.ts";
import type { PreparationTuple } from "./preparationExecutionContract.ts";
import { matchesInitialSchema } from "./schema.ts";
import schema from "./media-handoff-proof-schema-v1.json" with { type: "json" };

export const MEDIA_HANDOFF_PROOF_LIMITS = Object.freeze({
  claim: 32_768,
  verification_receipt: 65_536,
  transfer_receipt: 98_304,
});
export type MediaHandoffProofKind = keyof typeof MEDIA_HANDOFF_PROOF_LIMITS;
export interface MediaVerificationClaimV2 {
  version: 2;
  binding: AdmissionMediaBinding;
  admission_receipt_digest: string;
  verification_adapter_digest: string;
  claim_token: string;
  issued_at_ms: number;
}
export interface MediaVerificationReceiptV2 {
  version: 2;
  claim: MediaVerificationClaimV2;
  claim_digest: string;
  objects: (PreparationTuple & {
    object_id: string;
    backend_generation: string;
  })[];
  authorized_at_ms: number;
}
export interface MediaTransferReceiptV1 {
  version: 1;
  admission_receipt_digest: string;
  protocol_artifact_digest: string;
  verification_receipt: MediaVerificationReceiptV2;
  verification_receipt_digest: string;
  authorized_at_ms: number;
}
export interface MediaHandoffProofValidation {
  authority: "none";
  canonical: string;
  digest: string;
}
interface OriginalProof {
  receiptDigest: string;
  bindingText: string;
  binding: AdmissionMediaBinding;
  mapping: AdmissionDestinationMapping;
  handoff: InitialHandoffProfile;
  authorizedAtMs: number;
}
const bytes = new TextEncoder();
const domains = {
  claim: "verification-claim.v2",
  verification_receipt: "verification-receipt.v2",
  transfer_receipt: "transfer-receipt.v1",
} as const;

function bounded(kind: MediaHandoffProofKind, value: unknown): string {
  if (!Object.hasOwn(MEDIA_HANDOFF_PROOF_LIMITS, kind)) invalidInitialInput();
  // Each document is independently bounded before parsing or hashing.
  const text = initialCanonicalText(value);
  if (bytes.encode(text).length > MEDIA_HANDOFF_PROOF_LIMITS[kind]) {
    invalidInitialInput();
  }
  const parsed = parseInitialCanonicalText(text);
  if (!matchesInitialSchema(parsed, schema[kind])) invalidInitialInput();
  if (kind === "claim") {
    const claim = parsed as unknown as MediaVerificationClaimV2;
    if (bytes.encode(initialCanonicalText(claim.binding)).length > 16_384) {
      invalidInitialInput();
    }
  } else if (kind === "verification_receipt") {
    const receipt = parsed as unknown as MediaVerificationReceiptV2;
    if (receipt.objects.length === 0) invalidInitialInput();
    bounded("claim", receipt.claim);
  } else {
    bounded(
      "verification_receipt",
      (parsed as unknown as MediaTransferReceiptV1).verification_receipt,
    );
  }
  return text;
}

/** Canonical identity only. Even a correct digest never proves stored issuance. */
export async function mediaHandoffProofDigest(
  kind: MediaHandoffProofKind,
  canonical: string,
): Promise<string> {
  if (
    !Object.hasOwn(MEDIA_HANDOFF_PROOF_LIMITS, kind) ||
    typeof canonical !== "string" ||
    bytes.encode(canonical).length > MEDIA_HANDOFF_PROOF_LIMITS[kind]
  ) invalidInitialInput();
  bounded(kind, parseInitialCanonicalText(canonical));
  return hex(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        bytes.encode(
          `merian.initial-analysis.handoff.${domains[kind]}\n${canonical}`,
        ),
      ),
    ),
  );
}

async function originalProof(value: unknown): Promise<OriginalProof> {
  // This existing owner snapshots all twelve TEXT components synchronously
  // before its first await. Never accept a caller's prevalidated context.
  const original = await validateAdmittedProof(value);
  const canonical = original.canonical;
  return {
    receiptDigest: original.receiptDigest,
    bindingText: canonical.media_binding,
    binding: JSON.parse(canonical.media_binding),
    mapping: JSON.parse(canonical.mapping),
    handoff: JSON.parse(canonical.configuration).assignment.handoff.profile,
    authorizedAtMs: JSON.parse(canonical.manifest).authorized_at_ms,
  };
}

function checkClaim(original: OriginalProof, text: string): void {
  const claim = JSON.parse(text) as MediaVerificationClaimV2;
  if (
    initialCanonicalText(claim.binding) !== original.bindingText ||
    claim.admission_receipt_digest !== original.receiptDigest ||
    claim.verification_adapter_digest !==
      original.handoff.verification_adapter_digest ||
    claim.issued_at_ms < original.authorizedAtMs ||
    claim.issued_at_ms >=
      original.binding.phase_window.cutoffs.verification_claim
  ) invalidInitialInput();
}

async function checkVerification(
  original: OriginalProof,
  claimText: string,
  receiptText: string,
): Promise<void> {
  checkClaim(original, claimText);
  const receipt = JSON.parse(receiptText) as MediaVerificationReceiptV2;
  const expectedObjects = original.mapping.objects.map((
    { object_id, bytes },
  ) => ({
    object_id,
    backend_generation: original.mapping.destination_backend_generation,
    ...bytes,
  }));
  if (
    initialCanonicalText(receipt.claim) !== claimText ||
    receipt.claim_digest !==
      await mediaHandoffProofDigest("claim", claimText) ||
    initialCanonicalText(receipt.objects) !==
      initialCanonicalText(expectedObjects) ||
    receipt.authorized_at_ms < receipt.claim.issued_at_ms ||
    receipt.authorized_at_ms >=
      original.binding.phase_window.cutoffs.verification_settlement
  ) invalidInitialInput();
  // Exact equality above inherits the admitted mapping's nonempty, sorted,
  // unique union, ordinal aliases and saved/global object and byte bounds.
}

async function result(
  kind: MediaHandoffProofKind,
  canonical: string,
): Promise<MediaHandoffProofValidation> {
  return {
    authority: "none",
    canonical,
    digest: await mediaHandoffProofDigest(kind, canonical),
  };
}

/** Historical consistency, not token issuance or time provenance. A coherent
 * alternate synthetic token may pass; only the later locked owner knows which
 * original token it issued. No local clock is consulted by these codecs. */
export async function validateMediaVerificationClaim(
  original: unknown,
  claimValue: unknown,
): Promise<MediaHandoffProofValidation> {
  const claim = bounded("claim", claimValue);
  checkClaim(await originalProof(original), claim);
  return await result("claim", claim);
}

export async function validateMediaVerificationReceipt(
  original: unknown,
  originalClaim: unknown,
  receiptValue: unknown,
): Promise<MediaHandoffProofValidation> {
  const claim = bounded("claim", originalClaim);
  const receipt = bounded("verification_receipt", receiptValue);
  await checkVerification(await originalProof(original), claim, receipt);
  return await result("verification_receipt", receipt);
}

export async function validateMediaTransferReceipt(
  original: unknown,
  originalClaim: unknown,
  originalVerification: unknown,
  transferValue: unknown,
): Promise<MediaHandoffProofValidation> {
  // Capture all caller-owned values, including the admitted original via its
  // validator, before any asynchronous hashing can yield to a caller mutation.
  const claim = bounded("claim", originalClaim);
  const verification = bounded("verification_receipt", originalVerification);
  const transfer = bounded("transfer_receipt", transferValue);
  const context = await originalProof(original);
  await checkVerification(context, claim, verification);
  const parsed = JSON.parse(transfer) as MediaTransferReceiptV1;
  if (
    parsed.admission_receipt_digest !== context.receiptDigest ||
    parsed.protocol_artifact_digest !==
      context.binding.phase_window.protocol_artifact_digest ||
    initialCanonicalText(parsed.verification_receipt) !== verification ||
    parsed.verification_receipt_digest !==
      await mediaHandoffProofDigest("verification_receipt", verification) ||
    parsed.authorized_at_ms < parsed.verification_receipt.authorized_at_ms ||
    parsed.authorized_at_ms >= context.binding.phase_window.cutoffs.transfer
  ) invalidInitialInput();
  return await result("transfer_receipt", transfer);
}
