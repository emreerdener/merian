# Alternative identification provider evaluation

The first alternative is `gpt-6-sol` through OpenAI's Responses API. The shared
adapter supports controlled local and hosted evaluation. The separate production
`openai_photo_v1` binding adds pinned inline moderation and V2 result metadata;
the owner-authorized beta catalog assigns still photos to it and retains Gemini
for other complete-input profiles and enrichment. Provider selection stays
server-owned. See the
[beta activation record](../release-evidence/openai-beta-photo-activation-2026-09-28.md).

The production binding does not alter the completed baseline requests or their
hashes. Its separate paid end-to-end qualification remains deferred by the beta
decision, not reported as complete.

The
[matched comparison](../rfcs/identification-gemini-openai-matched-results-2026-09-27.md)
completed all sixteen scheduled Gemini/OpenAI attempts on 27 September. Earlier
app measurements and this comparison remain development evidence, with their
original inputs and limitations. The
[current optimization plan](../rfcs/identification-optimization-preserving-results-2026-09-27.md)
starts from that evidence and preserves the current explanation format and
detail. It does not require another Gemini-only benchmark campaign or a repeat
of the closed concise-explanation screen. Audio experiments cannot establish
photo/text quality.

## Luna/Sol photo comparison preparation

The
[Free/Pro model plan](../rfcs/identification-openai-free-pro-models-2026-09-28.md)
introduces two closed evaluation profiles: `openai_photo_luna_low_v1` and
`openai_photo_sol_low_v1`. Both freeze the original photo prompt
`openai_identify_vision_v1`, strict schema, high image detail, low reasoning,
8,192-token output limit and pinned native input/output moderation. Only the
model differs. The Sol control matched production when the comparisons ran; its
builder remains independent of the later observed-traits production prompt.
Retain all completed evidence under its original configuration and binding.

`_shared/ai/openaiPhotoModels.ts` owns those immutable configurations.
`createOpenAIPhotoModelEvaluationAdapter` reuses the bounded transport and
safety decoder, requiring the exact returned model before releasing a draft.
Neither profile is registered for production or accepted by the historical
evaluator or hosted workflow. The dedicated local `--photo-model-live` mode owns
this separate comparison. Production still-photo assignment remains
`openai_photo_v1` / `gpt-6-sol` for both tiers.

The new `preflight-free-pro-photo` mode performs preparation only. Place these
private files outside Git:

| File                       | Contract                                                                                                                                                                                                                                              |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `corpus.json`              | Existing exploratory corpus format, exactly 12 development photo cases without descriptions; non-null provisional references and valid media hashes.                                                                                                  |
| `taxonomy.json`            | Existing taxonomy format, containing every reference taxon.                                                                                                                                                                                           |
| `photo-model-facts.json`   | `photo_model_facts_v1`, exactly 12 existing-format fact cards bound to each input digest; rank/abstention/non-biological review requirements as applicable.                                                                                           |
| `photo-model-pricing.json` | `photo_model_pricing_v1`, current USD paid Standard synchronous rates for both exact models, official model-page sources and a review reference.                                                                                                      |
| `photo-model-plan.json`    | `photo_model_plan_v1` preserves the original $5 proposal; `photo_model_plan_v2` supports an explicitly approved ceiling up to $40. Both bind all four input-file digests, six screen IDs, six challenge IDs, 18 calls and one attempt per assignment. |

For real inputs, the plan's `inputApproval` records the owner's existing OpenAI
benchmark authorization for that corpus and all selected cases. This is an
operator evidence record, not app-user provider consent. Synthetic fixtures
require a null approval and are labeled mechanics-only. Real evidence must have
unexpired retention and its existing source/eligibility records. The screen
contains five named biological references and one non-biological control; the
challenge set also includes a non-biological control and a biological reference
that requires a higher rank or abstention. Freeze the six challenge references
before candidate outputs exist.

Run from the repository root, replacing `PRIVATE_PACKET` with the existing
private packet directory:

```bash
evaluation_root="PRIVATE_PACKET"
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$evaluation_root" --allow-write="$evaluation_root" \
  --allow-run=git \
  services/supabase/scripts/evaluate_identification.ts \
  preflight-free-pro-photo "$evaluation_root"
```

`photo-model-preflight.json` contains hashes, source identity, reviewed model
settings, fixed ordering and a conservative reservation. It stores no photo
bytes, observation/review prose, references or credential. Six Luna screening
assignments precede paired challenge assignments; challenge ordering alternates
Luna/Sol and Sol/Luna. The output always states `dispatchAuthorized: false`;
`liveControllerAvailable: true` reports implementation availability only. The
runner requires passing assistant reviews and correct reference decisions on all
six screen cases before any challenge call. Successful preparation is not a
completed benchmark or spending approval.

