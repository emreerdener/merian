/** Dormant fixed service transport for the trusted CPM verifier composition.
 * No route imports this module. Client declarations are never verifier evidence.
 * Capture the server-derived IP hash once; callers cannot choose funding facts. */
import type {
  CpmAdmissionIdentity,
  CpmPhotoAdmissionBridge,
  CpmVerificationStart,
} from "./cpmPhotoAdmission.ts";
import {
  initialCanonicalText,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { initialCpmPhotoAssignmentDigest } from "./cpmPhotoAssignment.ts";
import { parseInitialCpmPhotoCandidate } from "./cpmPhotoCandidate.ts";
import {
  initialMediaHash,
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaUUID,
} from "./mediaBinding.ts";
import { matchesInitialSchema } from "./schema.ts";
import schema from "./cpm-admission-bridge-response-schema-v1.json" with {
  type: "json",
};
import currentSchema from "./cpm-verification-current-response-schema-v1.json" with {
  type: "json",
};
import {
  type CpmCompletionAdmissionBinding,
  decodeCpmCompletionAdmission,
  snapshotCpmCompletionAdmissionBinding,
} from "./cpmCompletionAdmission.ts";
import { fetchWithDeadline } from "../outbound.ts";
import {
  requireServerApiKeyFromEnvironment,
  serviceRoleRequestHeaders,
} from "../serviceRoleAuth.ts";
import {
  cancelInitialStream,
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
  readInitialStream,
} from "./transport.ts";

function snapshot(value: Readonly<CpmAdmissionIdentity>) {
  const r = mediaRecord(value, [
    "owner_id",
    "scan_id",
    "candidate_canonical",
    "assignment_canonical",
    "assignment_digest",
  ]);
  const owner = mediaUUID(r.owner_id),
    scan = mediaUUID(r.scan_id),
    digest = mediaDigest(r.assignment_digest);
  if (
    typeof r.candidate_canonical !== "string" ||
    typeof r.assignment_canonical !== "string" ||
    new TextEncoder().encode(r.candidate_canonical).length > 1048576 ||
    new TextEncoder().encode(r.assignment_canonical).length > 65536
  ) throw initialMediaUnavailable();
  parseInitialCpmPhotoCandidate(r.candidate_canonical);
  return Object.freeze({
    owner_id: owner,
    scan_id: scan,
    candidate_canonical: r.candidate_canonical,
    assignment_canonical: r.assignment_canonical,
    assignment_digest: digest,
  });
}
function decode(value: unknown, identity: Readonly<CpmAdmissionIdentity>) {
  const r = JSON.parse(initialCanonicalText(value));
  if (
    !matchesInitialSchema(r, schema) || r.owner_id !== identity.owner_id ||
    r.scan_id !== identity.scan_id ||
    r.assignment_digest !== identity.assignment_digest ||
    r.candidate_digest !==
      JSON.parse(identity.assignment_canonical).candidate_digest ||
    (r.outcome === "admitted"
      ? r.admission_receipt_id === null || r.admission_receipt_digest === null
      : r.admission_receipt_id !== null || r.admission_receipt_digest !== null)
  ) throw initialMediaUnavailable();
  return r.outcome === "admitted";
}

export function createCpmPhotoAdmissionDb(
  trustedIpHash: string,
  fetcher: typeof fetch = fetch,
): Omit<CpmPhotoAdmissionBridge, "verify"> & {
  readCompletionAdmission(
    original: CpmCompletionAdmissionBinding,
    signal: AbortSignal,
  ): Promise<Awaited<ReturnType<typeof decodeCpmCompletionAdmission>>>;
  requireCurrent(
    start: Readonly<CpmVerificationStart>,
    signal: AbortSignal,
  ): Promise<void>;
} {
  mediaDigest(trustedIpHash);
  const base = new URL(Deno.env.get("SUPABASE_URL") ?? "");
  if (
    base.username || base.password || base.pathname !== "/" || base.search ||
    base.hash ||
    !(base.protocol === "https:" || (base.protocol === "http:" &&
      ["localhost", "127.0.0.1", "[::1]"].includes(base.hostname)))
  ) throw initialMediaUnavailable();
  const headers = {
    ...serviceRoleRequestHeaders(requireServerApiKeyFromEnvironment()),
    "Content-Type": "application/json",
    "Accept": "application/json",
  };
  async function call(
    operation:
      | "read_initial_cpm_photo_admission"
      | "read_initial_cpm_completion_admission_v1"
      | "begin_initial_cpm_photo_admission"
      | "admit_initial_cpm_photo"
      | "assert_initial_cpm_photo_verification_current",
    identity: Readonly<CpmAdmissionIdentity>,
    signal: AbortSignal,
    verification?: string,
    current?: Readonly<
      Pick<
        CpmVerificationStart,
        "attempt_id" | "snapshot_canonical" | "snapshot_digest"
      >
    >,
    acknowledgement?: Readonly<
      Pick<
        CpmCompletionAdmissionBinding,
        "backend_generation" | "backend_configuration_digest"
      >
    >,
  ) {
    return await initialDeadline(signal, 5000, async (phase) => {
      try {
        if (
          (operation === "read_initial_cpm_completion_admission_v1") !==
            (acknowledgement !== undefined)
        ) {
          throw initialMediaUnavailable();
        }
        const candidate = parseInitialCanonicalText(
          identity.candidate_canonical,
        );
        const assignment = parseInitialCanonicalText(
          identity.assignment_canonical,
        );
        if (
          await initialAbortable(
              phase,
              () => initialCpmPhotoAssignmentDigest(candidate, assignment),
            ) !==
            identity.assignment_digest ||
          JSON.parse(identity.assignment_canonical).scan_id !== identity.scan_id
        ) throw initialMediaUnavailable();
        if (
          current && await initialAbortable(phase, () =>
              initialMediaHash(
                new TextEncoder().encode(
                  `merian.initial-analysis.cpm-verification-start.v1\n${current.snapshot_canonical}`,
                ),
              )) !== current.snapshot_digest
        ) throw initialMediaUnavailable();
        const body = JSON.stringify(
          current
            ? {
              p_owner: identity.owner_id,
              p_scan: identity.scan_id,
              p_assignment_digest: identity.assignment_digest,
              p_attempt: current.attempt_id,
              p_snapshot_digest: current.snapshot_digest,
            }
            : {
              p_owner: identity.owner_id,
              p_scan: identity.scan_id,
              p_candidate: identity.candidate_canonical,
              p_assignment: identity.assignment_canonical,
              p_assignment_digest: identity.assignment_digest,
              ...(acknowledgement === undefined ? {} : {
                p_backend_generation: acknowledgement.backend_generation,
                p_backend_configuration_digest:
                  acknowledgement.backend_configuration_digest,
              }),
              ...(verification === undefined
                ? {}
                : { p_verification: verification, p_ip_hash: trustedIpHash }),
            },
        );
        // Canonical strings can double in size when nested in the RPC envelope.
        // Accommodate the full accepted candidate plus 64 KiB assignment/evidence.
        if (
          new TextEncoder().encode(body).length >
            2 * (1048576 + 65536 + 65536) + 4096
        ) throw initialMediaUnavailable();
        checkInitialDeadline(phase);
        const response = await initialAbortable(
          phase,
          () =>
            fetchWithDeadline(new URL(`/rest/v1/rpc/${operation}`, base), {
              method: "POST",
              headers,
              body,
              signal: phase,
              redirect: "error",
              cache: "no-store",
              credentials: "omit",
            }, { fetcher, timeoutMs: 5000 }),
          (late) => cancelInitialStream(late.body),
        );
        const bytes = await readInitialStream(
          response.body,
          acknowledgement ? 8192 : 262144,
          phase,
        );
        if (response.status !== 200) throw initialMediaUnavailable();
        const value: unknown = JSON.parse(
          new TextDecoder("utf-8", { fatal: true }).decode(bytes),
        );
        checkInitialDeadline(phase);
        return value;
      } catch {
        throw initialMediaUnavailable();
      }
    });
  }
  return Object.freeze({
    async readCompletionAdmission(value, signal) {
      return await initialDeadline(signal, 5000, async (phase) => {
        const original = await initialAbortable(
          phase,
          () => snapshotCpmCompletionAdmissionBinding(value),
        );
        const reply = await call(
          "read_initial_cpm_completion_admission_v1",
          original,
          phase,
          undefined,
          undefined,
          original,
        );
        return await initialAbortable(
          phase,
          () => decodeCpmCompletionAdmission(reply, original),
        );
      });
    },
    async requireCurrent(value, signal) {
      const identity = snapshot({
        owner_id: value.owner_id,
        scan_id: value.scan_id,
        candidate_canonical: value.candidate_canonical,
        assignment_canonical: value.assignment_canonical,
        assignment_digest: value.assignment_digest,
      });
      const current = Object.freeze({
        attempt_id: mediaUUID(value.attempt_id),
        snapshot_digest: mediaDigest(value.snapshot_digest),
        snapshot_canonical: value.snapshot_canonical,
      });
      if (
        typeof current.snapshot_canonical !== "string" ||
        new TextEncoder().encode(current.snapshot_canonical).length > 65536 ||
        initialCanonicalText(
            parseInitialCanonicalText(current.snapshot_canonical),
          ) !== current.snapshot_canonical
      ) {
        throw initialMediaUnavailable();
      }
      const result = await call(
        "assert_initial_cpm_photo_verification_current",
        identity,
        signal,
        undefined,
        current,
      );
      const expected = {
        version: 1,
        outcome: "current",
        authority: "none",
        owner_id: identity.owner_id,
        scan_id: identity.scan_id,
        assignment_digest: identity.assignment_digest,
        attempt_id: current.attempt_id,
        snapshot_digest: current.snapshot_digest,
      };
      if (
        !matchesInitialSchema(result, currentSchema) ||
        initialCanonicalText(result) !== initialCanonicalText(expected)
      ) throw initialMediaUnavailable();
    },
    async recover(value, signal) {
      const identity = snapshot(value);
      return decode(
        await call("read_initial_cpm_photo_admission", identity, signal),
        identity,
      );
    },
    async begin(value, signal) {
      const identity = snapshot(value);
      // Coordinator owns the strict fresh-start decoder and one-use semantics.
      return await call("begin_initial_cpm_photo_admission", identity, signal);
    },
    async admit(value, signal) {
      // Evidence has additional fields, but the saved identity is copied before
      // any await. SQL derives submission/context/funding rather than trusting them.
      const identity = snapshot({
        owner_id: value.owner_id,
        scan_id: value.scan_id,
        candidate_canonical: value.candidate_canonical,
        assignment_canonical: value.assignment_canonical,
        assignment_digest: value.assignment_digest,
      });
      const verification = value.verification_canonical;
      if (
        typeof verification !== "string" ||
        new TextEncoder().encode(verification).length > 65536 ||
        initialCanonicalText(parseInitialCanonicalText(verification)) !==
          verification
      ) throw initialMediaUnavailable();
      if (
        !decode(
          await call("admit_initial_cpm_photo", identity, signal, verification),
          identity,
        )
      ) throw initialMediaUnavailable();
    },
  });
}
