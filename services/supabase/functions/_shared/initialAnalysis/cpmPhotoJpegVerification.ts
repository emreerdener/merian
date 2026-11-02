/** Inactive JPEG-only consuming increment. No installed profile/route or SQL
 * admission bridge. Other accepted original formats still require adapters;
 * their declarations are never converted or treated as JPEG proof. */
import { inspectJpegContainer } from "../analysisHistory/jpegContainer.ts";
import {
  type CpmAdmissionIdentity,
  type CpmPhotoAdmissionBridge,
  type CpmVerificationStart,
  verifyAndAdmitInitialCpmPhoto,
} from "./cpmPhotoAdmission.ts";
import {
  type CpmWriteObservationDependencies,
  observeInitialCpmPhotoWrite,
  snapshotCpmWriteObservationTarget,
} from "./cpmPhotoWriteObservation.ts";
import { initialMediaUnavailable, mediaRecord } from "./mediaBinding.ts";
import { checkInitialDeadline, initialAbortable } from "./transport.ts";

type Role = "source" | "ai" | "display";
type Dimensions = {
  maximumWidth: number;
  maximumHeight: number;
  maximumPixels: number;
};
/** Fixed server catalog, resolved by BOTH saved digests. Limits are part of
 * the immutable verifier build, never caller-selected policy or moving flags.
 * No such catalog/profile is installed by this module. */
export interface CpmJpegVerificationContext {
  profile_digest: string;
  verifier_build_digest: string;
  dimensions: Record<Role, Dimensions>;
  backend: unknown;
}
export interface CpmJpegVerificationDependencies {
  load(
    start: Readonly<CpmVerificationStart>,
    signal: AbortSignal,
  ): Promise<CpmJpegVerificationContext>;
  /** Exact complete cohort, current owner/account/deletion/retirement fences.
   * Must validate the saved start, not simply that each object still exists. */
  requireCurrent(
    start: Readonly<CpmVerificationStart>,
    signal: AbortSignal,
  ): Promise<void>;
  storage: CpmWriteObservationDependencies;
}
type Snapshot = {
  profile_digest: string;
  verifier_build_digest: string;
  backend_generation: string;
  backend_configuration_digest: string;
  members: {
    role: {
      photo_ordinal: number;
      role: Role;
      object_id: string;
      declaration: {
        byte_count: number;
        sha256: string;
        declared_content_type: string;
      };
    };
    attempt: {
      attempt_id: string;
      issued_at: string;
      write_policy_digest: string;
    };
  }[];
};

function context(value: unknown, saved: Snapshot): CpmJpegVerificationContext {
  // Copy the bounded server metadata before any later awaits. No credentials
  // or storage responses enter this object; backend contains an opaque profile.
  const raw = JSON.stringify(value);
  if (typeof raw !== "string" || raw.length > 65_536) {
    throw initialMediaUnavailable();
  }
  const c = mediaRecord(JSON.parse(raw), [
    "profile_digest",
    "verifier_build_digest",
    "dimensions",
    "backend",
  ]);
  if (
    c.profile_digest !== saved.profile_digest ||
    c.verifier_build_digest !== saved.verifier_build_digest
  ) {
    throw initialMediaUnavailable();
  }
  const dimensions = mediaRecord(c.dimensions, ["source", "ai", "display"]);
  for (const role of ["source", "ai", "display"]) {
    const d = mediaRecord(dimensions[role], [
      "maximumWidth",
      "maximumHeight",
      "maximumPixels",
    ]);
    for (
      const [name, ceiling] of [["maximumWidth", 65535], [
        "maximumHeight",
        65535,
      ], ["maximumPixels", 65535 ** 2]] as const
    ) {
      if (
        typeof d[name] !== "number" || !Number.isSafeInteger(d[name]) ||
        d[name] < 1 || d[name] > ceiling
      ) throw initialMediaUnavailable();
    }
  }
  return c as unknown as CpmJpegVerificationContext;
}

/** The only entrypoint joins actual storage reads and JPEG structure checks to
 * the existing coordinator. Its private verify callback receives only the
 * coordinator-validated fresh committed start, never arbitrary caller proof. */