At the September 28 reviewed global Standard rates, reserving 1,050,000 input
tokens plus 8,192 output tokens per call costs at most $0.268644 for Luna and
$5.37288 for Sol, or **$35.461008 for the full schedule**. These ceilings
include long-context and cache-write tariffs; they are not expected per-scan
prices. The live controller also reserves the 10% regional premium, for
**$39.0071088** across the 18 calls, regardless of whether that premium applies
to the account. Preflight reports both reservations and budget-fit flags. Both
flags were false for the original $5 proposal. The owner-approved v2/$40 plan
covers both reservations. Do not lower the historical full-context reservation
using media byte length or raise the approved ceiling implicitly. Any future
comparison whose budget does not fit must bind justified input-token bounds to
its exact requests and actual account pricing, or obtain an explicit budget
revision. OpenAI's
[input token counting API](https://developers.openai.com/api/docs/guides/token-counting)
is a possible follow-on mechanism; its request compatibility, billing and
artifact/dispatch controls are not implemented by this offline mode.

The
[real preparation record](../rfcs/identification-luna-sol-photo-preparation-2026-09-28.md)
now records all twelve photos, frozen reference limits and a successful offline
preflight. The owner approved the $40 maximum for the same 18-call comparison on
28 September; bind that approval to the reviewed clean revision before live
execution. Deterministic adapter, controller and launcher tests do not establish
Luna accuracy, real moderation compatibility or a Free/Pro quality difference.

### Durable local execution

After explicit spending approval, freeze a `photo_model_plan_v2` whose budget
covers the entire reservation. For this comparison, the owner approved $40
and the private packet was revised to v2 while preserving the original v1/$5
proposal. A larger parser limit alone does not authorize spending.

`photo-model-approval.json` uses `photo_model_approval_v1`. It binds the
`naturebook` project, `18_call_luna_sol_photo_comparison` operation, exact plan
digest, clean source commit and implementation digest, credential SHA-256,
approved budget, approval reference, reviewer/delegation references, and an
approval window of at most 24 hours. It contains no API key. The assistant's
review delegation comes from the existing instruction to perform evaluation;
this is not an end-user provider choice. Keep the approval private alongside the
packet, and create it only for the actual approved revision and budget.

The existing hidden-input launcher now supports:

```bash
bash services/supabase/scripts/run_openai_evaluation.sh \
  --photo-model-live PRIVATE_PACKET
```

It completes offline preflight and rejects an insufficient budget or dirty
source before prompting for the Naturebook key. The child can access only the
OpenAI host, one-use loopback review, Git, fixed browser opener and evaluation
credential. `photoModelAdmission.ts` binds that credential to approval and
revalidates the scope, expiry, prices, evidence, source and spending limit
before every dispatch. The current GitHub-hosted comparison workflow does not
accept these new profiles; its existing secrets do not automatically authorize
this local runner.

`photoModelRunner.ts` owns an exclusive lock and immutable `photo-model-run/`
manifest, claims, results and assessments. It reserves the complete schedule
before the first call and retains each claimed reservation, even when a request
fails or its bill is unknown. A claim without a result stops permanently as
interrupted. A missing or unavailable explanation review also stops. Neither a
restart nor a changed state summary can repeat an attempt. Once a manifest
exists, source, packet or approval drift/expiry creates an immutable
configuration stop. Restoring the old inputs cannot clear it. If inputs no
longer validate, the stop summary leaves totals unknown and preserves the
original journal. Model mismatch, refusal, invalid safety/output, missing or
inconsistent billing, and operational failures stop subsequent calls. Six
successful screen results with passing assistant ratings are required before
challenges. Challenge quality failures remain visible for comparison; they do
not trigger replacement calls. An unassessable screening rating also yields
`screen_failed`; inspect the ratings to distinguish missing reference coverage
from an observed model error. The first
[live screen record](../rfcs/identification-luna-sol-photo-screen-results-2026-09-28.md)
retains one reference-matching Luna result and that reference-coverage stop. It
does not complete the Luna/Sol comparison.

`photoModelRecords.ts` projects bounded taxonomy IDs, scores, timings, native
usage categories, exact model, safety disposition and a conservative usage-based
cost upper bound. Unknown cache writes or service tier remain unpriced. Output
already includes reasoning, which is never billed twice in the projection. These
upper bounds are not invoices or expected per-scan prices; report measured cost
only when the actual pricing basis and all native usage categories permit it. No
photo, provider prose, reasoning trace, response/error body or key enters the
journal. Explanations exist only in the one-use assistant review view; only
bound enum ratings are saved. Finishing all calls never selects or activates a
production profile. The assistant still writes the quality/cost/latency
selection record against the frozen references.

### Approved continuation after the reference-coverage stop

The owner approved retaining the first result and completing at most the
seventeen unattempted assignments under `reference_gaps_recorded_v1`. This is a
specific continuation of the stopped one-result journal, with a combined maximum
of 18 calls and $40. Photos, frozen facts, request parameters, prices and
assignment order stay bound to the original plan. Do not restart the original
mode, delete its stop or replace its ratings.

Run the network/environment-denied
`preflight-free-pro-photo-continuation PRIVATE_PACKET` CLI mode against a clean
reviewed revision. It writes `photo-model-continuation-preflight.json`,
preserving the original preflight and journal. It validates exactly one
completed ordinal 1, a correct screening identification, the original
`screen_failed` stop, and ratings containing only passes and
`insufficient_reference` gaps. It binds `parentRunDigest` and
`parentArtifactsDigest` to the original manifest, stop, claim, result, review
and approval; derived `state.json` is never authority.

Create the private `photo-model-continuation-approval.json` only for this
approved revision. Its version is `photo_model_continuation_approval_v1` and
operation is `remaining_17_luna_sol_photo_comparison`. It retains the original
approval's project, plan, source, credential, budget, reference and
at-most-24-hour window fields, but binds the new source and current approval
window. It also requires both parent digests,
`screeningPolicy: reference_gaps_recorded_v1`, and `maxAdditionalCalls: 17`. The
old and new approval formats cannot authorize each other's execution mode. The
original approval is verified at its first claim's timestamp; this preserves
historical authority without extending its expiry.

```bash
bash services/supabase/scripts/run_openai_evaluation.sh \
  --photo-model-continuation-live PRIVATE_PACKET
```

The launcher runs that separate preflight before hidden key entry. Execution
holds the original lock before acquiring the sibling `photo-model-continuation/`
lock, validates the original artifacts before each dispatch and never rewrites
them. Only ordinals 2–18 can be claimed in the new journal. Accounting includes
the inherited call and reservation: the full $39.0071088 reservation still fits
the same $40 ceiling. Interrupted claims cannot be retried, and durable stops
cannot be cleared by restoring changed inputs.

All six screening identifications must still be correct at the supported rank.
The revised screen permits only `not_assessable / insufficient_reference` in
addition to passing explanation ratings. Actual failures, reviewer uncertainty
or unavailable review still stop screening; provider, safety and billing stops
also remain. Challenge-quality outcomes stay visible without replacement calls.
Reference gaps stay unassessable in the report and cannot count as explanation
passes or establish a Pro advantage.

The v2 aggregate state includes `inheritedCalls`, `newlyClaimedCalls`,
`referenceGapOrdinals` and `explanationEvidenceComplete`. The launcher requires
18 combined completed calls, one inherited and seventeen new claims, before
reporting completion. `complete: true` means the scheduled collection finished;
it does not mean the evidence is complete or a model is qualified. The assistant
must still write the selection report, and production activation remains a
separate decision.

The
[recorded continuation](../rfcs/identification-luna-sol-photo-screen-results-2026-09-28.md#approved-continuation-outcome-28-september)
completed the remaining five screening calls and stopped on a mineral
explanation's unsupported specificity. Six combined primary outcomes matched; no
challenge or Sol request ran. Preserve this terminal stop and the decision to
retain the current Sol assignment. Another candidate or paid run requires its
own bounded plan; the unused portion of this budget is not retry authority.

### Luna evidence-limit candidate comparison

The
[candidate record](../rfcs/identification-luna-evidence-limits-candidate-2026-09-28.md)
adds `openai_photo_luna_evidence_limits_low_v1`, a Luna-only projection of two
instruction lines. Historical `openai_photo_luna_low_v1`, the Sol control,
production routing and the shared Gemini prompt stay unchanged.

Use a **new private packet root** with the same twelve no-description photos,
corpus, taxonomy, frozen fact cards and `photo_model_pricing_v1`. Copy only
required inputs and media, never prior journals, approvals or ratings. Set a new
plan ID and `version: photo_model_plan_v3`; all other bounded plan fields keep
their meanings. V3 fixes the candidate Luna profile plus original Sol control,
18 calls, one attempt per assignment and a ceiling no higher than $40. It uses
the existing Luna pricing entry only because the exact model is unchanged. The
six-screen/six-paired-challenge ordering and full reservation are unchanged.

Run the same network/environment-denied `preflight-free-pro-photo` command
against this **new** packet. V3 preflight includes
`screeningPolicy: reference_gaps_recorded_v1`. Do not edit the stopped packet to
v3: its immutable manifest cannot accept different requests and the controller
will send no new calls. The original continuation mode rejects v3.

After explicit approval of this new experiment, create its private
`photo-model-approval.json` with `version: photo_model_candidate_approval_v1`,
`operation: 18_call_luna_evidence_limits_sol_photo_comparison` and
`screeningPolicy: reference_gaps_recorded_v1`. The other fields are the same
source/plan/key/budget/time/reviewer bindings as the original approval. Then use
`--photo-model-live NEW_PRIVATE_PACKET` in the hidden-key launcher. Original and
continuation approvals cannot authorize this candidate. The implementation does
not authorize paying for the new comparison from the stopped run's allocation.

This new packet owns its own immutable `photo-model-run/` journal. Its manifest
binds the screening policy; state separately records reference-gap ordinals and
whether explanation evidence is complete. Reference gaps stay unassessable;
actual screen errors, uncertain/unavailable review, safety, provider and billing
failures still stop. A completed collection is not automatic qualification.
Assistant review must specifically assess whether the mineral's broader identity
and variety both respect the evidence limit. The result report must disclose the
reused screen, six contemporary challenge pairs and every reference gap. Current
Sol production assignments remain in place pending a separate selection and
activation decision.

The approved v3 run subsequently completed all eighteen calls and reviews. Its
[selection report](../rfcs/identification-luna-sol-candidate-results-2026-09-28.md)
records passed mineral checks, faster and cheaper paired Luna measurements,
biological quality failures and taxonomy mapping limitations. Retain Sol for
both tiers. Keep the completed journal immutable; no additional paid calls or
activation follow from its unused spending ceiling.

### Offline photo catalog audit and rank consistency

The
[rank-consistency plan](../rfcs/identification-photo-rank-consistency-2026-09-28.md)
preserves the explanation format and current Sol assignment while preparing
better rank handling. Its first slice adds a read-only catalog audit and a
future v2 photo result projection. Run from the repository root with a private
packet path:

```bash
deno run --frozen --no-prompt --deny-net --deny-env --deny-write \
  --allow-read=PRIVATE_PACKET/corpus.json,PRIVATE_PACKET/taxonomy.json \
  --config services/supabase/functions/deno.json \
  services/supabase/scripts/audit_photo_taxonomy.ts PRIVATE_PACKET
```

The command prints bounded JSON and does not save or overwrite any files. Exit 0
means no catalog/reference consistency issue was detected, 2 reports issues, and
1 means invalid input or audit failure. Missing references and name collisions
block consistency; a clear result is neither biological review nor permission to
call a model. Repair only in a new versioned packet with an explicit
reference-ID remapping. Completed packet records remain immutable.

The new `photo_model_attempt_v2` parser/projection is offline infrastructure.
Existing photo runners accept only v1; do not insert v2 into an existing run or
reuse its approval. The next offline preparation is available:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --allow-read=PRIVATE_ROOT --allow-write=PRIVATE_ROOT/new-sol-packet \
  --config services/supabase/functions/deno.json \
  services/supabase/scripts/prepare_sol_rank_candidate.ts \
  PRIVATE_ROOT/completed-packet PRIVATE_ROOT/new-sol-packet \
  PRIVATE_ROOT/taxonomy-remap.json
```

Use a private parent outside every repository, canonical paths without symlinks,
and a destination that does not exist. The helper rejects the current checkout
and directly marked repository roots. The remap must use
`photo_taxonomy_remap_v1`, bind `sourceCorpusDigest` and `sourceTaxonomyDigest`,
set new `corpusId`, `taxonomyVersion`, `catalogRef`, `reviewRef`, and list
explicit `merges` of `{from,to}` IDs. Merges require identical normalized
canonical names and ranks; chains, cycles, missing IDs and residual collisions
fail. References are remapped consistently without changing supported ranks.

The command copies only validated photos, corpus, taxonomy and existing fact
cards; it writes an explicit repair report and `sol-rank-preparation.json`
receipt last. Files are private and exclusively created. Historical plans,
approvals, credentials, pricing and journals are never copied. Incomplete
destinations cannot be overwritten or resumed; inspect them and use a new
destination after addressing the failure.

The candidate `openai_photo_sol_rank_limits_low_v1` changes biological
instructions and descriptive schema guidance, preserving JSON structure, Sol
settings, mineral rules and the current explanation definition. It is
evaluation-only and rejected by production and historical live bindings. The
receipt binds proposed request identities for six screens and six paired
challenges, but marks live admission, reference review and dispatch unavailable.
It is not a runnable live plan or a pricing/spending approval. A separate live
contract is now implemented. Before dispatch, create
`sol-rank-reference-review.json` from assistant input/fact review, retaining
provisional references and finite-catalog limits; never mark independent truth
verified. Bind its digest and the unchanged preparation receipt in a fresh
`sol-rank-plan.json`, alongside corrected inputs and `sol-rank-pricing.json`.
The plan fixes six candidate screens and six alternating same-model pairs, 18
calls maximum, one attempt each. The conservative full-context reservation is
$106.383024 at the reviewed rates; a new $110 cap and fresh bound approval are
required, not the previous run's $40 allowance.

Run the scoped offline preflight from a clean reviewed checkout:

```bash
deno run --frozen --no-prompt --cached-only \
  --config services/supabase/functions/deno.json \
  --deny-net --deny-env --allow-run=git \
  --allow-read="$PWD,/absolute/private/sol-rank-packet" \
  --allow-write="/absolute/private/sol-rank-packet" \
  services/supabase/scripts/evaluate_identification.ts \
  preflight-sol-rank-photo /absolute/private/sol-rank-packet
```

It writes `sol-rank-preflight.json` with rebuilt request hashes, v2 record
identity, review policy, source and reservation. Fresh `sol-rank-approval.json`
binds that plan, clean source, credential fingerprint, reviewer/delegation,
budget and a window no longer than 24 hours. Then use:

```bash
bash services/supabase/scripts/run_openai_evaluation.sh \
  --sol-rank-photo-live /absolute/private/sol-rank-packet
```

The key is entered once through hidden terminal input and retained only in the
child process. The assistant reviews transient responses; only bounded results
and ratings are saved. The launcher checks the new final state and never calls a
stopped run complete. Inspect `sol-photo-rank-run/state.json` and `summary.json`
for completion, failed attempts, mapping/reference gaps and phase-specific
denominators. An unknown mapping is `screen_unassessable`, not a wrong taxon. Do
not erase a claim, retry an interrupted assignment or reuse old approval.

The
[first Sol rank run](../rfcs/identification-sol-rank-screen-results-2026-09-29.md)
stopped after one request. A source-to-fact audit found omitted publisher
metadata; the recorded failure cannot establish a model defect. Its append-only
adjudication binds the original journal and source record. Prospective fact
corrections are separate inputs, not a runnable plan or a replacement historical
rating. Preserve publisher labels, visible observations and diagnostic limits as
distinct evidence. Missing coverage is `insufficient_reference`; it is not
automatically invented evidence or unsupported specificity. A concrete failure
needs a resolved contradiction or an applicable reviewed diagnostic requirement.
For new runs, `sol_photo_rank_summary_v2` reports `identityInterpretation` and
`identityInterpretationCounts` separately from raw reference comparison fields;
consult both alongside explanation ratings. Limited-reference mismatches are
unassessable, while actual explanation failures remain visible. Keep historical
v1 summaries unchanged. New run bindings freeze v2 reporting; an existing v1
binding is refused before admission without changing any journal file or
dispatching another call. The separately approved corrected comparison rebuilt
its receipt and reference review, preserved every model-request digest, and
completed all eighteen calls under a fresh clean-source approval. Its
[results](../rfcs/identification-sol-rank-comparison-results-2026-09-29.md)
record broader-rank improvements and two concrete candidate visual failures.
Retain the current Sol profile; do not promote this candidate or rerun the
completed packet. Production rank/enrichment design and confidence calibration
remain later steps in the linked plan. Future live comparisons still require
their own clean-source preflight and execution approval.

## Observed-traits OpenAI optimization

The
[current candidate record](../rfcs/identification-openai-observed-traits-candidate-2026-09-29.md)
owns the production prompt `openai_identify_vision_observed_traits_v1` and the
frozen offline candidate `openai_photo_sol_observed_traits_low_v1`. Two pure
projections in `openaiPhoto.ts` replace fixed-count directions with one to three
directly supported traits. Production retains `openai_photo_v1`,
`merian_openai_identify_v1`, Sol, explanation format and the accepted 1–10 trait
array bounds. The offline candidate retains its private schema name and original
hashes; no runner or production assignment selects that evaluation identity. Run
its compatibility checks with network and environment access denied:

```bash
deno test --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/ai/openaiObservedTraits_test.ts
```

These tests establish request isolation and decoding compatibility, not model
quality. The updated plan treats the two wording changes as a small beta
improvement: the versioned prompt is integrated in source, with affected
regressions and normal CI preceding a few ordinary beta scans. After existing
additive backend and migration prerequisites are deployed, distribute the
updated iOS reader before deploying this prompt revision: it recognizes both
prompt versions for display-only badges, while older readers show Needs review
for the new prompt. Result shape, protocol minimum and database schema stay
unchanged. A dedicated comparison runner is unnecessary for this change.
Preserve explanation format and use the final prompt configuration for
confidence calibration. Existing experiment budgets remain closed; see the
candidate record for the exact scope and smoke checks.

## Explicit-primary Sol comparison

The completed Sol rank experiment remains frozen. The separate evaluator profile
`openai_photo_sol_primary_low_v1` now prepares a required resolution, names and
species-ranked alternatives under a new private schema. Its pure decoder and
normalizer check the explicit-primary contract using synthetic fixtures while
preserving the current photo model, generation, explanation format and
moderation request. No existing paid-plan parser or production binding selects
it. See the
[implementation checkpoint](../rfcs/identification-primary-resolution-contract-2026-09-29.md#isolated-explicit-primary-candidate--2026-09-29)
for frozen configuration hashes and remaining qualification work.

Run its local contract checks without network or credentials:

```bash
deno test --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  services/supabase/functions/_shared/ai/openaiSolPrimary_test.ts \
  services/supabase/functions/_shared/ai/openaiSolPrimaryNormalization_test.ts \
  services/supabase/functions/_shared/ai/openaiSolPrimaryAdapter_test.ts
```

A new live comparison requires its own reviewed packet, bounded plan and
authorization. The current command only tests implementation; it neither runs an
identification benchmark nor qualifies a confidence display policy.

The
[offline comparison packet](../rfcs/identification-sol-primary-comparison-preparation-2026-09-29.md)
contains twelve cases, including dog, cat and unresolved-biological examples.
All five resolution states are represented; family and unresolved references
remain limited. The separately approved eighteen-request run is
[complete](../rfcs/identification-sol-primary-comparison-results-2026-09-29.md).
Retain the current Sol profile: the candidate's rank improvements do not cancel
its visual-grounding failure. Do not rerun the completed packet. Historical
experiment parsers and production bindings remain closed to this profile.

The current order is OpenAI optimization, then confidence calibration for the
selected configuration. The
[completed offline audit](../rfcs/identification-openai-confidence-evidence-audit-2026-09-29.md)
found that the eighteen matching controls cover only six photos and cannot
establish new cutoffs. Keep existing display thresholds provisional. The new
[observed-traits candidate](../rfcs/identification-openai-observed-traits-candidate-2026-09-29.md)
is offline-only. The historical preparation and execution commands below do not
admit it or reopen the completed explicit-primary comparison.

To prepare another immutable copy after reviewing its source records, use the
two-path offline CLI. Both source and destination parent must be private and
outside the repository. The destination must not exist:

```bash
evaluation_parent="$HOME/Developer/merian-evaluation"
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$evaluation_parent" \
  --allow-write="$evaluation_parent/NEW-PRIMARY-PREPARATION" \
  services/supabase/scripts/prepare_sol_primary_candidate.ts \
  "$evaluation_parent/2026-09-29-sol-primary-source-v2" \
  "$evaluation_parent/NEW-PRIMARY-PREPARATION"
```

The source supplies `primary-preparation-plan.json` and
`primary-reference-review.json` under their separate closed contracts. The
review binds input/reference/fact digests, support limits, private source
attribution and role evidence. A lookalike comparator must be a distinct
reviewed species outside the accepted identities. The builder writes
`primary-preparation.json` last, with coverage and exact request hashes. It
copies no historical authorization or results and accepts no key or live flag.
The existing corpus curation permission token does not authorize disclosure to a
new provider.

### Bounded explicit-primary execution

The separately versioned controller is now implemented. It does not extend the
historical Sol-rank or photo-model plan parsers. The frozen preparation receipt
continues to describe the state when it was created; its
`liveControllerAvailable: false` is historical, not a mutable switch. A new
`sol-primary-preflight.json` describes current runner readiness.

Before dispatch, the private prepared directory must additionally contain:

- `sol-primary-plan.json`: `sol_photo_primary_plan_v1`, binding the existing
  packet, preparation receipt, review, current pricing, the exact six screens
  and six challenges, one attempt each, eighteen calls maximum and a new budget.
- `sol-primary-pricing.json`: reviewed standard synchronous pricing no older
  than seven days. Reservation uses the existing full-context Sol ceiling plus
  the regional multiplier; this is a spending bound, not expected cost.
- `sol-primary-approval.json`: `sol_photo_primary_approval_v1`, explicitly
  authorizing `18_call_sol_primary_photo_comparison` for Naturebook, the exact
  clean source, plan, credential fingerprint and budget. It expires within
  twenty-four hours and binds assistant review. Historical approvals cannot be
  relabeled or reused. Real-input disclosure permission belongs to the new plan.

For a separately prepared and authorized future comparison, replace the
placeholder below with its new private packet. The completed
`2026-09-29-sol-primary-photo-preparation-v2` journal is historical evidence,
not a reusable execution target. Preflight performs no model request and needs
no credential:

```bash
evaluation_packet="$HOME/Developer/merian-evaluation/NEW-PRIMARY-PREPARATION"
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$evaluation_packet" --allow-write="$evaluation_packet" \
  --allow-run=git services/supabase/scripts/evaluate_sol_primary.ts \
  preflight "$evaluation_packet"
```

After the new bounded execution is authorized, the existing hidden-key launcher
accepts this separate mode:

```bash
bash services/supabase/scripts/run_openai_evaluation.sh \
  --sol-primary-photo-live "$evaluation_packet"
```

It rejects stale or dirty preflight before prompting, holds the key only in the
child process environment and grants network access only to the provider and
private loopback review. The controller revalidates before every durable claim.
An interrupted claim or missing review stops permanently without replay; the
reservation remains held. New journals live under `sol-photo-primary-run` and
use separate record, manifest, binding, review, stop and summary versions.

`primary_reference_limits_v1` admits screens only as `pass` or
`reference_limited`. The latter requires a predeclared limited reference and
ratings that are all pass or exactly not-assessable/insufficient-reference. It
never contributes a quality pass or an explanation-pass count. An unsupported
visual claim, rank conflict, provider error or unusable review still stops;
unmapped and ambiguous names are unassessable and stop screening. Challenge
failures remain visible comparison outcomes; provider or missing-review failure
stops further calls. Subject and identity disagreements remain in raw comparison
counts alongside their limited-reference interpretation. No score from this
pilot qualifies confidence badges or a Free/Pro split.

## Fixed initial assignment

| Setting                     | Candidate                                                                    |
| --------------------------- | ---------------------------------------------------------------------------- |
| Evaluation profile          | `openai_gpt_6_sol`                                                           |
| Model                       | `gpt-6-sol`                                                                  |
| Transport                   | One synchronous POST to `https://api.openai.com/v1/responses`                |
| Input                       | Prepared photos (JPEG, PNG, WebP) and observation text                       |
| Reasoning / image detail    | `low` / `high`                                                               |
| Output                      | Strict common Identify JSON schema; 8,192 output tokens, including reasoning |
| Deadline / response ceiling | 90 seconds / 512 KiB                                                         |
| Confidence                  | `openai_unqualified_v1`; no Gemini match bands or diagnostic suppression     |

This is an initial candidate configuration, not a demonstrated quality or
latency winner.
[OpenAI's model documentation](https://developers.openai.com/api/docs/models/gpt-6-sol)
was reviewed on 25 September 2026. It documents text/image input and structured
output, and directs API clients to the alias `gpt-6-sol`; no dated snapshot was
listed. Record the returned model and run time. An alias does not establish an
immutable underlying model version. A returned-model mismatch stops the run.

The first slice rejects **the complete observation** when it contains WAV audio,
video frames, video capture metadata, an unsupported image type, or another
task. A five-second video in Naturebook supplies snapshots and may include
companion audio; it is not a native-video model request. Snapshot support can be
qualified later without discarding its accompanying evidence. No observation is
split into extra provider calls or silently reduced to photos.

## Implementation and data boundary

- `_shared/ai/openaiRequest.ts` owns the immutable evaluation binding, ordered
  evidence projection and strict-schema conversion from
  `_shared/identify/contract.ts`. It retains the existing visual/text task
  instructions and adds explicit optional-null and unqualified-score guidance.
- `_shared/ai/openai.ts` owns credentials supplied by the evaluator,
  fixed-origin transport, response-size/deadline enforcement, refusal/error
  decoding and usage. There is no SDK, URL override, retry, remote-media fetch,
  tool use, background job or stored conversation. Preparation performs no
  disclosure; the common executor permits one invocation.
- `scripts/identification_evaluation/providers.ts` selects evaluation profiles.
  Production `production.ts` contains a separate enabled photo composition,
  using `openaiPhoto.ts` and the exact registered binding. Credential lookup
  follows admitted catalog assignment; the beta catalog assigns only still
  photos to OpenAI. Deploy the enabled bundle before a separate photo assignment
  migration. Evaluation profiles are not production assignments. The
  [photo integration record](../rfcs/identification-openai-photo-integration-2026-09-27.md)
  owns the implemented admission, safety, provenance and compatible-reader work.
- Required fields, bounds and enums still pass the common Identify parser.
  Provider-required null optionals map back to the domain contract; missing or
  extra provider fields fail. Domain normalization retains OpenAI candidates
  without applying Gemini's diagnostic threshold.
- Artifacts contain bounded decisions, requested/returned model, usage, timing
  and hashes. Prompts, photos, provider prose, reasoning items and error bodies
  are never copied into run results.

`store: false` disables stored Responses state. It does **not** promise zero
provider retention: default abuse monitoring and prompt-cache processing require
separate review. Consult
[OpenAI's data controls](https://developers.openai.com/api/docs/guides/your-data)
for the actual account and region before live disclosure.

## Offline verification

Run from the repository root. The parent directory must be private and outside
Git; the demo creates a new child. This uses invented images/text and fixed
outcomes, with no API key or network access:

```bash
evaluation_parent="$(mktemp -d)"
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$evaluation_parent" --allow-write="$evaluation_parent" \
  --allow-run=git \
  services/supabase/scripts/evaluate_identification.ts \
  demo-providers "$evaluation_parent/providers"
```

The eight assignments compare native Gemini Pro/OpenAI request preparation for
four synthetic photo/text cases. `runs/offline-providers-v1/` contains the
manifest, immutable claims/results and report. Running `offline` again resumes
without repeating claims. `preflight` prepares an explicitly selected provider
spec without dispatch; historical corpus-only preflight remains Gemini-only.
Offline reports prove mechanics, never biological quality, speed or price.

## Credential storage and future deployment

The long-term deployment source is the `NATUREBOOK_OPENAI_API_KEY` environment
secret in `emreerdener/merian` → `Production`, alongside the existing backend
provider credentials. This is the backend environment named exactly
`Production`; the `Production – naturebook` and `Production – naturebook-admin`
environments serve the web applications. Keep a recovery copy in the owner's
password manager. Do not put the key in source, app configuration or artifacts.

The name is intentionally separate from the repository's `OPENAI_API_KEY`, which
is consumed by the unrelated Agent Quality workflow. Storage alone does not run
a comparison, synchronize a Supabase secret or enable the provider. The manual
**Compare identification providers** workflow now reads the Naturebook key in
its protected evaluation steps. The protected production deployment now
synchronizes a configured value into the same-named Supabase Edge secret and
verifies its stored digest. An absent value skips synchronization and leaves any
existing runtime copy untouched.

The first pilot ran locally with a private packet and persistent run ledger. The
subsequent
[hosted comparison procedure](./23-hosted-identification-comparison.md) reuses
the existing public `merian` bucket for owner-approved test exports and durable,
one-shot experiment claims. It preserves provider-scoped credentials and
prevents a fresh GitHub runner from repeating an admitted comparison. No
self-hosted runner or local key retrieval is required for that path.

The local runner requires the same key from the owner's password manager; GitHub
does not provide a way to read a saved secret back. The terminal launcher below
injects it transiently as `OPENAI_EVALUATION_API_KEY`. GitHub is the deployment
source and Supabase is the runtime store. The
[deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md#required-and-optional-github-secrets)
owns the env-backed CLI transport, digest verification and failure handling.
Successful synchronization proves only that the key was copied; it does not
validate provider access or activate OpenAI traffic. The photo composition is
source-enabled ahead of catalog activation; the beta catalog changes only
still-photo assignments. Settings retains explicit choice collection, while the
owner-requested beta policy allows an absent OpenAI choice and honors explicit
withdrawal. Provider qualification, traffic activation and rollback remain
separate decisions.

### Private local key entry

Use `scripts/run_openai_evaluation.sh` under `services/supabase` from a trusted
local terminal on macOS/Linux with Python 3 and the repository-pinned Deno
installed. The launcher uses Python's hidden terminal prompt. It refuses an
unavailable terminal or echoed-input fallback, disables shell tracing, ignores
Python environment/custom user imports, and never saves or prints the key. Do
not paste a credential into chat, a shell command, an environment file or an
editor. It intentionally does not read an inherited key.

For initial readiness preparation, create a new private directory outside Git
and run:

```bash
private_review="$(mktemp -d)"
bash services/supabase/scripts/run_openai_evaluation.sh \
  --credential-fingerprint "$private_review"
```

Paste the existing Naturebook key **only when the hidden prompt appears**. The
only written file is `openai-credential-fingerprint.json` (mode `0600`),
containing a version and SHA-256 hash for the readiness record. No network or
provider call occurs. The file is created exclusively; an existing fingerprint
is never overwritten. This is a credential binding, not proof of valid billing
or input permission. Preserve it privately and bind its hash into the reviewed
readiness record described below; the launcher does not approve or alter that
record.

After the private packet has current pricing, OpenAI input permission, reviewed
readiness and a budget-bound live spec, run:

```bash
bash services/supabase/scripts/run_openai_evaluation.sh --live PRIVATE_RUN_ROOT
```

The directory must already exist outside Git, belong to the operator and have
mode `0700`. The launcher checks that the spec selects only OpenAI and runs the
existing offline preflight before asking for the key. Dependencies must already
be cached: run the offline demo above before handling credentials. The live
child receives only `PATH`, `HOME`, optional `DENO_DIR` and
`OPENAI_EVALUATION_API_KEY`; its Deno environment/network permissions remain the
narrow ones below. Dependency downloads, inherited service credentials, Git
configuration environment overrides and non-OpenAI provider dispatch are
excluded from this entry point.

The existing evaluator remains responsible for every approval, key hash, request
fingerprint, call/budget limit and durable claim. The wrapper never retries a
run or removes its ledger. Its success message means artifacts were written;
inspect the private report for completeness, unknown executions and failures
before interpreting the benchmark. An interruption is resumed only through the
same evaluator/root; never erase claims or create a fresh run to repeat
uncertain calls. Key entry is required again for each launcher invocation. For
an approved OpenAI-only experiment, `--experiment-session PRIVATE_RUN_ROOT`
prompts once and invokes the existing controller for each frozen run in order,
stopping on failure, a durable stop, incomplete state or a changed plan. The key
stays only in memory for that session; no persistent credential store is added.

## First live comparison

Reuse eligible photo/text source packets and labels, preserving prior evidence.
An exploratory packet can retain provisional references and an owner review;
there is no new requirement for a second reviewer. Formal qualification keeps
its existing independent-reference requirements. Freeze the small case list and
budget before execution, then compare identity agreement, unresolved answers,
failures, latency and estimated cost. OpenAI raw scores remain unqualified;
Strong/diagnostic metrics are not estimable until a confidence policy is
qualified. The native app's
[OpenAI display thresholds](../rfcs/identification-openai-confidence-display-2026-09-28.md)
only choose existing UI labels; they do not qualify these benchmark metrics or
retroactively change retained reports.

The executable owners are `runContracts.ts` and `admission.ts`:

1. Use `identification_provider_run_spec_v1`. Offline runs may select Gemini and
   OpenAI together. Each live provider run selects **one profile** so its host,
   credential, pricing and processor approval have a single recipient. Use new
   run IDs for Gemini and OpenAI on the same frozen inputs/source. The existing
   two-profile Gemini specifications remain valid unchanged.
2. Supply `evaluation_openai_processor_v1` with `provider: openai`, the existing
   reviewed project/key, terms, data-use, region, retention and validity fields,
   plus
   `inputPermission: {provider, corpusDigest, caseIds, reviewRef, approved}`.
   That record must explicitly approve OpenAI for the exact corpus and selected
   cases, with `approved: true`. It supplements the corpus's historical
   `gemini_evaluation` curation; it cannot be inferred from it. Its lifetime is
   the enclosing review's expiry, bounded by source retention. Opaque review
   references are operator assertions, not cryptographic proof of permission.
   `dedicatedEvaluationProject` is an explicit boolean: use `false` for a shared
   Naturebook application project and `true` for a dedicated evaluation project.
   The same reviewed OpenAI key may serve the app and these benchmarks; a
   separate test project/key is optional. Shared usage consumes the same project
   limits, and the runner's budget accounts only for its own calls. The legacy
   Gemini `evaluation_processor_v1` remains dedicated-project-only. New Gemini
   runs may use `evaluation_gemini_processor_v1` with `provider: gemini`, an
   explicit project-kind Boolean and the same exact corpus/case permission
   structure naming Gemini. This permits the owner's existing paid application
   project without asserting that it is dedicated; it never approves OpenAI. The
   [Gemini procedure](../../services/supabase/scripts/identification_evaluation/README.md#future-explicitly-approved-gemini-live-use)
   owns credential, review, expiry and execution requirements.
3. Supply `evaluation_openai_pricing_v1`, `provider: openai`, with the model
   page above as `sourceUrl`, USD, `paid_standard_synchronous`, retrieval/review
   references and `includesReasoning: true`. Its single model is `gpt-6-sol`.
   Input rates are `text`, `image`, `cached`, `cacheWrite`; review worst-case
   synchronous rates including long-context/cache-write charges. There are no
   built-in prices. Reserve at least the full 1,050,000-token model context as
   `maxInputTokens` and at least 8,192 as `maxBillableOutputTokens`; the
   deliberately conservative reservation may exceed likely actual cost. Prices
   expire after seven days. Never lower ceilings merely to fit a budget.
4. Bind pricing/readiness digests and a positive explicit USD budget in the
   spec. The named `OPENAI_EVALUATION_API_KEY` must match the reviewed
   credential hash. Keep the key in the process environment, never a command
   argument or artifact. The evaluator checks approval again before each durable
   claim and invocation. A shared application key must still be injected under
   `OPENAI_EVALUATION_API_KEY`; the evaluator does not read `OPENAI_API_KEY`.
   This environment name scopes the runner's access, not the key's vendor-side
   privileges. Creating a key does not enable OpenAI in the production backend.

Use the terminal launcher above after authorization and private preparation.
Internally it executes the existing evaluator with
`--frozen --no-prompt
--cached-only`, read access to the checkout and private
packet, write access to only the packet, and `--allow-run=git`. Its live Deno
permissions grant network access only to `api.openai.com:443` and environment
access only to `OPENAI_EVALUATION_API_KEY`. It explicitly denies `SUPABASE_*`,
`R2_*`, `GOOGLE_*`, `GEMINI_*`, `WS_*` and `OPENAI_API_KEY` with `--deny-env`.
Deno's `--no-prompt` suppresses prompts but does not itself make these
permission states `denied`; the live admission checks require explicit denial.
See
[Deno's permission reference](https://docs.deno.com/runtime/reference/permissions/).
The launcher regression test exercises the actual Deno admission gate with a
synthetic key and no provider invocation. Source fingerprinting uses a Git
subprocess with hooks and filesystem monitoring disabled; that subprocess also
inherits the restricted child environment. This is a trusted local tooling
boundary, not isolation from other processes running as the same
operating-system user.

Broad environment/network permissions, Supabase/storage credentials and Gemini
SDK variables are rejected for OpenAI. The existing Gemini command remains in
the
[evaluator guide](../../services/supabase/scripts/identification_evaluation/README.md).
No changes to hosted secrets, Supabase or the simulator are needed for this
local comparison. This guide does not authorize a paid run.

Provider-run manifests add a validated `transports` catalog; `source.sdk`
retains the repository's Google SDK pin for comparison compatibility, while
`transports.openai` records `openai_responses_https_v1`. Complete source hashes
include the adapter. Existing manifests and audio evidence keep their formats.

Responses usage includes reasoning in `output_tokens`. The adapter separates
visible output from reasoning once, and the estimator charges total output once.
Unknown/malformed usage, model drift, uncertain execution, exhausted budget or
call limit stops further paid calls. No retry or failover occurs. Reports retain
all failures and excluded/unknown states; estimates are not invoice-exact caps.
The formal `compare` command requires matched cases/source/boundaries;
exploratory reports remain provisional and must not be passed off as formal
qualification.

## First live pilot evidence

The
[25 September photo/text pilot](../rfcs/identification-openai-photo-text-pilot-2026-09-25.md)
records seven normalized OpenAI results and one preserved unknown outcome across
eight existing examples. Four species results and both non-biological results
agree with provisional references; the mushroom name could not be scored from
its retained taxonomy mapping. The four untouched cases completed in a separate
bounded continuation without replaying any claimed case. This closes the initial
provider-path check, not production qualification. The dated record owns the
measurements and limitations.

## Shared measurement and planned optimization

Optimization Slice 1 is implemented for new offline exploratory packets:
reviewed canonical/synonym catalogs, explicit mapping states, v2 reports,
rate-aware cost estimates and a separate `compare-exploratory` command. Existing
v1 records keep their original interpretation. The
[tooling guide](../../services/supabase/scripts/identification_evaluation/README.md#shared-measurement-repair-optimization-slice-1)
owns formats, offline commands, missing-measurement rules and compatibility.
OpenAI native usage now includes bounded cache-write counts when reported; old
attempts do not gain those missing values retroactively. Historical attempts
have no explanation assessment; the retained concise candidate contracts require
the private review described below.

The
[current optimization plan](../rfcs/identification-optimization-preserving-results-2026-09-27.md)
records the completed existing-evidence bottleneck audit and OpenAI prompt
review. The isolated explicit-null visual candidate is now implemented for
evaluation; explanation format and detail stay intact. No new owner practice
exercise or Gemini benchmark campaign is required. Live candidate comparison
remains pending a fresh bounded allocation.

The [earlier plan](../rfcs/identification-provider-optimization-plan.md) records
the implemented measurement and experiment controls. Its Slice 2 supplies
immutable baseline descriptors, a frozen experiment plan, shared
allocations/reservations, an exclusive controller and a persistent global stop.
The
[controller contract](../../services/supabase/scripts/identification_evaluation/README.md#reusable-profiles-and-experiment-controls-optimization-slice-2)
owns `experiment-preflight`, `experiment-offline`, `--experiment-live` and
`experiment-report`. The OpenAI hidden-input launcher accepts
`--experiment-live <packet> <runId>` or `--experiment-session <packet>` for one
key entry across the ordered OpenAI runs. The retained
[private candidate workflow](../../services/supabase/scripts/identification_evaluation/README.md#concise-openai-candidate-and-private-review)
adds code-defined uncached control/concise profiles, bounded v3 attempts and
ephemeral explanation assessment. V2 experiments preserve owner calibration; v3
experiments record explicitly delegated AI review without a human practice
exercise. Their v3 reports identify AI assessment and no independent human
validation. The assistant processes only the task-approved corpus and bounded
review fields in its session; evaluator files still exclude explanation prose.
Only candidate live runs add loopback and fixed macOS opener permissions. Any
cache anomaly or missing/failed review stops remaining calls while preserving
completed results and cost. Reports apply the frozen latency/quality gates and
remain unqualified. Standalone candidate dispatch is blocked. Offline synthetic
validation establishes mechanics only. The owner approved the real eight-case,
16-request/$86 comparison on 26 September 2026. Its
[outcome record](../rfcs/identification-openai-concise-screen-2026-09-26.md)
closes the screen as inconclusive after one control result: identification
matched the provisional reference and observed cache counters were zero, but
lookalike claims could not be assessed against the frozen facts. Fifteen
assignments remain unattempted; retain the existing profile and defer the
concise candidate. The single result does not establish general cache support or
qualify production use. These profiles and tests remain available as historical
and regression contracts; their presence does not schedule another comparison.

The v1 controller accepts the two original baseline profiles; v2/v3 remain
specific to the closed concise hypothesis. The separate
[v4 explicit-null contract](../../services/supabase/scripts/identification_evaluation/README.md#openai-explicit-null-candidate)
compares the unchanged OpenAI baseline against four visual-prompt wording
changes, using six photos and twelve calls live. It retains baseline automatic
caching, delegated review and explanation detail; cache observations remain
descriptive, with no speed target or automatic production promotion. New run and
attempt versions preserve historical decoding. Packet JSON cannot select
arbitrary settings or authorize spending; the tooling owner remains
authoritative for admission.

## Later production assignment

The
[matched Gemini/OpenAI photo/text comparison](../rfcs/identification-gemini-openai-matched-comparison-2026-09-27.md)
completed all 16 first attempts on 27 September. Its
[outcome record](../rfcs/identification-gemini-openai-matched-results-2026-09-27.md)
preserves the source, measurements, description failures and cost limitations.
Both configurations agreed with five provisional biological photo references and
the mineral control. OpenAI's observed photo median was 7.10 seconds versus
15.81 seconds for Gemini Pro; this small reused corpus remains unqualified.

The
[photo integration record](../rfcs/identification-openai-photo-integration-2026-09-27.md#provider-infrastructure-closeout--27-september-2026)
records completed infrastructure and verified deployment of the OpenAI key
synchronization. The primary handler prepares a result policy before quota
commitment; the photo binding has separate safety, provenance, admission,
accounting and reader contracts. Beta activation changes only still-photo
assignment. The forward correction defers all OpenAI-specific collection and
enforcement for beta accounts, irrespective of past OpenAI choices, while
preserving the immutable history and ordinary required consent.
Description-only, audio and sampled-video observations retain Gemini.
Released-reader verification, full production-profile qualification, TestFlight
archive and released-store upgrade verification remain separate evidence; source
completion does not claim those outcomes.

The implemented admission slice records an exact Gemini
provider/binding/permission assignment per metered identification attempt and
rejects unqualified recipients before dispatch. See its
[implementation record](../rfcs/identification-provider-production-admission-2026-09-26.md).
The subsequent
[OpenAI consent slice](../rfcs/identification-provider-openai-consent-2026-09-26.md)
implements independent evidence, strict recipient proof and optional Settings
choices. Those controls are now dormant during beta; access is a separate
current-account projection that never creates evidence. A future public rollout
must pair enforcement with a direct disclosure action on each permission alert
and a return to the same saved scan for explicit retry. Account changes, failed
saves, revocation and causal synchronization are covered locally. Required
onboarding and the ordinary consent gate remain unchanged; photo inference
additionally applies the current server-owned beta recipient policy. The
[server provenance slice](../rfcs/identification-provider-result-provenance-2026-09-26.md)
now retains successful Gemini provider/model and generation/confidence
configuration with atomic recovery backups. Historical unknown values stay null.
The
[client provenance slice](../rfcs/identification-client-result-provenance-2026-09-26.md)
adds DTO/V52 storage and neutral unknown-profile presentation; the
[native preflight slice](../rfcs/identification-native-recipient-preflight-2026-09-26.md)
carries app-assigned recipient expectations through dispatch and retries. These
implemented controls do not qualify OpenAI's runtime safety or confidence. The
optional concise-prompt screen is closed and is not required to implement these
boundaries. Follow the
[provider onboarding contract](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md).
Photo/text could then receive one provider and audio-containing observations
another, using complete-task capability checks. This slice enables that work
without changing today's production assignment.
