/** Closed recovery projections for the inactive allocation-only increment. */
import {
  type CanonicalValue,
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { validateInitialCpmPhotoCandidate } from "./cpmPhotoCandidate.ts";
import {
  initialCpmPhotoAssignmentDigest,
  validateInitialCpmPhotoAssignment,
} from "./cpmPhotoAssignment.ts";
import { matchesInitialSchema } from "./schema.ts";
import schema from "./cpm-photo-recovery-schema-v1.json" with { type: "json" };

function isObject(
  value: CanonicalValue,
): value is { readonly [key: string]: CanonicalValue } {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

/** A terminal/not-found reply never permits replacement or fresh execution.
 * Saved verification and admission require their own implemented versions; this
 * allocation decoder deliberately has no permissive unknown-outcome fallback.
 */
export async function validateInitialCpmPhotoRecovery(
  candidate: unknown,
  response: unknown,
  savedAssignmentCanonical: string | null,
): Promise<string> {
  const candidateText = validateInitialCpmPhotoCandidate(candidate);
  const c = JSON.parse(candidateText) as { content_canonical: string };
  const content = JSON.parse(c.content_canonical) as { scan_id: string };
  const text = initialCanonicalText(response);
  const value = parseInitialCanonicalText(text);
  if (!isObject(value)) {
    return invalidInitialInput();
  }
  // Null is explicit only when the first allocation acknowledgement was lost.
  // Once saved, neither a renewed clock nor a different valid mapping may rebase it.
  if (savedAssignmentCanonical !== null) {
    await validateInitialCpmPhotoAssignment(
      JSON.parse(candidateText),
      parseInitialCanonicalText(savedAssignmentCanonical),
    );
  }
  if (value.outcome === "terminal_held") {
    if (
      !matchesInitialSchema(value, schema.terminal_held) ||
      value.scan_id !== content.scan_id
    ) return invalidInitialInput();
    return text;
  }
  if (!matchesInitialSchema(value, schema.allocated)) {
    return invalidInitialInput();
  }
  if (
    savedAssignmentCanonical !== null &&
    value.assignment_canonical !== savedAssignmentCanonical
  ) return invalidInitialInput();
  const assignment = parseInitialCanonicalText(
    String(value.assignment_canonical),
  );
  if (
    value.assignment_digest !== await initialCpmPhotoAssignmentDigest(
      JSON.parse(candidateText),
      assignment,
    )
  ) return invalidInitialInput();
  return text;
}