export function verifyAndAdmitInitialCpmJpegPhoto(
  bridge: Omit<CpmPhotoAdmissionBridge, "verify">,
  deps: CpmJpegVerificationDependencies,
  identity: CpmAdmissionIdentity,
  signal: AbortSignal,
) {
  return verifyAndAdmitInitialCpmPhoto(
    {
      recover: (identity, signal) => bridge.recover(identity, signal),
      begin: (identity, signal) => bridge.begin(identity, signal),
      admit: (evidence, signal) => bridge.admit(evidence, signal),
      verify: async (start, signal) => {
        const saved = JSON.parse(start.snapshot_canonical) as Snapshot;
        // Preflight the ENTIRE cohort before the first storage request. Preserve
        // the declaration vocabulary: unsupported adapters fail closed here.
        const targets = saved.members.map(({ role }) => {
          if (
            role.declaration.declared_content_type !== "image/jpeg"
          ) throw initialMediaUnavailable();
          return snapshotCpmWriteObservationTarget({
            outcome: "live_object",
            role: role.role,
            byte_count: role.declaration.byte_count,
            sha256: role.declaration.sha256,
            content_type: "image/jpeg",
          });
        });
        const current = () =>
          initialAbortable(signal, () => deps.requireCurrent(start, signal));
        await current();
        const policy = context(
          await initialAbortable(signal, () => deps.load(start, signal)),
          saved,
        );
        await current();
        // One reusable bounded buffer, not a retained cohort or chunks+aggregate.
        // Actual worker/RSS/transport cancellation still need qualification.
        const scratch = new Uint8Array(
          Math.max(...saved.members.map((m) => m.role.declaration.byte_count)),
        );
        const objects = [];
        try {
          for (const [index, member] of saved.members.entries()) {
            const { role, attempt } = member;
            const size = role.declaration.byte_count;
            let offset = 0, inspected = false;
            await current();
            await observeInitialCpmPhotoWrite(
              {
                ...deps.storage,
                requireCurrent: async (binding, target, signal) => {
                  await initialAbortable(
                    signal,
                    () => deps.requireCurrent(start, signal),
                  );
                  await initialAbortable(
                    signal,
                    () => deps.storage.requireCurrent(binding, target, signal),
                  );
                },
              },
              {
                attempt_id: attempt.attempt_id,
                scan_id: start.scan_id,
                object_id: role.object_id,
                assignment_digest: start.assignment_digest,
                backend_generation: saved.backend_generation,
                backend_configuration_digest:
                  saved.backend_configuration_digest,
                issued_at_ms: Date.parse(attempt.issued_at),
                verification_policy_digest: attempt.write_policy_digest,
              },
              targets[index],
              policy.backend,
              signal,
              () => ({
                push(bytes) {
                  checkInitialDeadline(signal);
                  if (
                    bytes.byteLength > size - offset
                  ) throw initialMediaUnavailable();
                  scratch.set(bytes, offset);
                  offset += bytes.byteLength;
                },
                finish() {
                  checkInitialDeadline(signal);
                  if (offset !== size) throw initialMediaUnavailable();
                  inspectJpegContainer(scratch.subarray(0, size), () => {
                    // Private source/derivative metadata is preserved, not decoded,
                    // sanitized or claimed safe for publication by this verifier.
                    checkInitialDeadline(signal);
                  }, { ...policy.dimensions[role.role], maximumBytes: size });
                  checkInitialDeadline(signal);
                  inspected = true;
                },
                release() {
                  scratch.fill(0, 0, size);
                },
              }),
            );
            checkInitialDeadline(signal);
            if (!inspected) throw initialMediaUnavailable();
            objects.push({
              object_id: role.object_id,
              photo_ordinal: role.photo_ordinal,
              role: role.role,
              byte_count: size,
              sha256: role.declaration.sha256,
              content_type: "image/jpeg",
              structural_acceptance: true,
            });
          }
          await current();
          checkInitialDeadline(signal);
          return {
            version: 1,
            protocol: "cpm_photo_full_bytes_v1",
            attempt_id: start.attempt_id,
            snapshot_digest: start.snapshot_digest,
            profile_digest: saved.profile_digest,
            verifier_build_digest: saved.verifier_build_digest,
            objects,
          };
        } finally {
          scratch.fill(0);
        }
      },
    },
    identity,
    signal,
  );
}
