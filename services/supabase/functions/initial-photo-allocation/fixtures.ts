import { initialCanonicalText } from "../_shared/initialAnalysis/canonical.ts";
import candidate from "../_shared/initialAnalysis/fixtures/cpm-photo-candidate-v1.json" with {
  type: "json",
};
import assignment from "../_shared/initialAnalysis/fixtures/cpm-photo-assignment-v1.json" with {
  type: "json",
};
export const create = () => ({
  version: 1,
  action: "create",
  candidate_canonical: initialCanonicalText(candidate.candidate),
});
export const status = (digest: string | null = null) => ({
  ...create(),
  action: "status",
  saved_assignment_digest: digest,
});
export const allocated = () => ({
  version: 1,
  variant: "client_prepared_photo",
  outcome: "allocated",
  authority: "none",
  assignment_canonical: assignment.canonical,
  assignment_digest: assignment.digest,
});
