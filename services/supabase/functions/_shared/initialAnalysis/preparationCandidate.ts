/** Inactive no-media preparation codec. No RPC, grant or runtime installation. */
import {
  type CanonicalValue,
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { matchesInitialSchema, validateInitialInput } from "./schema.ts";
import candidateSchema from "./preparation-candidate-schema-v2.json" with {
  type: "json",
};
import assignmentSchema from "./assignment-schema-v2.json" with {
  type: "json",
};

function canonicalObject(
  value: CanonicalValue,
): value is { readonly [key: string]: CanonicalValue } {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function validateInitialPreparationCandidate(value: unknown): string {
  const text = initialCanonicalText(value);
  const frozen = parseInitialCanonicalText(text);
  if (!matchesInitialSchema(frozen, candidateSchema)) {
    return invalidInitialInput();
  }
  if (!canonicalObject(frozen)) {
    return invalidInitialInput();
  }
  const input = frozen.input;
  validateInitialInput(input);
  if (!canonicalObject(input)) {
    return invalidInitialInput();
  }
  if (
    !Array.isArray(input.media) || input.media.length !== 0 ||
    !["identify-describe", "identify-multimodal"].includes(
      String(input.route),
    ) ||
    input.experiment !== null
  ) throw new Error("initial_analysis_preparation_unavailable");
  return text;
}

/** Validates server-saved bytes; never selects or authorizes an assignment. */
export function validateInitialSavedAssignment(value: unknown): string {
  const text = initialCanonicalText(value);
  if (
    !matchesInitialSchema(parseInitialCanonicalText(text), assignmentSchema)
  ) {
    return invalidInitialInput();
  }
  return text;
}

export async function initialPreparationDigest(
  domain: "preparation-candidate" | "assignment",
  canonical: string,
): Promise<string> {
  const bytes = new TextEncoder().encode(
    `merian.initial-analysis.${domain}.v2\n${canonical}`,
  );
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
  return [...digest].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
