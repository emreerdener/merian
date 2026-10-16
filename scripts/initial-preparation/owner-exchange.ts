/** Fixed local fixture protocol. Never imported by a production route. */
import { initialCanonicalText } from "../../services/supabase/functions/_shared/initialAnalysis/canonical.ts";
import { executionDigest } from "../../services/supabase/functions/_shared/initialAnalysis/preparationExecutionContract.ts";
import type { PreparationExecutionDependencies } from "../../services/supabase/functions/_shared/initialAnalysis/preparationExecution.ts";
import vector from "./owner-fixture.json" with { type: "json" };

type RuntimeInput = Parameters<PreparationExecutionDependencies["runtime"]>[0];
const invalid = (): never => {
  throw new Error("local_preparation_protocol");
};
export async function byteDigest(
  bytes: Uint8Array<ArrayBuffer>,
): Promise<string> {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(
    (x) => x.toString(16).padStart(2, "0"),
  ).join("");
}
export function base64(bytes: Uint8Array): string {
  let text = "";
  for (let i = 0; i < bytes.length; i += 8192) {
    text += String.fromCharCode(...bytes.subarray(i, i + 8192));
  }
  return btoa(text);
}
function decode(text: unknown, max: number): Uint8Array<ArrayBuffer> {
  if (typeof text !== "string" || text.length > Math.ceil(max / 3) * 4) {
    return invalid();
  }
  let binary: string;
  try {
    binary = atob(text);
  } catch {
    return invalid();
  }
  const bytes = Uint8Array.from(binary, (x) => x.charCodeAt(0));
  if (!bytes.length || bytes.length > max || base64(bytes) !== text) {
    return invalid();
  }
  return bytes;
}
function closed(value: unknown, keys: string[]): Record<string, unknown> {
  if (
    !value || typeof value !== "object" || Array.isArray(value) ||
    Object.keys(value).join() !== keys.join()
  ) return invalid();
  return value as Record<string, unknown>;
}
export class LocalPreparationRejected extends Error {
  constructor(readonly stage: "validation" | "transform") {
    super("local_preparation_rejected");
  }
}
/** Bind metadata and bytes before the first await. Sole caller still owns grant authority. */
async function requestFor(input: RuntimeInput) {
  const profile = JSON.parse(initialCanonicalText(input.profile));
  const grant = JSON.parse(initialCanonicalText(input.grant));
  const source = JSON.parse(initialCanonicalText(input.source_verification));
  const supplied = input.read(0);
  if (
    !(supplied instanceof Uint8Array) ||
    !(supplied.buffer instanceof ArrayBuffer) || supplied.length < 44 ||
    supplied.length > 192000
  ) return invalid();
  const bytes = new Uint8Array(supplied);
  if (
    initialCanonicalText(profile) !== initialCanonicalText(vector.profile) ||
    grant.scan_id !== vector.scan ||
    grant.assignment_digest !== vector.assignment_digest ||
    grant.grant_id !== vector.grant_id ||
    grant.profile_digest !== vector.assignment.preparation.profile_digest ||
    grant.artifact_digest !== vector.profile.spec.artifact.sha256 ||
    source.scan_id !== vector.scan ||
    source.assignment_digest !== vector.assignment_digest ||
    source.profile_digest !== grant.profile_digest ||
    source.backend_generation !==
      vector.assignment.preparation.backend_generation ||
    source.validator_identity !== vector.profile.spec.identities.validator ||
    source.entries.length !== 1
  ) return invalid();
  const entry = source.entries[0],
    wanted = vector.candidate.source_plan.sources[0];
  if (
    entry.ordinal !== 0 ||
    entry.object_id !==
      vector.assignment.preparation.source_mapping[0].object_id ||
    entry.bytes.byte_count !== bytes.length ||
    entry.bytes.byte_count !== wanted.source_byte_count ||
    entry.bytes.sha256 !== wanted.source_sha256 ||
    entry.bytes.content_type !== "audio/wav"
  ) return invalid();
  const sha = await byteDigest(bytes);
  const expectedSource = {
    version: 1,
    scan_id: vector.scan,
    assignment_digest: vector.assignment_digest,
    profile_digest: vector.assignment.preparation.profile_digest,
    backend_generation: vector.assignment.preparation.backend_generation,
    validator_identity: vector.profile.spec.identities.validator,
    entries: [{
      ordinal: 0,
      object_id: vector.assignment.preparation.source_mapping[0].object_id,
      bytes: {
        byte_count: wanted.source_byte_count,
        sha256: wanted.source_sha256,
        content_type: "audio/wav",
      },
      facts: {
        image: null,
        wav: {
          format: "pcm16",
          sample_rate: 32000,
          channels: 1,
          frames: 32000,
        },
        mp4: null,
      },
    }],
  };
  const expectedGrant = {
    version: 1,
    scan_id: vector.scan,
    assignment_digest: vector.assignment_digest,
    grant_id: vector.grant_id,
    source_digest: await executionDigest(
      "source_verification",
      initialCanonicalText(expectedSource),
    ),
    profile_digest: vector.assignment.preparation.profile_digest,
    artifact_digest: vector.profile.spec.artifact.sha256,
    issued_at_ms: 1000000,
    execution_deadline_ms: 1020000,
    registration_deadline_ms: 1025000,
    outcome_deadline_ms: 1060000,
  };
  if (
    initialCanonicalText(source) !== initialCanonicalText(expectedSource) ||
    initialCanonicalText(grant) !== initialCanonicalText(expectedGrant) ||
    sha !== entry.bytes.sha256 ||
    grant.source_digest !==
      await executionDigest("source_verification", initialCanonicalText(source))
  ) return invalid();
  const request = {
    version: 2,
    operation: "validated_wav16k",
    base64: base64(bytes),
    preserve_source_when_trimmed_too_short: false,
  };
  if (
    request.base64.length > 256000 || JSON.stringify(request).length > 262144
  ) return invalid();
  const value = {
    version: 1,
    kind: "execute",
    scan_id: vector.scan,
    assignment_digest: vector.assignment_digest,
    grant_id: grant.grant_id,
    source_digest: grant.source_digest,
    profile_digest: grant.profile_digest,
    ordinal: 0,
    request,
  };
  return { frame: JSON.stringify(value) + "\n", bytes, grant };
}
export function createOwnerRuntime(
  exchange: (frame: string, signal: AbortSignal) => Promise<string>,
): PreparationExecutionDependencies["runtime"] {
  let consumed = false;
  return async (input, signal) => {
    if (consumed || signal.aborted) return invalid();
    consumed = true;
    const original = await requestFor(input);
    if (signal.aborted) return invalid();
    const raw = await exchange(original.frame, signal);
    if (
      signal.aborted || new TextEncoder().encode(raw).length > 300000 ||
      !raw.endsWith("\n")
    ) return invalid();
    let parsed: unknown;
    try {
      parsed = JSON.parse(raw);
    } catch {
      return invalid();
    }
    const header = closed(parsed, [
      "version",
      "kind",
      "grant_id",
      "source_digest",
      "ordinal",
      (parsed as { kind?: unknown })?.kind === "prepared" ? "answer" : "stage",
    ]);
    if (
      JSON.stringify(header) + "\n" !== raw || header.version !== 1 ||
      header.grant_id !== original.grant.grant_id ||
      header.source_digest !== original.grant.source_digest ||
      header.ordinal !== 0
    ) return invalid();
    if (header.kind === "rejected") {
      if (header.stage !== "validation" && header.stage !== "transform") {
        return invalid();
      }
      throw new LocalPreparationRejected(header.stage);
    }
    if (header.kind !== "prepared") return invalid();
    const a = closed(header.answer, [
      "version",
      "operation",
      "preserve_source_when_trimmed_too_short",
      "input_bytes",
      "input_sha256",
      "output_bytes",
      "output_sha256",
      "base64",
      "complete",
    ]);
    const output = decode(a.base64, 192000);
    if (
      a.version !== 2 || a.operation !== "validated_wav16k" ||
      a.preserve_source_when_trimmed_too_short !== false ||
      a.input_bytes !== original.bytes.length ||
      a.input_sha256 !== await byteDigest(original.bytes) ||
      a.output_bytes !== output.length ||
      a.output_sha256 !== await byteDigest(output) || a.complete !== true
    ) return invalid();
    return [new Uint8Array(output)];
  };
}
