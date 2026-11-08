/** Inactive post-dispatch byte verifier. No installed retention policy, SQL
 * bridge, adoption write, delivery route or provider execution is supplied. */
import { initialCanonicalText } from "./canonical.ts";
import {
  initialMediaHash,
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaTime,
  mediaUUID,
} from "./mediaBinding.ts";
import {
  type CpmPhotoContentType,
  type CpmWriteObservationBinding,
  type CpmWriteObservationDependencies,
  observeInitialCpmPhotoWrite,
  snapshotCpmWriteObservationBinding,
  snapshotCpmWriteObservationTarget,
} from "./cpmPhotoWriteObservation.ts";
import {
  type CpmPhotoVerificationContext,
  inspectCpmPhotoBytes,
  snapshotCpmPhotoVerificationContext,
} from "./cpmPhotoVerification.ts";
import {
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
} from "./transport.ts";

type Role = "source" | "ai" | "display";
type ObjectBinding = {
  photo_ordinal: number;
  role: Role;
  reference_id: string;
  object_id: string;
  backend_generation: string;
  backend_configuration_digest: string;
  namespace: "initial-preparation/v2";
  byte_count: number;
  sha256: string;
  content_type: string;
};
type Binding = {
  version: 1;
  variant: "cpm_in_place_adoption_v1";
  owner_id: string;
  scan_id: string;
  admission_receipt_id: string;
  admission_receipt_digest: string;
  cpm_verification_digest: string;
  retained_roles_digest: string;
  result_evidence_id: string;
  result_digest: string;
  retention_policy_digest: string;
  retention_build_digest: string;
  objects: ObjectBinding[];
};
type Policy = {
  write_policy_digest: string;
  retention_build_digest: string;
  qualification_evidence_digest: string;
  reviewed_revision: string;
  protocol: "cpm_in_place_adoption_v1";
  verification_max_duration_ms: number;
  verification_max_age_ms: number;
  clock_skew_ms: number;
};
export type CpmRetentionSnapshot = {
  binding: Binding;
  reads: CpmWriteObservationBinding[];
  profile_digest: string;
  verifier_build_digest: string;
  policy: Policy;
};
export interface CpmRetentionDependencies {
  /** Trusted bootstrap resolves the exact separately qualified terminal build,
   * original structural profile/build and saved backend. Labels alone do not
   * certify this executable; no default/latest or remotely selected build. */
  load(snapshot: Readonly<CpmRetentionSnapshot>, signal: AbortSignal): Promise<{
    retention_policy_digest: string;
    retention_build_digest: string;
    photo: CpmPhotoVerificationContext;
  }>;
  /** Terminal-only SQL reader must reconstruct this exact snapshot under the
   * original completion locks, with policy/backend eligibility and all account,
   * deletion, C1, retirement and marker fences. No lock spans storage I/O. */
  requireCurrent(
    snapshot: Readonly<CpmRetentionSnapshot>,
    signal: AbortSignal,
  ): Promise<void>;
  storage: Omit<CpmWriteObservationDependencies, "requireCurrent">;
}

function freeze<T>(value: T): T {
  if (value && typeof value === "object") {
    Object.values(value).forEach(freeze);
    Object.freeze(value);
  }
  return value;
}

function snapshot(value: unknown): CpmRetentionSnapshot {
  const canonical = initialCanonicalText(value);
  if (new TextEncoder().encode(canonical).byteLength > 65536) {
    throw initialMediaUnavailable();
  }
  const s = mediaRecord(JSON.parse(canonical), [
    "binding",
    "reads",
    "profile_digest",
    "verifier_build_digest",
    "policy",
  ]);
  const b = mediaRecord(s.binding, [
    "version",
    "variant",
    "owner_id",
    "scan_id",
    "admission_receipt_id",
    "admission_receipt_digest",
    "cpm_verification_digest",
    "retained_roles_digest",
    "result_evidence_id",
    "result_digest",
    "retention_policy_digest",
    "retention_build_digest",
    "objects",
  ]);
  if (b.version !== 1 || b.variant !== "cpm_in_place_adoption_v1") {
    throw initialMediaUnavailable();
  }
  for (
    const name of [
      "owner_id",
      "scan_id",
      "admission_receipt_id",
      "result_evidence_id",
    ]
  ) mediaUUID(b[name]);
  for (
    const name of [
      "admission_receipt_digest",
      "cpm_verification_digest",
      "retained_roles_digest",
      "result_digest",
      "retention_policy_digest",
      "retention_build_digest",
    ]
  ) mediaDigest(b[name]);
  mediaDigest(s.profile_digest);
  mediaDigest(s.verifier_build_digest);
  const p = mediaRecord(s.policy, [
    "write_policy_digest",
    "retention_build_digest",
    "qualification_evidence_digest",
    "reviewed_revision",
    "protocol",
    "verification_max_duration_ms",
    "verification_max_age_ms",
    "clock_skew_ms",
  ]);
  for (
    const name of [
      "write_policy_digest",
      "retention_build_digest",
      "qualification_evidence_digest",
    ]
  ) mediaDigest(p[name]);
  if (
    p.retention_build_digest !== b.retention_build_digest ||
    p.protocol !== b.variant || typeof p.reviewed_revision !== "string" ||
    !/^[0-9a-f]{40}$/.test(p.reviewed_revision)
  ) throw initialMediaUnavailable();
  for (
    const [name, low, high] of [["verification_max_duration_ms", 1, 150000], [
      "verification_max_age_ms",
      1,
      30000,
    ], ["clock_skew_ms", 0, 1000]] as const
  ) {
    const v = p[name];
    if (
      typeof v !== "number" || !Number.isSafeInteger(v) || v < low || v > high
    ) throw initialMediaUnavailable();
  }
  if (
    !Array.isArray(b.objects) || ![3, 6].includes(b.objects.length) ||
    !Array.isArray(s.reads) || s.reads.length !== b.objects.length
  ) throw initialMediaUnavailable();
  const objects = new Set<string>(),
    references = new Set<string>(),
    attempts = new Set<string>();
  let backend: string | undefined, assignment: string | undefined;
  for (const [index, member] of b.objects.entries()) {
    const o = mediaRecord(member, [
      "photo_ordinal",
      "role",
      "reference_id",
      "object_id",
      "backend_generation",
      "backend_configuration_digest",
      "namespace",
      "byte_count",
      "sha256",
      "content_type",
    ]);
    const r = snapshotCpmWriteObservationBinding(s.reads[index]);
    snapshotCpmWriteObservationTarget({
      outcome: "live_object",
      role: o.role,
      byte_count: o.byte_count,
      sha256: o.sha256,
      content_type: o.content_type,
    });
    const id = mediaUUID(o.object_id), ref = mediaUUID(o.reference_id);
    const key = `${mediaUUID(o.backend_generation)}/${
      mediaDigest(o.backend_configuration_digest)
    }`;
    if (
      o.photo_ordinal !== Math.floor(index / 3) ||
      o.role !== ["source", "ai", "display"][index % 3] ||
      o.namespace !== "initial-preparation/v2" || objects.has(id) ||
      references.has(ref) || attempts.has(r.attempt_id) ||
      r.object_id !== id || r.scan_id !== b.scan_id ||
      r.backend_generation !== o.backend_generation ||
      r.backend_configuration_digest !== o.backend_configuration_digest ||
      r.verification_policy_digest !== p.write_policy_digest ||
      (backend !== undefined && backend !== key) ||
      (assignment !== undefined && assignment !== r.assignment_digest)
    ) throw initialMediaUnavailable();
    objects.add(id);
    references.add(ref);
    attempts.add(r.attempt_id);
    backend = key;
    assignment = r.assignment_digest;
  }
  return freeze(s as unknown as CpmRetentionSnapshot);
}

