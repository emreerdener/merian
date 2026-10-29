/** Dormant concrete CPM issuer. No route, credentials or profile installation.
 * A returned capability is secret; never log it. Hosted payload enforcement and
 * alternate-writer/retention qualification remain activation prerequisites. */
import { getS3Client } from "../aws.ts";
import {
  type CpmPhotoUploadProfile,
  prepareCpmPhotoUploadSpecification,
} from "./cpmPhotoUploadSpecification.ts";
import {
  type CpmWriteClosureBridge,
  snapshotCpmWriteClosureInput,
} from "./cpmPhotoWriteClosure.ts";
import {
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaTime,
  mediaUUID,
} from "./mediaBinding.ts";
import {
  checkInitialDeadline,
  initialAbortable,
  initialDeadline,
} from "./transport.ts";

export interface CpmPhotoIssuanceIdentity {
  owner: string;
  scan: string;
  assignment_digest: string;
  object: string;
  policy: string;
}
export interface CpmPhotoIssuanceBridge
  extends Pick<CpmWriteClosureBridge, "requireCurrent"> {
  /** One committed service RPC acknowledgement, never a cached fresh result.
   * Timeout/unknown status must throw, without retrying or synthesizing fresh. */
  begin(
    identity: Readonly<CpmPhotoIssuanceIdentity>,
    signal: AbortSignal,
  ): Promise<unknown>;
}
export interface CpmPhotoIssuerProfile extends CpmPhotoUploadProfile {
  /** Explicit trusted host configuration, never client input or v1 fallback. */
  access_key_id: string;
  secret_access_key: string;
}
export function snapshotCpmPhotoIssuanceIdentity(value: unknown) {
  const r = mediaRecord(value, [
    "owner",
    "scan",
    "assignment_digest",
    "object",
    "policy",
  ]);
  return Object.freeze({
    owner: mediaUUID(r.owner),
    scan: mediaUUID(r.scan),
    assignment_digest: mediaDigest(r.assignment_digest),
    object: mediaUUID(r.object),
    policy: mediaDigest(r.policy),
  });
}
function profilesSnapshot(values: readonly CpmPhotoIssuerProfile[]) {
  if (!Array.isArray(values) || values.length < 1 || values.length > 16) {
    throw initialMediaUnavailable();
  }
  const seen = new Set<string>();
  return values.map((value) => {
    const r = mediaRecord(value, [
      "credential_profile",
      "backend_generation",
      "backend_configuration_digest",
      "access_key_id",
      "secret_access_key",
    ]);
    if (
      typeof r.credential_profile !== "string" ||
      !/^[a-z][a-z0-9_]{0,63}$/.test(r.credential_profile) ||
      seen.has(r.credential_profile)
    ) throw initialMediaUnavailable();
    seen.add(r.credential_profile);
    for (const key of ["access_key_id", "secret_access_key"]) {
      if (
        typeof r[key] !== "string" ||
        !/^[A-Za-z0-9/+_=.-]{16,256}$/.test(r[key])
      ) throw initialMediaUnavailable();
    }
    return Object.freeze({
      credential_profile: r.credential_profile,
      backend_generation: mediaUUID(r.backend_generation),
      backend_configuration_digest: mediaDigest(r.backend_configuration_digest),
      access_key_id: r.access_key_id as string,
      secret_access_key: r.secret_access_key as string,
    });
  });
}

/** One begin, at most one local signature, no storage request and no retry.
 * Fresh metadata cannot be submitted directly by a caller. Replays return only
 * held identity; failure after begin leaves the durable possibly-issued hold.
 * SQL fences remain authoritative; no lock spans signing or delivery. */
