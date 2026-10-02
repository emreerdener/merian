# Photo feature-observation candidate — offline preparation

Status: implemented offline on 1 October 2026. This is engineering preparation,
with zero provider calls and zero charges. It establishes no identification
improvement. Production routing, prompts, confidence thresholds, explanation
format and public response shapes are unchanged by this candidate.

The
[reference adjudication](identification-reference-adjudication-2026-10-01.md)
provides 18 exposed, provisional development observations and two reference
holds. The
[answerability audit](identification-answerability-audit-2026-10-01.md) owns the
feature-review instrument and proposed advancement conditions. Original study
references and scores remain historical evidence.

Later on 1 October, the
[collection and review workflow](identification-photo-feature-workflow-2026-10-01.md)
implemented the missing collector, review and paired scoring. This record
preserves the earlier preparation snapshot and its verification.

## Candidate and comparison

The existing explicit-primary request is the comparator. The candidate reuses
its model, low reasoning, token and timeout settings, image preparation, safety
identity, confidence instructions and explanation fields. Its only request
changes are additional feature instructions, a private schema name and a
required `diagnostic_features` field. Each biological answer must include one to
three brief observations; a nonbiological answer may include zero to three. Each
observation has a bounded kind, visibility and at most 160 characters of text.

The instructions distinguish a visible feature, an unshown structure and an
unclear structure. They prohibit treating a missing view as biological absence
and preserve supported species answers. These are prompt instructions, not proof
of model compliance or evidence that the proposed treatment works.

All candidate code lives under
`services/supabase/scripts/identification_evaluation`.
`photoFeatureCandidate.ts` has no transport or credential access and is not
registered for production admission. Its decoder strips the private feature
field before invoking the existing strict primary decoder; the existing decoder
continues rejecting that extra field. Existing five-state identification
semantics remain intact.

## Transient review boundary

`photoFeatureReview.ts` accepts two trusted callback integrations. Each receives
an opaque token and a separate frozen copy of the feature observations, without
the predicted name, rank, confidence, explanation or reference score. Malformed
output and normalization/rank conflicts are rejected before callbacks run.
Reviewer errors produce fixed states without echoing private error text.

The returned projection contains canonical taxon IDs, bounded normalization
facts and review counts. It contains no model feature text, names or
explanation. Each observation needs both reviewers to mark it supported for
`allFeaturesSupported` to be true. Disagreement, contradiction, unverifiability
or irrelevance prevents that result. An empty feature list never satisfies it.
The model cannot supply its own reviewer judgments through the draft schema.

This helper is a contract prototype. Distinct callback objects do not establish
independent reviewers, blinding or scientific correctness. The aggregate flag is
not experiment advancement or a verified biological gain. A real integration
must bind reviewer identities and assignments to exact images, shuffled opaque
tokens and diagnostic cards; treat provider observations as untrusted text;
apply the audit's specificity/visibility/dispute rubric; retain bounded review
provenance; and keep all provider prose transient. It must also implement the
independent dispute adjudication specified by the audit. No such live reviewer
integration is claimed here. Trusted callbacks can perform I/O, so this helper
alone cannot enforce their privacy or erase their memory.

## Offline packet

`prepare_photo_feature_screen.ts` accepts the executing repository, the original
primary-screen archive, the checked-in adjudication JSON and a new private
output directory. It requires the repository to match the executing module's
canonical root. It binds the exact reviewed adjudication bytes and audit hash,
reads and hashes each of the four original parent JSON files once, validates
original curation/evidence links, and checks all selected image bytes before
use.

The materialized packet includes:

- Eighteen unchanged image files and a separately versioned development corpus,
  retaining original split and curation provenance.
- The 94-entry taxonomy formed by adding the three reviewed families to the
  original 91 entries. Existing entries remain unchanged.
- The adjudication, parent audit and the subset of original evidence records
  referenced by selected observations. Old reference cards are explicitly
  historical; the adjudication owns prospective accepted answers.
- Thirty-six request/settings fingerprints with deterministic alternating arm
  order. This order is reproducible, not randomized.
