/** Inactive source-plan contract only. No storage, assignment or grant authority. */
import {
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { matchesInitialSchema } from "./schema.ts";
import { assertInitialMediaSourceSemantics } from "./mediaSourceSemantics.ts";
import schema from "./media-source-candidate-schema-v2.json" with {
  type: "json",
};

export function validateInitialMediaSourceCandidate(value: unknown): string {
  const text = initialCanonicalText(value);
  const frozen = parseInitialCanonicalText(text);
  if (
    !matchesInitialSchema(frozen, schema) || frozen === null ||
    typeof frozen !== "object" || Array.isArray(frozen)
  ) {
    return invalidInitialInput();
  }
  assertInitialMediaSourceSemantics(
    (frozen as { readonly source_plan: unknown }).source_plan,
  );
  return text;
}
