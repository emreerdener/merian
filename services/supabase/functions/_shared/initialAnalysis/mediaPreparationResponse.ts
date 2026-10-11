/** Closed allocation metadata only; this decoder never conveys I/O authority. */
import {
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { matchesInitialSchema } from "./schema.ts";
import { validateInitialMediaAssignment } from "./mediaAssignment.ts";
import { initialPreparationDigest } from "./preparationCandidate.ts";
import schema from "./media-preparation-response-schema-v2.json" with {
  type: "json",
};

export async function validateInitialMediaPreparationResponse(
  candidate: unknown,
  response: unknown,
): Promise<string> {
  const text = initialCanonicalText(response);
  const value = parseInitialCanonicalText(text) as Record<string, unknown>;
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return invalidInitialInput();
  }
  const shape = value.outcome === "expired" ? schema.expired : schema.allocated;
  if (!matchesInitialSchema(value, shape)) return invalidInitialInput();
  if (value.outcome === "expired") return text;
  const assignment = await validateInitialMediaAssignment(
    candidate,
    value.assignment,
  );
  if (
    value.candidate_digest !==
      (value.assignment as Record<string, unknown>).candidate_digest ||
    value.assignment_digest !==
      await initialPreparationDigest("assignment", assignment) ||
    !Number.isFinite(Date.parse(String(value.expires_at)))
  ) return invalidInitialInput();
  return text;
}
