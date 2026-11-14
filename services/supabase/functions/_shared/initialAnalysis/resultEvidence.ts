/** In-progress original result capture/recovery; no live route or SQL writer.
 * Consumes the original invocation returned by dispatchAccounting, never a raw
 * provider draft as a completed identification or current scan reconstruction. */
import type { AIExecutionOutcome } from "../ai/contracts.ts";
import { identificationProvenance } from "../ai/provenance.ts";
import { identificationUsageFacts } from "../ai/identificationUsage.ts";
import { dataContractV2, provenanceContractV2 } from "./resultSchemaV2.ts";
import { parseInitialResultDataV2 } from "./resultSemanticsV2.ts";
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import type { InitialDispatchBinding } from "./dispatchAccounting.ts";
import {
  initialMediaHash,
  mediaDigest,
  mediaRecord,
  mediaUUID,
} from "./mediaBinding.ts";
import {
  invalidInitialResult,
  transformInitialResult,
} from "./resultEncoding.ts";
import { initialAbortable, initialDeadline } from "./transport.ts";

export interface InitialResultReference {
  readonly owner_id: string;
  readonly scan_id: string;
  readonly invocation_id: string;
  readonly result_evidence_id: string;
  readonly submission_digest: string;
  readonly config_digest: string;
  readonly funding_binding_digest: string;
}
export interface CapturedInitialResult {
  readonly reference: Readonly<InitialResultReference>;
  readonly result_canonical: string;
  readonly provenance_canonical: string;
  readonly result_digest: string;
  readonly provenance_digest: string;
}
const encoder = new TextEncoder();
const captured = new WeakSet<object>();
const dataContract = dataContractV2;
const digest = (domain: "result" | "result-provenance", text: string) =>
  initialMediaHash(
    encoder.encode(`merian.initial-analysis.${domain}.v1\n${text}`),
  );
export function snapshotInitialResultReference(
  value: unknown,
): Readonly<InitialResultReference> {
  const r = mediaRecord(
    parseInitialCanonicalText(initialCanonicalText(value)),
    [
      "owner_id",
      "scan_id",
      "invocation_id",
      "result_evidence_id",
      "submission_digest",
      "config_digest",
      "funding_binding_digest",
    ],
  );
  return Object.freeze({
    owner_id: mediaUUID(r.owner_id),
    scan_id: mediaUUID(r.scan_id),
    invocation_id: mediaUUID(r.invocation_id),
    result_evidence_id: mediaUUID(r.result_evidence_id),
    submission_digest: mediaDigest(r.submission_digest),
    config_digest: mediaDigest(r.config_digest),
    funding_binding_digest: mediaDigest(r.funding_binding_digest),
  });
}
/** Snapshot the closed transport envelope without evaluating accessors. */
export function snapshotCapturedInitialResult(
  value: unknown,
): Readonly<CapturedInitialResult> {
  if (
    !value || typeof value !== "object" ||
    Object.getPrototypeOf(value) !== Object.prototype
  ) throw invalidInitialResult();
  const fields = Object.getOwnPropertyDescriptors(value);
  const keys = [
    "reference",
    "result_canonical",
    "provenance_canonical",
    "result_digest",
    "provenance_digest",
  ];
  if (
    Reflect.ownKeys(value).length !== keys.length ||
    Object.keys(fields).sort().join() !== keys.sort().join()
  ) throw invalidInitialResult();
  for (const field of Object.values(fields)) {
    if (!field.enumerable || !("value" in field)) throw invalidInitialResult();
  }
  const result: unknown = fields.result_canonical.value;
  const provenance: unknown = fields.provenance_canonical.value;
  if (
    typeof result !== "string" || encoder.encode(result).length > 1048576 ||
    typeof provenance !== "string" || encoder.encode(provenance).length > 65536
  ) throw invalidInitialResult();
  return Object.freeze({
    reference: snapshotInitialResultReference(fields.reference.value),
    result_canonical: result,
    provenance_canonical: provenance,
    result_digest: mediaDigest(fields.result_digest.value),
    provenance_digest: mediaDigest(fields.provenance_digest.value),
  });
}
function canonicalBound(text: string, max: number) {
  if (typeof text !== "string" || encoder.encode(text).length > max) {
    throw invalidInitialResult();
  }
  return parseInitialCanonicalText(text);
}
function usageFacts(value: unknown, provider: string) {
  const r = mediaRecord(value, [
    "input_tokens",
    "cached_tokens",
    "cache_write_tokens",
    "output_tokens",
    "candidate_tokens",
    "thinking_tokens",
    "tool_tokens",
    "total_tokens",
    "service_tier",
    "modality_breakdown",
  ]);
  for (
    const key of [
      "input_tokens",
      "cached_tokens",
      "cache_write_tokens",
      "output_tokens",
      "candidate_tokens",
      "thinking_tokens",
      "tool_tokens",
      "total_tokens",
    ]
  ) {
    const v = r[key];
    if (
      v !== null &&
      (typeof v !== "number" || !Number.isSafeInteger(v) || v < 0 ||
        v > 100_000_000)
    ) throw invalidInitialResult();
  }
  if (r.service_tier !== null && r.service_tier !== "default") {
    throw invalidInitialResult();
  }
  const breakdown = mediaRecord(
    r.modality_breakdown,
    provider === "gemini" ? ["prompt", "cached", "candidates", "tool"] : [],
  );
  if (provider !== "gemini" && provider !== "openai") {
    throw invalidInitialResult();
  }
  for (const category of Object.values(breakdown)) {
    if (!category || typeof category !== "object" || Array.isArray(category)) {
      throw invalidInitialResult();
    }
    for (const [key, count] of Object.entries(category)) {
      if (
        !["text", "image", "audio", "video"].includes(key) ||
        typeof count !== "number" || !Number.isSafeInteger(count) ||
        count < 0 || count > 100_000_000
      ) throw invalidInitialResult();
    }
  }
  if (encoder.encode(initialCanonicalText(r)).length > 2048) {
    throw invalidInitialResult();
  }
}