export async function issueInitialCpmPhotoUpload(
  bridge: CpmPhotoIssuanceBridge,
  identity: CpmPhotoIssuanceIdentity,
  profiles: readonly CpmPhotoIssuerProfile[],
  caller: AbortSignal,
) {
  const expected = snapshotCpmPhotoIssuanceIdentity(identity);
  const capturedProfiles = profilesSnapshot(profiles);
  return await initialDeadline(caller, 20_000, async (signal) => {
    try {
      const raw = await initialAbortable(
        signal,
        () => bridge.begin(expected, signal),
      );
      if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
        throw initialMediaUnavailable();
      }
      if ((raw as Record<string, unknown>).outcome === "held") {
        const r = mediaRecord(raw, ["outcome", "attempt_id"]);
        return Object.freeze({
          outcome: "held" as const,
          attempt_id: mediaUUID(r.attempt_id),
        });
      }
      const r = mediaRecord(raw, [
        "outcome",
        "attempt_id",
        "observation",
        "created_at_ms",
        "capability_expires_at_ms",
      ]);
      if (r.outcome !== "fresh") throw initialMediaUnavailable();
      const attempt = mediaUUID(r.attempt_id);
      const observation = snapshotCpmWriteClosureInput(
        r.observation,
        attempt,
        "live_object",
      );
      const b = observation.binding;
      const created = mediaTime(r.created_at_ms),
        expiry = mediaTime(r.capability_expires_at_ms);
      if (
        b.scan_id !== expected.scan || b.object_id !== expected.object ||
        b.assignment_digest !== expected.assignment_digest ||
        b.verification_policy_digest !== expected.policy ||
        b.issued_at_ms < created || b.issued_at_ms > Date.now()
      ) throw initialMediaUnavailable();
      const spec = await initialAbortable(
        signal,
        () =>
          prepareCpmPhotoUploadSpecification(
            {
              binding: {
                attempt_id: attempt,
                scan_id: b.scan_id,
                object_id: b.object_id,
                assignment_digest: b.assignment_digest,
                backend_generation: b.backend_generation,
                backend_configuration_digest: b.backend_configuration_digest,
              },
              target: observation.target,
              backend: observation.backend,
              created_at_ms: created,
              admission_expires_at_ms: observation.admission_expires_at_ms,
              capability_expires_at_ms: expiry,
            },
            capturedProfiles.map((
              {
                credential_profile,
                backend_generation,
                backend_configuration_digest,
              },
            ) => ({
              credential_profile,
              backend_generation,
              backend_configuration_digest,
            })),
          ),
      );
      const profile = capturedProfiles.find((p) =>
        p.credential_profile === spec.profile.credential_profile
      )!;
      await initialAbortable(
        signal,
        () => bridge.requireCurrent(observation, signal),
      );
      checkInitialDeadline(signal);
      const signingSecond = Math.floor(Date.now() / 1000) * 1000;
      const expirySecond = Math.floor(expiry / 1000) * 1000;
      const ttl = (expirySecond - signingSecond) / 1000;
      if (
        ttl < 1 || ttl > 600 ||
        signingSecond < Math.floor(created / 1000) * 1000
      ) throw initialMediaUnavailable();
      const url = new URL(
        `${spec.destination.direct_endpoint}/${spec.destination.private_bucket}/${spec.destination.key}`,
      );
      url.searchParams.set("X-Amz-Expires", String(ttl));
      const headers = Object.freeze({
        ...spec.headers,
        "x-amz-content-sha256": spec.payload_integrity.required_digest,
      });
      // Sign metadata only. The pinned signer uses this explicit digest for the
      // canonical payload hash; do not use its UNSIGNED-PAYLOAD default or fetch.
      const signed = await initialAbortable(
        signal,
        () =>
          getS3Client(profile.access_key_id, profile.secret_access_key).sign(
            url.toString(),
            {
              method: "PUT",
              headers,
              aws: {
                service: "s3",
                region: "auto",
                signQuery: true,
                allHeaders: true,
                datetime: new Date(signingSecond).toISOString().replace(
                  /[:-]|\.\d{3}/g,
                  "",
                ),
              },
            },
          ),
      );
      await initialAbortable(
        signal,
        () => bridge.requireCurrent(observation, signal),
      );
      checkInitialDeadline(signal);
      if (Date.now() >= expirySecond) throw initialMediaUnavailable();
      // This is private service output, not a public/native wire DTO. No route
      // may expose it until hosted enforcement and consuming contracts qualify.
      return Object.freeze({
        outcome: "issued" as const,
        attempt_id: attempt,
        url: signed.url,
        method: "PUT" as const,
        headers,
        capability_expires_at_ms: expiry,
        signed_expires_at_ms: expirySecond,
        provider_enforcement: "unqualified" as const,
      });
    } catch {
      throw initialMediaUnavailable();
    }
  });
}
