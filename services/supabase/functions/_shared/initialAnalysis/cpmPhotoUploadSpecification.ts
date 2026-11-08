/** Inactive request planning only. No credentials, signer, Request, fetch or
 * issuance authority. A specification cannot establish payload enforcement,
 * current eligibility, durable possible issuance or remote write closure. */
import { snapshotCpmWriteObservationTarget } from "./cpmPhotoWriteObservation.ts";
import { decodeHandoffSourceBackend } from "./mediaHandoffStorage.ts";
import {
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaTime,
  mediaUUID,
} from "./mediaBinding.ts";

/** Trusted host configuration, never an inbound client profile selection.
 * This descriptor contains no credentials and confers no provider authority. */
export interface CpmPhotoUploadProfile {
  credential_profile: string;
  backend_generation: string;
  backend_configuration_digest: string;
}

/** Freeze metadata before backend digest verification suspends. The existing
 * backend digest binds endpoint, bucket, namespace, profile and protocol. The
 * injected allowlist separately limits which saved configuration is planned.
 * Historical/expired specifications remain metadata, never fresh permission.
 * A future issuer must independently fence original state and persist possible
 * issuance before any capability exposure; replay cannot sign again. */
export async function prepareCpmPhotoUploadSpecification(
  value: unknown,
  allowedProfiles: readonly CpmPhotoUploadProfile[],
) {
  const r = mediaRecord(value, [
    "binding",
    "target",
    "backend",
    "created_at_ms",
    "admission_expires_at_ms",
    "capability_expires_at_ms",
  ]);
  const binding = Object.freeze({
    ...mediaRecord(r.binding, [
      "attempt_id",
      "scan_id",
      "object_id",
      "assignment_digest",
      "backend_generation",
      "backend_configuration_digest",
    ]),
  });
  for (
    const key of ["attempt_id", "scan_id", "object_id", "backend_generation"]
  ) {
    mediaUUID(binding[key]);
  }
  mediaDigest(binding.assignment_digest);
  mediaDigest(binding.backend_configuration_digest);
  const target = snapshotCpmWriteObservationTarget(r.target);
  // Marker replacement has a separate original-claim owner and must not use
  // conditional creation: an existing live object needs to be overwritten.
  if (target.outcome !== "live_object") throw initialMediaUnavailable();
  const created = mediaTime(r.created_at_ms);
  const admission = mediaTime(r.admission_expires_at_ms);
  const expiry = mediaTime(r.capability_expires_at_ms);
  if (
    admission <= created || expiry <= created ||
    !Number.isSafeInteger(created + 600_000) ||
    expiry !== Math.min(admission, created + 600_000)
  ) throw initialMediaUnavailable();
  const backendValue = {
    ...mediaRecord(r.backend, [
      "generation",
      "configuration_digest",
      "provider",
      "direct_endpoint",
      "private_bucket",
      "namespace",
      "credential_profile",
      "storage_protocol",
    ]),
  };
  if (
    !Array.isArray(allowedProfiles) || allowedProfiles.length < 1 ||
    allowedProfiles.length > 16
  ) throw initialMediaUnavailable();
  const seen = new Set<string>();
  const profiles = allowedProfiles.map((entry) => {
    const p = {
      ...mediaRecord(entry, [
        "credential_profile",
        "backend_generation",
        "backend_configuration_digest",
      ]),
    };
    if (
      typeof p.credential_profile !== "string" ||
      !/^[a-z][a-z0-9_]{0,63}$/.test(p.credential_profile) ||
      seen.has(p.credential_profile)
    ) throw initialMediaUnavailable();
    seen.add(p.credential_profile);
    mediaUUID(p.backend_generation);
    mediaDigest(p.backend_configuration_digest);
    return Object.freeze(p);
  });
  const profile = profiles.find((p) =>
    p.credential_profile === backendValue.credential_profile
  );
  if (
    !profile || profile.backend_generation !== binding.backend_generation ||
    profile.backend_configuration_digest !==
      binding.backend_configuration_digest
  ) throw initialMediaUnavailable();
  const backend = await decodeHandoffSourceBackend(
    backendValue,
    mediaUUID(binding.backend_generation),
    mediaDigest(binding.backend_configuration_digest),
  );
  return Object.freeze({
    kind: "unqualified_cpm_upload_specification" as const,
    binding,
    target,
    profile,
    created_at_ms: created,
    admission_expires_at_ms: admission,
    capability_expires_at_ms: expiry,
    method: "PUT" as const,
    destination: Object.freeze({
      direct_endpoint: backend.direct_endpoint,
      private_bucket: backend.private_bucket,
      key: `${backend.namespace}/${binding.scan_id}/${binding.object_id}`,
    }),
    headers: Object.freeze({
      "If-None-Match": "*",
      "Content-Type": target.content_type,
      "Content-Length": String(target.byte_count),
      "Cache-Control": "private, no-store",
    }),
    payload_integrity: Object.freeze({
      required_algorithm: "sha256" as const,
      required_digest: target.sha256,
      provider_enforcement: "unqualified" as const,
    }),
  });
}