/** Fresh actual-byte proof only. The interval begins before policy loading or
 * current-state checks, and every object is reopened exactly once. SQL must
 * reconstruct all bindings and check age again before settlement and adoption.
 * Errors propagate; no retry, fallback, new result or provider request occurs. */
export async function verifyInitialCpmRetention(
  deps: CpmRetentionDependencies,
  value: unknown,
  caller: AbortSignal,
) {
  const started = mediaTime(Date.now());
  const saved = snapshot(value);
  return await initialDeadline(
    caller,
    saved.policy.verification_max_duration_ms,
    async (signal) => {
      const current = () =>
        initialAbortable(signal, () => deps.requireCurrent(saved, signal));
      const digest = await initialMediaHash(new TextEncoder().encode(
        "merian.initial-analysis.cpm-retention-policy.v1\n" +
          initialCanonicalText({ version: 1, ...saved.policy }),
      ));
      if (
        digest !== saved.binding.retention_policy_digest
      ) throw initialMediaUnavailable();
      await current();
      const loaded = await initialAbortable(
        signal,
        () => deps.load(saved, signal),
      );
      if (
        loaded.retention_policy_digest !== digest ||
        loaded.retention_build_digest !== saved.binding.retention_build_digest
      ) throw initialMediaUnavailable();
      const policy = snapshotCpmPhotoVerificationContext(loaded.photo, saved);
      const backend = policy.backend as Record<string, unknown>;
      if (
        backend.generation !== saved.binding.objects[0].backend_generation ||
        backend.configuration_digest !==
          saved.binding.objects[0].backend_configuration_digest
      ) throw initialMediaUnavailable();
      await current();
      const scratch = new Uint8Array(
        Math.max(...saved.binding.objects.map((o) => o.byte_count)),
      );
      try {
        for (const [index, object] of saved.binding.objects.entries()) {
          let offset = 0, inspected = false;
          await observeInitialCpmPhotoWrite(
            { ...deps.storage, requireCurrent: current },
            saved.reads[index],
            {
              outcome: "live_object",
              role: object.role,
              byte_count: object.byte_count,
              sha256: object.sha256,
              content_type: object.content_type as CpmPhotoContentType,
            },
            policy.backend,
            signal,
            () => ({
              push(bytes) {
                checkInitialDeadline(signal);
                if (
                  bytes.byteLength > object.byte_count - offset
                ) throw initialMediaUnavailable();
                scratch.set(bytes, offset);
                offset += bytes.byteLength;
              },
              finish() {
                checkInitialDeadline(signal);
                if (offset !== object.byte_count) {
                  throw initialMediaUnavailable();
                }
                inspectCpmPhotoBytes(
                  scratch.subarray(0, offset),
                  object.content_type,
                  policy.dimensions[object.role],
                  signal,
                );
                inspected = true;
              },
              release() {
                scratch.fill(0);
              },
            }),
          );
          if (!inspected) throw initialMediaUnavailable();
        }
        await current();
        checkInitialDeadline(signal);
        const verified = mediaTime(Date.now());
        if (
          verified < started ||
          verified - started > saved.policy.verification_max_duration_ms
        ) throw initialMediaUnavailable();
        return freeze({
          ...saved.binding,
          verification_started_at_ms: started,
          verified_at_ms: verified,
        });
      } finally {
        scratch.fill(0);
      }
    },
  );
}
