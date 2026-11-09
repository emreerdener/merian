/** Fixed private result transport for the uninstalled S0 integration. SQL must
 * still enforce original invocation, ownership, immutable replay and erasure.
 * No route imports this module and no producer/grant is added here. */
import {
  decodeInitialCompletionAcquisition,
  type InitialCompletionAdmission,
  snapshotInitialCompletionAdmission,
} from "./completionAcquisition.ts";
import { fetchWithDeadline } from "../outbound.ts";
import {
  decodeInitialStatusAdmission,
  decodeInitialStatusRecoveryRequest,
  type InitialStatusCpmBinding,
} from "./completionStatusRequest.ts";
import { serviceRoleRequestHeaders } from "../serviceRoleAuth.ts";
import {
  decodeInitialCompletionDelivery,
  type InitialCompletionDelivery,
  type InitialCompletionRequestBinding,
  snapshotInitialCompletionRequestBinding,
} from "./completionDelivery.ts";
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { mediaDigest, mediaRecord, mediaUUID } from "./mediaBinding.ts";
import {
  decodeInitialResult,
  type InitialResultReference,
  type InitialResultStore,
  snapshotCapturedInitialResult,
  snapshotInitialResultReference,
} from "./resultEvidence.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "./transport.ts";

const encoder = new TextEncoder();
const unavailable = () =>
  new Error("initial_analysis_result_store_unavailable");
const envelopeBytes = 2 * (1048576 + 65536) + 4096;
const completionEnvelopeBytes = envelopeBytes + 2 * (16384 + 65536) + 2048;
export interface InitialResultDeliveryStore extends InitialResultStore {
  readCompletion(
    reference: Readonly<InitialResultReference & { result_digest: string }>,
    signal: AbortSignal,
  ): Promise<Readonly<InitialCompletionDelivery> | null>;
}

export function createInitialResultStore(input: {
  reference: InitialResultReference;
  /** Independently retained original configuration, not derived from a reply. */
  originalProvenanceCanonical: string;
  /** Required only for completion reads; independently saved admission facts. */
  completionBinding?: InitialCompletionRequestBinding;
  /** Omit on restart/read-only recovery. Missing lease forbids writes. */
  leaseToken?: string;
  origin: string;
  serverApiKey: string;
  fetcher?: typeof fetch;
}): InitialResultDeliveryStore {
  const original = snapshotInitialResultReference(input.reference);
  const originalText = initialCanonicalText(original);
  const provenance = input.originalProvenanceCanonical;
  if (
    typeof provenance !== "string" || encoder.encode(provenance).length > 65536
  ) throw unavailable();
  parseInitialCanonicalText(provenance);
  const completionBinding = input.completionBinding === undefined
    ? null
    : snapshotInitialCompletionRequestBinding(input.completionBinding);
  const lease = input.leaseToken === undefined
    ? null
    : mediaUUID(input.leaseToken);
  const call = createResultRPC(input);
  function sameReference(value: unknown) {
    if (
      initialCanonicalText(snapshotInitialResultReference(value)) !==
        originalText
    ) throw unavailable();
  }
  function readRequest(request: unknown) {
    const r = mediaRecord(
      parseInitialCanonicalText(initialCanonicalText(request)),
      [
        "owner_id",
        "scan_id",
        "invocation_id",
        "result_evidence_id",
        "submission_digest",
        "config_digest",
        "funding_binding_digest",
        "result_digest",
      ],
    );
    const { result_digest: expectedDigest, ...requested } = r;
    sameReference(requested);
    return mediaDigest(expectedDigest);
  }
  return Object.freeze<InitialResultDeliveryStore>({
    async write(value, caller) {
      if (lease === null) throw unavailable();
      const evidence = snapshotCapturedInitialResult(value);
      sameReference(evidence.reference);
      // Copy all request facts before hashing awaits, including the original lease.
      await initialDeadline(caller, 5000, async (signal) => {
        await initialAbortable(
          signal,
          () => decodeInitialResult(evidence, original, provenance),
        );
        const reply = mediaRecord(
          await call("record_initial_analysis_result", {
            p_owner: original.owner_id,
            p_scan: original.scan_id,
            p_submission_digest: original.submission_digest,
            p_invocation: original.invocation_id,
            p_lease_token: lease,
            p_result_evidence: original.result_evidence_id,
            p_result: evidence.result_canonical,
            p_provenance: evidence.provenance_canonical,
            p_result_digest: evidence.result_digest,
          }, signal),
          [
            "version",
            "outcome",
            "reference",
            "result_digest",
            "provenance_digest",
          ],
        );
        if (
          reply.version !== 1 ||
          (reply.outcome !== "recorded" && reply.outcome !== "replay") ||
          reply.result_digest !== evidence.result_digest ||
          reply.provenance_digest !== evidence.provenance_digest
        ) throw unavailable();
        sameReference(reply.reference);
      });
    },
    async read(request, caller) {
      // The request is a closed original reference with one expected digest.
      const expected = readRequest(request);
      return await initialDeadline(caller, 5000, async (signal) => {
        const reply = mediaRecord(
          await call("read_initial_analysis_result", {
            p_owner: original.owner_id,
            p_scan: original.scan_id,
            p_submission_digest: original.submission_digest,
            p_result_evidence: original.result_evidence_id,
            p_result_digest: expected,
          }, signal),
          ["version", "outcome", "reference", "result_digest", "evidence"],
        );
        if (reply.version !== 1 || reply.result_digest !== expected) {
          throw unavailable();
        }
        sameReference(reply.reference);
        if (reply.outcome === "absent" && reply.evidence === null) return null;
        if (reply.outcome !== "found") throw unavailable();
        const evidence = snapshotCapturedInitialResult(reply.evidence);
        if (evidence.result_digest !== expected) throw unavailable();
        await initialAbortable(
          signal,
          () => decodeInitialResult(evidence, original, provenance),
        );
        return evidence;
      });
    },
    async readCompletion(request, caller) {
      if (completionBinding === null) throw unavailable();
      const expected = readRequest(request);
      return await initialDeadline(caller, 5000, async (signal) => {
        const reply = await call("read_initial_completion_v1", {
          p_owner: original.owner_id,
          p_scan: original.scan_id,
          p_submission: original.submission_digest,
          p_result: original.result_evidence_id,
          p_result_digest: expected,
        }, signal);
        return await initialAbortable(
          signal,
          () =>
            decodeInitialCompletionDelivery(
              reply,
              original,
              expected,
              provenance,
              completionBinding,
            ),
        );
      });
    },
  });
}

