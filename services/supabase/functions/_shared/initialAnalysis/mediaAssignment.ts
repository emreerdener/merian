/** Decoder for dormant saved metadata; no authority to upload or execute. */
import {
  initialCanonicalText,
  invalidInitialInput,
  parseInitialCanonicalText,
} from "./canonical.ts";
import { matchesInitialSchema } from "./schema.ts";
import { validateInitialMediaSourceCandidate } from "./mediaSourceCandidate.ts";
import { initialPreparationDigest } from "./preparationCandidate.ts";
import {
  initialMediaContractDigest,
  initialSourceInputProfile,
  initialSourceRole,
} from "./mediaPreparationProfile.ts";
import type { InitialMediaSourcePlan } from "./mediaSourceSemantics.ts";
import schema from "./media-assignment-schema-v2.json" with { type: "json" };

export async function validateInitialMediaAssignment(
  candidate: unknown,
  assignment: unknown,
): Promise<string> {
  const candidateText = validateInitialMediaSourceCandidate(candidate);
  const plan =
    (JSON.parse(candidateText) as { source_plan: InitialMediaSourcePlan })
      .source_plan;
  const text = initialCanonicalText(assignment),
    frozen = parseInitialCanonicalText(text);
  if (
    new TextEncoder().encode(text).length > 65536 ||
    !matchesInitialSchema(frozen, schema)
  ) return invalidInitialInput();
  const a = frozen as unknown as {
    candidate_digest: string;
    source_plan_digest: string;
    route: string;
    input_profile: string;
    preparation: {
      source_mapping: {
        ordinal: number;
        source: unknown;
        role: string;
        object_id: string;
      }[];
    };
  };
  if (
    a.candidate_digest !==
      await initialPreparationDigest("preparation-candidate", candidateText) ||
    a.source_plan_digest !==
      await initialMediaContractDigest(
        "source_plan",
        initialCanonicalText(plan),
      ) ||
    a.route !== plan.route ||
    a.input_profile !== initialSourceInputProfile(plan) ||
    a.preparation.source_mapping.length !== plan.sources.length ||
    new Set(a.preparation.source_mapping.map((m) => m.object_id)).size !==
      plan.sources.length
  ) return invalidInitialInput();
  for (const [i, m] of a.preparation.source_mapping.entries()) {
    if (
      m.ordinal !== i || m.role !== initialSourceRole(plan.sources[i]) ||
      initialCanonicalText(m.source) !== initialCanonicalText(plan.sources[i])
    ) return invalidInitialInput();
  }
  return text;
}