/** Synchronous snapshot before the first await; the caller assigns the stable
 * evidence UUID once. The data argument is the parsed route response before
 * completion entitlement, not outcome.draft. */
export async function captureInitialResult(input: {
  binding: InitialDispatchBinding;
  invocationId: string;
  resultEvidenceId: string;
  outcome: AIExecutionOutcome;
  data: unknown;
}): Promise<Readonly<CapturedInitialResult>> {
  const ref = snapshotInitialResultReference({
    owner_id: input.binding.owner_id,
    scan_id: input.binding.scan_id,
    invocation_id: input.invocationId,
    result_evidence_id: input.resultEvidenceId,
    submission_digest: input.binding.submission_digest,
    config_digest: input.binding.config_digest,
    funding_binding_digest: input.binding.funding_binding_digest,
  });
  if (input.outcome.kind !== "draft") throw invalidInitialResult();
  const encoded = transformInitialResult(dataContract, input.data, "encode");
  const decoded = transformInitialResult(dataContract, encoded, "decode");
  const data = parseInitialResultDataV2(decoded);
  if (data.scan_id !== ref.scan_id || !data.identification_provenance) {
    throw invalidInitialResult();
  }
  const provenance = initialCanonicalText(
    transformInitialResult(
      provenanceContractV2,
      data.identification_provenance,
      "encode",
    ),
  );
  const original = initialCanonicalText(
    transformInitialResult(
      provenanceContractV2,
      identificationProvenance(
        input.outcome.execution,
        input.outcome.returnedModel,
      ),
      "encode",
    ),
  );
  if (provenance !== original || encoder.encode(provenance).length > 65536) {
    throw invalidInitialResult();
  }
  const usage = identificationUsageFacts(input.outcome);
  usageFacts(usage, data.identification_provenance.provider);
  const result = initialCanonicalText({
    version: 1,
    state: "validated_success",
    scan_id: ref.scan_id,
    invocation_id: ref.invocation_id,
    submission_digest: ref.submission_digest,
    config_digest: ref.config_digest,
    funding_binding_digest: ref.funding_binding_digest,
    provider_usage: usage,
    data: encoded,
  });
  const [resultDigest, provenanceDigest] = await Promise.all([
    digest("result", result),
    digest("result-provenance", provenance),
  ]);
  const evidence = Object.freeze({
    reference: ref,
    result_canonical: result,
    provenance_canonical: provenance,
    result_digest: resultDigest,
    provenance_digest: provenanceDigest,
  });
  captured.add(evidence);
  return evidence;
}

/** Every recovery decoder enforces the same numeric round-trip policy and
 * original identity/provenance association. Possessing hashes is not authority;
 * the fixed repository must first authorize ownership and retained evidence. */
