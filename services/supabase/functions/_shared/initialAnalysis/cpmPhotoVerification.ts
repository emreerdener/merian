/** Inactive private-photo consuming increment. No installed profile/route or SQL
 * admission bridge. HEIF nested-derived/non-alpha auxiliary/sequence forms remain unqualified;
 * declarations are never converted or treated as JPEG proof. */
import { inspectHeifContainer } from "../analysisHistory/heifContainer.ts";
import { inspectJpegContainer } from "../analysisHistory/jpegContainer.ts";
import { inspectWebpContainer } from "../analysisHistory/webpContainer.ts";
import { inspectPngContainer } from "../analysisHistory/pngContainer.ts";
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
import {
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaUUID,
} from "./mediaBinding.ts";
import { decodeHandoffSourceBackend } from "./mediaHandoffStorage.ts";
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
export interface CpmPhotoVerificationContext {
  profile_digest: string;
  verifier_build_digest: string;
  dimensions: Record<Role, Dimensions>;
  backend: unknown;
}
export interface CpmPhotoVerificationDependencies {
  load(
    start: Readonly<CpmVerificationStart>,
    signal: AbortSignal,
  ): Promise<CpmPhotoVerificationContext>;
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

function context(
  value: unknown,
  saved?: Pick<Snapshot, "profile_digest" | "verifier_build_digest">,
): CpmPhotoVerificationContext {
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
  mediaDigest(c.profile_digest);
  mediaDigest(c.verifier_build_digest);
  if (
    saved && (c.profile_digest !== saved.profile_digest ||
      c.verifier_build_digest !== saved.verifier_build_digest)
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
  return c as unknown as CpmPhotoVerificationContext;
}

/** Trusted bootstrap only: snapshot all entries before the first await. No
 * defaults, environment reads, credentials, installed entries or eligibility.
 * Reviewed build/profile digests are supplied by deployment composition; this
 * factory does not certify the executable build or grant verification authority.
 */
export async function cpmPhotoVerificationCatalog(
  values: readonly CpmPhotoVerificationContext[],
): Promise<Pick<CpmPhotoVerificationDependencies, "load">> {
  if (!Array.isArray(values) || values.length > 16) {
    throw initialMediaUnavailable();
  }
  const copied = values.map((value) => context(value));
  const entries = new Map<string, CpmPhotoVerificationContext>();
  const builds = new Map<string, string>();
  const profiles = new Map<string, string>();
  for (const entry of copied) {
    const dimensions = JSON.stringify(
      ["source", "ai", "display"].map((role) => {
        const d = entry.dimensions[role as Role];
        return [d.maximumWidth, d.maximumHeight, d.maximumPixels];
      }),
    );
    const previous = builds.get(entry.verifier_build_digest);
    const priorBuild = profiles.get(entry.profile_digest);
    if (
      (previous !== undefined && previous !== dimensions) ||
      (priorBuild !== undefined && priorBuild !== entry.verifier_build_digest)
    ) {
      throw initialMediaUnavailable();
    }
    builds.set(entry.verifier_build_digest, dimensions);
    profiles.set(entry.profile_digest, entry.verifier_build_digest);
    const raw = entry.backend as Record<string, unknown>;
    const generation = mediaUUID(raw?.generation);
    const digest = mediaDigest(raw?.configuration_digest);
    const backend = await decodeHandoffSourceBackend(raw, generation, digest);
    const key =
      `${entry.profile_digest}/${entry.verifier_build_digest}/${generation}/${digest}`;
    if (entries.has(key)) throw initialMediaUnavailable();
    for (const role of ["source", "ai", "display"] as const) {
      Object.freeze(entry.dimensions[role]);
    }
    entries.set(
      key,
      Object.freeze({
        ...entry,
        dimensions: Object.freeze(entry.dimensions),
        backend,
      }),
    );
  }
  return Object.freeze({
    load(start: Readonly<CpmVerificationStart>, signal: AbortSignal) {
      checkInitialDeadline(signal);
      // Invoked only inside the coordinator's committed fresh-start callback.
      // Retained recovery and held starts must never consult current catalog state.
      if (
        typeof start.snapshot_canonical !== "string" ||
        start.snapshot_canonical.length > 65536
      ) {
        throw initialMediaUnavailable();
      }
      const saved = JSON.parse(start.snapshot_canonical) as Snapshot;
      const key = `${mediaDigest(saved.profile_digest)}/${
        mediaDigest(saved.verifier_build_digest)
      }/${mediaUUID(saved.backend_generation)}/${
        mediaDigest(saved.backend_configuration_digest)
      }`;
      const entry = entries.get(key);
      if (!entry) throw initialMediaUnavailable();
      return Promise.resolve(entry);
    },
  });
}

/** The only entrypoint joins actual storage reads and image structure checks to
 * the existing coordinator. Its private verify callback receives only the
 * coordinator-validated fresh committed start, never arbitrary caller proof. */
export function verifyAndAdmitInitialCpmPhotoMedia(
  bridge: Omit<CpmPhotoAdmissionBridge, "verify">,
  deps: CpmPhotoVerificationDependencies,
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
            role.declaration.declared_content_type !== "image/jpeg" &&
            !(role.role === "source" &&
              ["image/png", "image/webp", "image/heic", "image/heif"].includes(
                role.declaration.declared_content_type,
              ))
          ) throw initialMediaUnavailable();
          return snapshotCpmWriteObservationTarget({
            outcome: "live_object",
            role: role.role,
            byte_count: role.declaration.byte_count,
            sha256: role.declaration.sha256,
            content_type: role.declaration.declared_content_type,
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
                  if (role.declaration.declared_content_type === "image/png") {
                    inspectPngContainer(scratch.subarray(0, size), {
                      ...policy.dimensions[role.role],
                      maximumBytes: size,
                    }, (type) => {
                      checkInitialDeadline(signal);
                      // Still-image increment only. Animation needs its own
                      // qualified interpretation; opaque metadata is preserved.
                      if (["acTL", "fcTL", "fdAT"].includes(type)) {
                        throw initialMediaUnavailable();
                      }
                    });
                  } else if (
                    role.declaration.declared_content_type === "image/webp"
                  ) {
                    inspectWebpContainer(
                      scratch.subarray(0, size),
                      {
                        ...policy.dimensions[role.role],
                        maximumBytes: size,
                      },
                      "private_still",
                      () => checkInitialDeadline(signal),
                    );
                  } else if (
                    role.declaration.declared_content_type === "image/heic" ||
                    role.declaration.declared_content_type === "image/heif"
                  ) {
                    inspectHeifContainer(
                      scratch.subarray(0, size),
                      role.declaration.declared_content_type,
                      { ...policy.dimensions[role.role], maximumBytes: size },
                      () => checkInitialDeadline(signal),
                    );
                  } else {
                    inspectJpegContainer(
                      scratch.subarray(0, size),
                      () => {
                        // Private source/derivative metadata is preserved, not decoded,
                        // sanitized or claimed safe for publication by this verifier.
                        checkInitialDeadline(signal);
                      },
                      { ...policy.dimensions[role.role], maximumBytes: size },
                    );
                  }
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
              content_type: role.declaration.declared_content_type,
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
