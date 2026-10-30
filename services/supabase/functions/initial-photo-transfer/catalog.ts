/** Trusted composition input only. No environment loader or installed entries. */
import {
  initialMediaUnavailable,
  mediaDigest,
  mediaRecord,
  mediaUUID,
} from "../_shared/initialAnalysis/mediaBinding.ts";
import type { CpmPhotoIssuerProfile } from "../_shared/initialAnalysis/cpmPhotoUploadIssuer.ts";

export interface TransferPolicyEntry {
  readonly policy_digest: string;
  readonly profile: Readonly<CpmPhotoIssuerProfile>;
}
export interface TransferPolicyCatalog {
  resolve(
    generation: string,
    configurationDigest: string,
  ): Readonly<TransferPolicyEntry>;
}

/** Each historical tuple pins one policy. Rotation adds a tuple; it must not
 * replace a mapping for old allocations. SQL rechecks current eligibility. */
export function transferPolicyCatalog(
  values: readonly TransferPolicyEntry[],
): TransferPolicyCatalog {
  if (!Array.isArray(values) || values.length > 16) {
    throw initialMediaUnavailable();
  }
  const entries = new Map<string, Readonly<TransferPolicyEntry>>();
  for (const value of values) {
    const row = mediaRecord(value, ["policy_digest", "profile"]);
    const profile = mediaRecord(row.profile, [
      "credential_profile",
      "backend_generation",
      "backend_configuration_digest",
      "access_key_id",
      "secret_access_key",
    ]);
    const generation = mediaUUID(profile.backend_generation),
      digest = mediaDigest(profile.backend_configuration_digest);
    const key = `${generation}/${digest}`;
    if (
      entries.has(key) || typeof profile.credential_profile !== "string" ||
      !/^[a-z][a-z0-9_]{0,63}$/.test(profile.credential_profile)
    ) throw initialMediaUnavailable();
    for (const name of ["access_key_id", "secret_access_key"]) {
      if (
        typeof profile[name] !== "string" ||
        !/^[A-Za-z0-9/+_=.-]{16,256}$/.test(profile[name] as string)
      ) throw initialMediaUnavailable();
    }
    entries.set(
      key,
      Object.freeze({
        policy_digest: mediaDigest(row.policy_digest),
        profile: Object.freeze({
          credential_profile: profile.credential_profile,
          backend_generation: generation,
          backend_configuration_digest: digest,
          access_key_id: profile.access_key_id as string,
          secret_access_key: profile.secret_access_key as string,
        }),
      }),
    );
  }
  // The catalog exposes no enumerable credential fields and captures copies.
  return Object.freeze({
    resolve(generation: string, digest: string) {
      const found = entries.get(
        `${mediaUUID(generation)}/${mediaDigest(digest)}`,
      );
      if (!found) throw initialMediaUnavailable();
      return found;
    },
  });
}