export async function decodeInitialResult(
  value: CapturedInitialResult,
  expected: InitialResultReference,
  originalProvenanceCanonical: string,
) {
  value = snapshotCapturedInitialResult(value);
  const ref = snapshotInitialResultReference(expected);
  if (
    initialCanonicalText(snapshotInitialResultReference(value.reference)) !==
      initialCanonicalText(ref)
  ) throw invalidInitialResult();
  const resultText = value.result_canonical,
    provenanceText = value.provenance_canonical;
  const result = mediaRecord(canonicalBound(resultText, 1048576), [
    "version",
    "state",
    "scan_id",
    "invocation_id",
    "submission_digest",
    "config_digest",
    "funding_binding_digest",
    "provider_usage",
    "data",
  ]);
  canonicalBound(provenanceText, 65536);
  canonicalBound(originalProvenanceCanonical, 65536);
  if (
    !initialRequestedProvenanceMatches(
      provenanceText,
      originalProvenanceCanonical,
    )
  ) {
    throw invalidInitialResult();
  }
  const resultDigest = mediaDigest(value.result_digest),
    provenanceDigest = mediaDigest(value.provenance_digest);
  if (
    result.version !== 1 || result.state !== "validated_success" ||
    result.scan_id !== ref.scan_id ||
    result.invocation_id !== ref.invocation_id ||
    result.submission_digest !== ref.submission_digest ||
    result.config_digest !== ref.config_digest ||
    result.funding_binding_digest !== ref.funding_binding_digest
  ) throw invalidInitialResult();
  const data = parseInitialResultDataV2(
    transformInitialResult(dataContract, result.data, "decode"),
  );
  if (
    data.scan_id !== ref.scan_id || !data.identification_provenance ||
    initialCanonicalText(
        transformInitialResult(
          provenanceContractV2,
          data.identification_provenance,
          "encode",
        ),
      ) !== provenanceText
  ) throw invalidInitialResult();
  usageFacts(result.provider_usage, data.identification_provenance.provider);
  if (
    await digest("result", resultText) !== resultDigest ||
    await digest("result-provenance", provenanceText) !== provenanceDigest
  ) throw invalidInitialResult();
  return data;
}

export interface InitialResultStore {
  /** Fixed original-result write; no permission to dispatch, promote or settle. */
  write(
    value: Readonly<CapturedInitialResult>,
    signal: AbortSignal,
  ): Promise<void>;
  /** Null means no exact durable result observed; never permission to execute. */
  read(
    reference: Readonly<InitialResultReference & { result_digest: string }>,
    signal: AbortSignal,
  ): Promise<CapturedInitialResult | null>;
}

/** One write attempt followed by exact read-back, including after a lost ack.
 * A failed/absent/mismatched read is held, never promotion or repeat inference. */
export async function persistInitialResult(
  store: InitialResultStore,
  value: CapturedInitialResult,
  caller: AbortSignal,
): Promise<"stored" | "held"> {
  if (!captured.has(value)) throw invalidInitialResult();
  const frozen = snapshotCapturedInitialResult(value);
  await decodeInitialResult(
    frozen,
    frozen.reference,
    frozen.provenance_canonical,
  );
  try {
    await initialDeadline(
      caller,
      5000,
      (signal) => initialAbortable(signal, () => store.write(frozen, signal)),
    );
  } catch { /* Only exact durable read-back may establish success below. */ }
  try {
    return await initialDeadline(caller, 5000, async (signal) => {
      const stored = await initialAbortable(
        signal,
        () =>
          store.read(
            Object.freeze({
              ...frozen.reference,
              result_digest: frozen.result_digest,
            }),
            signal,
          ),
      );
      if (
        !stored || stored.result_digest !== frozen.result_digest ||
        stored.provenance_digest !== frozen.provenance_digest ||
        stored.result_canonical !== frozen.result_canonical ||
        stored.provenance_canonical !== frozen.provenance_canonical
      ) return "held";
      await initialAbortable(
        signal,
        () =>
          decodeInitialResult(
            stored,
            frozen.reference,
            frozen.provenance_canonical,
          ),
      );
      return "stored";
    });
  } catch {
    return "held";
  }
}

/** Compare immutable requested configuration without pretending it knew the response. */
export function initialRequestedProvenanceMatches(
  received: string,
  requested: string,
): boolean {
  if (received === requested) return true;
  try {
    const left = parseInitialCanonicalText(received) as Record<string, unknown>;
    const right = parseInitialCanonicalText(requested) as Record<
      string,
      unknown
    >;
    if (
      left.version !== 3 || right.version !== 3 ||
      left.model !== "gemini-3.8-flash" ||
      left.returned_model !== left.model ||
      (right.returned_model !== null && right.returned_model !== left.model)
    ) return false;
    const { returned_model: _left, ...leftRequested } = left;
    const { returned_model: _right, ...rightRequested } = right;
    return initialCanonicalText(leftRequested) ===
      initialCanonicalText(rightRequested);
  } catch {
    return false;
  }
}
