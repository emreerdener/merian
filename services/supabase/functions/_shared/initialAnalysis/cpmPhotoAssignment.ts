/** Saved CPM metadata only. Parsing never selects a profile or grants authority. */
import {
  hex,
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import {
  initialCpmPhotoCandidateDigest,
  validateInitialCpmPhotoCandidate,
} from "./cpmPhotoCandidate.ts";
import { initialCpmPhotoContentDigest } from "./cpmPhotoContent.ts";
import { matchesInitialSchema } from "./schema.ts";
import schema from "./cpm-photo-assignment-schema-v1.json" with {
  type: "json",
};

type Role = "source" | "ai" | "display";
type Declaration = {
  reference_id: string;
  byte_count: number;
  sha256: string;
  declared_content_type: string;
};
type Content = {
  scan_id: string;
  package_id: string;
  photos: (Record<Role, Declaration> & { ordinal: number })[];
};
type Candidate = {
  content_canonical: string;
  admission: {
    client_protocol: number;
    identification_protocol: number;
    expected_processor_permission: string;
  };
};
type Assignment = {
  candidate_digest: string;
  content_digest: string;
  scan_id: string;
  package_id: string;
  created_at_ms: number;
  expires_at_ms: number;
  configuration: {
    route: string;
    input_profile: string;
    effective_plan: string;
    effective_tier: string;
    quota_model: string;
    provider_model: string | null;
    effective_model: string;
    provider: string;
    processor_permission: string;
    minimum_client_protocol: number;
    accepted_client_protocol: number;
    minimum_identification_protocol: number;
    accepted_identification_protocol: number;
  };
  preparation: {
    role_mapping: {
      photo_ordinal: number;
      role: Role;
      object_id: string;
      declaration: Declaration;
    }[];
  };
};
const roles: readonly Role[] = ["source", "ai", "display"];

/** Both caller-owned inputs are privately snapshotted before the first await.
 * This checks a saved binding, not current consent, configuration eligibility,
 * authenticated ownership, object existence, byte verification or a live clock.
 * Those checks remain with allocation/admission/recovery transaction owners.
 */
export async function validateInitialCpmPhotoAssignment(
  candidate: unknown,
  assignment: unknown,
): Promise<string> {
  const candidateText = validateInitialCpmPhotoCandidate(candidate);
  const c = JSON.parse(candidateText) as Candidate;
  const content = JSON.parse(c.content_canonical) as Content;
  const text = initialCanonicalText(assignment);
  const frozen = parseInitialCanonicalText(text);
  if (
    new TextEncoder().encode(text).length > 65536 ||
    !matchesInitialSchema(frozen, schema)
  ) return invalidInitialInput();
  const a = frozen as unknown as Assignment;
  const config = a.configuration;
  if (
    a.scan_id !== content.scan_id || a.package_id !== content.package_id ||
    a.expires_at_ms - a.created_at_ms !== 1_800_000 ||
    config.processor_permission !== c.admission.expected_processor_permission ||
    config.accepted_client_protocol !== c.admission.client_protocol ||
    config.accepted_identification_protocol !==
      c.admission.identification_protocol ||
    config.minimum_client_protocol > config.accepted_client_protocol ||
    config.minimum_identification_protocol >
      config.accepted_identification_protocol ||
    config.effective_tier !==
      (config.effective_plan === "free" ? "free" : "pro") ||
    config.effective_model !== (config.provider_model ?? config.quota_model) ||
    (config.provider === "gemini") !==
      (config.processor_permission === "google_gemini") ||
    (config.route === "identify") !==
      (config.input_profile === "vision_compat_v1")
  ) return invalidInitialInput();
  const mapping = a.preparation.role_mapping;
  if (
    mapping.length !== content.photos.length * roles.length ||
    new Set(mapping.map((m) => m.object_id)).size !== mapping.length
  ) return invalidInitialInput();
  for (const [index, member] of mapping.entries()) {
    const ordinal = Math.floor(index / roles.length);
    const role = roles[index % roles.length];
    if (
      member.photo_ordinal !== ordinal || member.role !== role ||
      initialCanonicalText(member.declaration) !==
        initialCanonicalText(content.photos[ordinal][role])
    ) return invalidInitialInput();
  }
  if (
    a.candidate_digest !==
      await initialCpmPhotoCandidateDigest(JSON.parse(candidateText)) ||
    a.content_digest !== await initialCpmPhotoContentDigest(content)
  ) return invalidInitialInput();
  return text;
}

/** Recompute only after strict pair validation; never hash an unchecked reply. */
export async function initialCpmPhotoAssignmentDigest(
  candidate: unknown,
  assignment: unknown,
): Promise<string> {
  const text = await validateInitialCpmPhotoAssignment(candidate, assignment);
  return hex(
    new Uint8Array(
      await crypto.subtle.digest(
        "SHA-256",
        new TextEncoder().encode(
          `merian.initial-analysis.cpm-photo-assignment.v1\n${text}`,
        ),
      ),
    ),
  );
}