type ResultRPCOptions = {
  origin: string;
  serverApiKey: string;
  fetcher?: typeof fetch;
};
function createResultRPC(input: ResultRPCOptions) {
  const base = new URL(input.origin);
  if (
    base.username || base.password || base.pathname !== "/" || base.search ||
    base.hash ||
    !(base.protocol === "https:" ||
      (base.protocol === "http:" &&
        ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname)))
  ) throw unavailable();
  const headers = Object.freeze({
    ...serviceRoleRequestHeaders(input.serverApiKey),
    "Content-Type": "application/json",
    "Accept": "application/json",
  });
  const fetcher = input.fetcher ?? fetch;
  async function call(
    operation:
      | "record_initial_analysis_result"
      | "read_initial_analysis_result"
      | "read_initial_completion_v1"
      | "discover_initial_completion_v1"
      | "read_initial_cpm_saved_admission_v1",
    args: Record<string, unknown>,
    caller: AbortSignal,
  ) {
    return await initialDeadline(caller, 5000, async (signal) => {
      const body = JSON.stringify(args);
      if (encoder.encode(body).length > envelopeBytes) throw unavailable();
      const response = await initialAbortable(
        signal,
        () =>
          fetchWithDeadline(new URL(`/rest/v1/rpc/${operation}`, base), {
            method: "POST",
            headers,
            body,
            signal,
            redirect: "error",
            cache: "no-store",
            credentials: "omit",
          }, { fetcher, timeoutMs: 5000 }),
        (late) => cancelInitialStream(late.body),
      );
      const bytes = await readInitialStream(
        response.body,
        operation === "read_initial_cpm_saved_admission_v1"
          ? 2 * (65536 + 8192) + 4096
          : operation === "record_initial_analysis_result"
          ? 8192
          : operation === "discover_initial_completion_v1"
          ? completionEnvelopeBytes + 2 * (65536 + 4096) + 4096
          : operation === "read_initial_completion_v1"
          ? completionEnvelopeBytes
          : envelopeBytes,
        signal,
      );
      if (response.status !== 200) throw unavailable();
      const value: unknown = JSON.parse(
        new TextDecoder("utf-8", { fatal: true }).decode(bytes),
      );
      checkInitialDeadline(signal);
      return value;
    });
  }
  return call;
}

/** Inactive first acquisition; trusted admission facts must already be saved. */
export function createInitialCompletionAcquisition(
  input: ResultRPCOptions & {
    admission: InitialCompletionAdmission;
  },
) {
  const admission = snapshotInitialCompletionAdmission(input.admission);
  const canonical = initialCanonicalText(admission);
  const call = createResultRPC(input);
  return Object.freeze({
    async read(caller: AbortSignal) {
      return await initialDeadline(caller, 5000, async (signal) => {
        const reply = await call("discover_initial_completion_v1", {
          p_owner: admission.owner_id,
          p_scan: admission.scan_id,
          p_admission: canonical,
        }, signal);
        return await initialAbortable(
          signal,
          () => decodeInitialCompletionAcquisition(reply, admission),
        );
      });
    },
  });
}

/** Inactive authenticated-owner admission read using only native saved facts.
 * Authentication must precede this factory; no current eligibility or repair. */
export async function createInitialSavedAdmissionAcquisition(
  input: ResultRPCOptions & {
    original: InitialStatusCpmBinding;
    authenticatedOwnerID: string;
  },
) {
  const call = createResultRPC(input);
  const request = await decodeInitialStatusRecoveryRequest({
    initial_recovery: {
      version: 1,
      phase: "admission",
      original: input.original,
    },
  }, input.authenticatedOwnerID);
  if (request.phase !== "admission") throw unavailable();
  const original = request.original;
  return Object.freeze({
    async read(caller: AbortSignal) {
      return await initialDeadline(caller, 5000, async (signal) => {
        const reply = await call("read_initial_cpm_saved_admission_v1", {
          p_owner: original.owner_id,
          p_scan: original.scan_id,
          p_candidate: original.candidate_canonical,
          p_candidate_digest: original.candidate_digest,
          p_content_digest: original.content_digest,
          p_assignment_digest: original.assignment_digest,
          p_backend_generation: original.backend_generation,
          p_backend_configuration_digest: original.backend_configuration_digest,
        }, signal);
        return await initialAbortable(
          signal,
          () => decodeInitialStatusAdmission(reply, original),
        );
      });
    },
  });
}
