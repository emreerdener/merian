/** Inactive allocation candidate, never admission, consent or upload authority. */
import {
  hex,
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { parseInitialCpmPhotoContent } from "./cpmPhotoContent.ts";
import { matchesInitialSchema } from "./schema.ts";
import schema from "./cpm-photo-candidate-schema-v1.json" with { type: "json" };

/** The existing content encoding remains its own field authority. Keeping its
 * exact canonical text avoids a second copied content schema and preserves the
 * content digest independently of the saved admission expectation. Both the
 * outer envelope and embedded declaration must be canonical and bounded.
 * The receiving owner must persist this value before allocation I/O. Server
 * owners must still check authenticated ownership, scan identity, current
 * consent and the expected processor; this parser grants none of those facts.
 */
export function validateInitialCpmPhotoCandidate(value: unknown): string {
  const canonical = initialCanonicalText(value);
  const frozen = parseInitialCanonicalText(canonical);
  if (!matchesInitialSchema(frozen, schema)) return invalidInitialInput();
  const candidate = frozen as { content_canonical: string };
  parseInitialCpmPhotoContent(candidate.content_canonical);
  return canonical;
}

export function parseInitialCpmPhotoCandidate(canonical: string): string {
  return validateInitialCpmPhotoCandidate(parseInitialCanonicalText(canonical));
}

/** The digest binds content AND protocol/processor expectation. It snapshots
 * synchronously before SHA-256 awaits and remains an unverified client claim.
 */
export async function initialCpmPhotoCandidateDigest(
  value: unknown,
): Promise<string> {
  const canonical = validateInitialCpmPhotoCandidate(value);
  const bytes = new TextEncoder().encode(
    `merian.initial-analysis.cpm-photo-candidate.v1\n${canonical}`,
  );
  return hex(new Uint8Array(await crypto.subtle.digest("SHA-256", bytes)));
}