- Implementation graph identity, evidence fingerprints, the two held case IDs,
  the existing 22 October retention deadline and explicit readiness flags.

Parent and output packet roots must be outside the canonical repository. The
output is created exclusively with owner-only permissions and flushed to disk. A
nonempty output directory is rejected rather than resumed or overwritten. The
original archive is read-only input. Source identity records the current
implementation graph; a dirty shared checkout and these request fingerprints do
not substitute for a final isolated execution freeze.

There is no live mode, dispatcher, provider pricing, budget or authorization in
this packet. `dispatchSupported` and `paidServiceApproved` are false, and the
budget is null. Editing these fields cannot enable execution. No attempt claims
or model results exist. The 40 unused old-held-out observations are untouched.

## Remaining execution boundary

Before collection, integrate the candidate into the existing evaluator's
moderation, accounting, durable claim and no-retry controls; complete and test
the transient review workflow; and implement the paired advancement report
against the adjudicated reference version. Freeze this reviewed implementation
in an isolated source snapshot, verify current pricing, and obtain a new
explicit spending ceiling and credential session. Previously closed budgets stay
closed. These are real remaining requirements, not paid execution hidden behind
a flag.

The proposed screen remains 18 observations by two arms, at most 36 attempted
calls. Passing requires the adjudication's net gain, limited-evidence
mechanisms, unresolved gain, no regression and non-mapping conditions, with
feature review. This small exposed screen cannot establish provider superiority
or calibrate confidence. Continue to recommend the released photo configuration
until a completed experiment justifies a change.

## Verification

The private preparation at
`/private/tmp/merian-photo-feature-preparation-20261001` contains 24 owner-only
files: 18 images and six JSON records. Offline verification rebuilt all 36
requests from the copied images and reproduced every request/settings hash,
checked corpus/taxonomy/evidence hashes and current source identity, and
rejected five negative cases: output reuse, wrong executing checkout, parent
packet inside the repository, output inside the repository and changed
adjudication bytes. This temporary directory is reproducible preparation, not a
paid run archive. It retains the original 22 October deadline.

Its implementation graph digest is
`609fcdc2d15229409d9cfb57df56ab15aa0cd640c09574c22faace7333700966`. The
dirty-checkout flag and disabled execution/readiness flags remain explicit. This
is not an isolated executable source freeze.

- Six focused tests passed with network/environment access denied and a narrow
  read grant for the checked-in adjudication fixture. Coverage includes request
  parity, production isolation, malformed features, all five primary states,
  private-content exclusion, reviewer disagreement/failure/mutation, reference
  holds, image binding and taxonomy ranks.
- The backend runtime suite passed: 2,255 tests and 343 steps, with 11 ignored.
- The full tooling command passed 495 standard tests, 144 isolated evaluator
  tests and both DTO suites (20 and 21 tests). Its shell phase stopped at the
  Gemini fake-key PTY test because the sandbox prevented terminal echo control.
  The failed test and all seven remaining shell tests passed separately outside
  that sandbox, using synthetic credentials and local fake providers. Thus the
  tooling components passed; the original monolithic command returned failure.
- All 104 isolated Function entrypoints type-checked; 104 dependency configs and
  411 runtime-file graph boundaries passed. Separate DTO validation passed.
- Recursive backend formatting passed. All six affected TypeScript files passed
  lint. Full recursive lint remains blocked by five unrelated `require-await`
  findings in `functions/review-scan-identification/handler_test.ts`; that
  user-owned work was preserved.
- Research catalog validation passed with 29 studies and 10 dataset families.
  Changed-Markdown formatting and `git diff --check` passed.
- Independent read-only review found source-root binding, repeated-read
  provenance and in-repository media-output risks. These were fixed before
  materialization and verified above. Review also confirmed the absence of a
  provider dispatch or production admission path.

These are software and artifact checks, not model accuracy measurements. No new
database, hosted deployment or device test is claimed for this scripts-only
candidate. Provider calls, provider charges and outstanding reservations are all
zero for this preparation.
