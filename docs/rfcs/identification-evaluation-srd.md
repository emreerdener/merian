# Naturebook Identification Evaluation Readiness — SRD

Document ID: NB-SRD-IDENTIFICATION-EVAL-001\
Version: 0.19\
Date: 23 September 2026\
Status: Slices 1–3 and exploratory automation implemented; photo, description,
first video and expanded audio app checks completed; reviewed baseline pending\
Product authority:
[Evaluation Readiness PRD](../product/04-identification-evaluation-prd.md)

## 1. Scope and evidence boundary

Implement a local evaluation tool for the existing primary identification path.
Both live profiles remain Gemini: `gemini-2.5-flash` with the free-tier policy
and `gemini-2.5-pro` with the Pro-tier policy. Use their current registry
settings, including prompt selection by actual evidence. Do not hand-copy
settings or silently substitute a newer model if an approved model becomes
unavailable.

The formal live corpus covers still images, descriptions, audio, sampled frames,
frames with audio, and still images with audio. Compatibility endpoints and
supporting content tasks retain their existing tests but are not qualified by
these scores.

The measured boundary is **prepared evidence → provider execution → normalized
identification decision**. It excludes upload/capture time, real user admission,
dictionary/GBIF hydration, enrichment, database writes, durable recovery, and
iOS rendering. Describe reports as identification evaluation, not complete app
accuracy or shutter-to-result latency. The
[AI architecture](../system-architecture/04-ai-engineering.md) and
[provider onboarding guide](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md)
continue to own runtime and later activation requirements.

## 2. Reuse and the one required runtime extraction

| Existing owner                                                           | Use in this milestone                                                                                                             |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `functions/identify-multimodal/provider.ts` — `buildMultimodalAIRequest` | Build the same evidence ordering and capture/frame/audio relationships from prepared, approved fixtures.                          |
| `functions/_shared/ai/registry.ts` — `resolveAIClaim`                    | Resolve the actual prompt, schema, model, tier thresholds, and generation settings.                                               |
| `functions/_shared/ai/execution.ts` and `gemini.ts`                      | Reuse one-shot invocation, provider outcome classification, returned model, timings, and normalized usage.                        |
| `functions/_shared/identify/normalizeIdentification.ts`                  | Reuse executable parsing, name/pet normalization from `functions/identify/sanitize.ts`, subject decisions, and confidence policy. |
| `scripts/benchmark_ai_boundary.ts`                                       | Keep as a separate, network-denied adapter-overhead benchmark. It supplies no biological quality evidence.                        |
| `scripts/evaluate_field_chat_answers.ts`                                 | Reuse the explicit live opt-in and injectable assessment pattern; its structural chat cases are not identification ground truth.  |

Paths in this table are relative to `services/supabase/`. Reconcile them with
merged source before implementation; function organization may move owners.

Slice 2 extracted the existing post-provider parsing and normalization into
`functions/_shared/identify/normalizeIdentification.ts`. Both the production
`identify-multimodal/index.ts` route and the scripts-only
`identification_evaluation/normalization.ts` bridge call it. It remains between
provider outcome handling and dictionary hydration.

The helper receives the provider draft, modality/profile facts, and the existing
non-secret context needed by policy: actual visual/audio presence, admitted
inference tier, and a Boolean for invasive-location availability. It returns the
parsed and normalized identification, audio disposition, separate client
candidates/life stage, and in-memory diagnostics for the route's existing
logger. Domain candidates remain distinct from the suppressed client projection.
It preserves scientific-name and domestic-pet normalization, bounded fields,
processed-material demotion, audio subject precedence, context-dependent policy,
and diagnostic candidate suppression. It performs no network, database,
allowance, or telemetry operation. Preserve the route's final hydrated response
validation separately. The evaluator's deviceRegion/month context does not
qualify as the GPS or semanticLocation that the existing invasive rule requires.
Neither model prose nor returned diagnostics is a durable evaluation artifact;
taxonomy mapping and bounded prediction projection belong to Slice 3.

The evaluation records backend confidence bands and server candidate presence.
It does not call that the final candidate-review UI: iOS applies further
visibility rules, saved user decisions, and taxonomy handling. Existing route
and Swift contract tests remain the authority for those consumers.

Use a scripts-only fixture authority to resolve each existing approved profile,
as the current benchmark does. Its synthetic identifiers are test values, not
consent receipts or real reservations. Never add an evaluation authority
accepted by HTTP handlers, widen production provider/model unions, or use public
species jobs to authorize private identification. Live evaluation eligibility
comes from the reviewed corpus and run specification, not this synthetic
registry context. The separately tagged exploratory route below accepts eligible
provisional evidence under the same live execution controls.

## 3. Corpus and reference-answer contract

Keep tool code and synthetic examples in Git. Store real approved media and
curation records in an access-controlled directory outside the repository;
record an owner and retention/deletion date. Do not import production
observations or response bodies. Default to purpose-collected material or
individually reviewed licensed sources. Rights to view or download a file do not
establish permission to send it for provider evaluation or use it for training.

Define separate input and reference-label records with a versioned schema:

| Record          | Required contents                                                                                                                                                                                                                 |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Input           | Opaque case/group ID, input group, development/held-out split, sanitized observable text, ordered local assets with hashes/MIME types, frame/clip/audio lineage, approved coarse context or no context, and preparation version.  |
| Reference label | Expected subject class (biological, non-biological, or indeterminate), expected resolution (named or unresolved), independently supported taxon IDs/ranks and alternatives, and the most specific rank justified by the evidence. |
| Curation        | Source/rights record, review for personal information and revealing filenames/metadata, reference evidence, label reviewer and second-review status, difficulty/biological-group tags, and adjudication status.                   |
| Corpus manifest | Schema/taxonomy versions, all included record hashes, split seed and membership, coverage counts, approval record, and immutable corpus digest.                                                                                   |

Curation records identify reviewers through internal non-personal role codes; do
not copy names, personal source accounts, raw coordinates, auth state, or
secrets into fixtures or artifacts. Real assets must exclude identifiable human
faces and speech. Human-only policy cases use synthetic offline provider
fixtures in this milestone. Strip disallowed metadata before hashing and freeze
the final prepared evidence. Preserve allowed image dimensions/compression, WAV
preparation, and frame ordering in a documented recipe; the tool does not fetch
arbitrary asset URLs or production storage keys.

Only the input record reaches request construction. Ground truth, provenance,
taxon-bearing filenames, and reviewer notes cannot become prompt context. Reject
unapproved or malformed assets before network access. Test that the request
builder cannot receive reference-label fields.

Description-only requests still include the production capture-context
projection. Preserve its `Context: no telemetry.` form when no facts are
available, or its exact approved coarse-context form. Hash the prepared request
representation as well as the assets so a text-only shortcut cannot silently
change the evaluated prompt.

Two independent reviews must agree on eligibility and the reference answer;
adjudicate disagreement before admission. A provider prediction, a taxonomy-name
lookup, or an unverified user confirmation cannot establish truth. Freeze a
taxonomy authority/version with accepted IDs, ranks, and synonyms for scoring;
do not make live taxonomy lookups during a run. Unknown prediction names remain
unresolved mappings, never fuzzy matches silently counted as correct.

Assign all views and derived variants of the same observation to one group and
one split; check duplicates and near duplicates before freezing. Use the 60
development groups to debug the method and the 240 held-out groups only after it
is frozen. Keep one primary scored case per independent group in this first
baseline. Exposure to public examples during foundation-model training is
unknown and must be disclosed. Repeatedly tuning against the held-out set would
weaken it as independent evidence; refresh it when used to guide changes.
[Google's dataset guidance](https://developers.google.com/machine-learning/crash-course/overfitting/dividing-datasets)
explains these separation and repeated-use limits.

The curation rubric requires clear positives, lookalikes, degraded evidence,
appropriate unknowns, and non-biological negatives in each applicable input
group. The pilot freezes the detailed coverage matrix before held-out selection.
Do not fabricate paired image/audio observations to fill a quota. If coverage or
reference expertise is missing, report that gap and collect eligible examples.

## 4. Runner, artifacts, and live limits

Proposed tooling owner: `services/supabase/scripts/identification_evaluation/`,
with one thin `scripts/evaluate_identification.ts` entrypoint. Keep dataset
loading, scoring, comparison, and report generation outside deployed functions.
The shared production normalizer and pure native-request assembly belong under
`functions/`; the executable runner remains scripts-only.

The offline default validates manifests and processes synthetic outcomes under
denied network access. Credentials are unnecessary; importing the evaluator must
not initialize a paid run. Later report regeneration reads normalized prediction
records without rerunning inference. Raw real-provider drafts are processed in
memory and discarded; offline raw-response fixtures are synthetic only.

A live run requires explicit selection of the approved corpus digest, Gemini
profiles, evaluation project/key, call cap, and USD budget. Read the key only
from an approved environment variable; never include it in argv, manifests,
output, or artifacts. Give the process no Supabase/service-role credentials or
production storage access. Restrict network permission to the adapter's reviewed
Gemini transport; use a dedicated evaluation credential and project where
available.

Bind the run to a reviewed, versioned processor-readiness record for the actual
Gemini account/project and credential reference, without recording the key. That
record must establish paid-service eligibility and the terms, processing
purpose, region/subprocessors, retention/deletion and abuse-log treatment
applicable to this corpus, including data-use restrictions consistent with its
permissions. Reuse existing reviewed Gemini evidence where it applies; never
infer evaluation or training rights from production consent. The record includes
a fingerprint of the dedicated evaluation credential; its canonical digest is
frozen in the run spec. A missing, expired or changed record blocks dispatch, as
does falling back to an unreviewed account or free-service configuration. This
reviewed attestation does not independently prove vendor billing settings.

Before the first request, validate all inputs and verify a fresh run estimate
against current exact-model pricing. Preserve standard synchronous invocation,
production generation settings and timeout; do not add Batch, automatic retries,
grounding tools, or explicit caching to make the benchmark cheaper or faster.
Record any provider-reported cached usage. Pre-register a shuffled, interleaved
order for the two profiles to reduce systematic order effects.

Default concurrency is one. Planned maximum generation calls are:

| Stage                     | Calculation                                                                                  | Maximum |
| ------------------------- | -------------------------------------------------------------------------------------------- | ------: |
| Development pilot         | 60 groups × 2 current profiles × 1 attempt                                                   |     120 |
| Held-out baseline         | 240 groups × 2 profiles × 1 attempt                                                          |     480 |
| Repeatability check       | 30 preselected development groups, five per input group × 2 profiles × 2 additional attempts |     120 |
| Total across these stages | Repeats remain separate from independent-case metrics                                        |     720 |

These are stage ceilings, not authorization to spend. A pilot rerun after fixing
the method requires a new recorded run and budget; do not hide it in the
baseline totals or replace a failed case until it succeeds. Publish the frozen
method's held-out results separately from development and repeatability results.

The current runner additionally shares pure `geminiRequest.ts` parameter
assembly with the production adapter. Importing the Node SDK reads environment
variables; keeping SDK initialization behind live admission lets offline tools
run with environment and network access denied. Existing native parameters and
production dispatch behavior are unchanged.

Require an exclusive run lock and an atomic persistent `started` claim keyed by
run/case/profile/attempt. Commit and flush that claim durably before dispatch;
fail closed if the lock or durable write fails. A buffered append alone is not
sufficient. Write a terminal result afterwards. A crash or timeout with no
certain result becomes `unknown_execution`, consumes the attempt allowance, and
is potentially charged. Resume dispatches only never-started attempts; a
repeated uncertain attempt requires an explicit new run decision. Do not retry
inside the adapter or SDK. Refusals and invalid output are terminal measured
outcomes. Stop on authentication or rate-limit errors, unknown execution, or the
call/spend guard; report unattempted cases and an incomplete run. The
implemented runner stops on the **first operational failure**, a stricter rule
than the original three-failure ceiling: the adapter combines 400 and 429
outcomes, so continuing could retry after a rate limit. Test dependencies are
rejected in live mode; only the fixed production Gemini composition is allowed.

Track known spend plus conservative reserved cost for the next attempt,
including reasoning/output allowances and modality-specific input. Pause if a
defensible bound cannot be computed or usage needed for budgeting is missing.
The implementation requires pricing no older than seven days, with reviewed
maximum model token ceilings, and reserves those ceilings at worst-case rates.
Known usage is conservatively charged at the highest input rate without a cache
discount and includes thinking. A missing/contradictory total remains unknown.
Local budget guards and vendor quotas are safeguards, not a claim of
invoice-exact hard caps; billing can lag or include uncertain calls. No dollar
estimate is asserted in this plan. Snapshot rates, units, currency, source URL,
and retrieval date for each run; current
[Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing) distinguishes
input modalities, cached input, and output including thinking.

Each run emits a manifest, bounded normalized prediction records, summary JSON,
and a Markdown report. Record the corpus/input hashes, source commit and dirty
state/source digest, scorer/taxonomy versions, requested and returned models,
profile/prompt/schema/confidence references and hashes, SDK version, timing
boundary, timeout/settings, order seed, timestamp, pricing snapshot, and
processor-readiness reference/digest. An unrecorded source or model drift
invalidates comparability.

Prediction records retain opaque case ID, terminal outcome/reason code,
normalized taxon IDs/ranks, subject disposition, confidence and band, bounded
candidate identities, usage counts, durations, and scoring flags. Exclude raw
provider bodies, reasoning, free-form error messages, prompt/media bytes,
secrets, and personal identifiers. Use label codes for manual adjudication
notes. Store these records with the controlled corpus; only reviewed aggregate
reports and synthetic examples are candidates for Git.

## 5. Scoring and denominators

Freeze metric definitions before the held-out run. A named result is a
normalized biological identity offered by the backend, regardless of confidence
band. It is not a user's confirmation. A correct offered result matches an
explicitly allowed taxon and rank for that case. A broader answer is not exact
species correctness; an unsupported specific guess is not correct merely because
it is a descendant of an allowed genus.

Let `N` be all scheduled, scorable cases in the frozen split, including negative
and expected-unresolved cases. Let `B` be the subset with biological reference
subjects and `S` the subset whose evidence supports a species answer. These
denominators are fixed before dispatch, not selected from successful responses.
Unattempted cases remain visible and make a run incomplete. A zero denominator
always produces `not_estimable`, never zero percent or a passing comparison.

For confidence reliability, use all valid named biological results across `N`,
including false biological assertions on negatives and unsupported names on
expected-unresolved cases. In each disjoint score interval report correct
offered results divided by named results in that interval, the count, and the
mean reported score. Use below-Possible, Possible-to-below-Strong, and Strong
intervals from the resolved profile; report the diagnostic interval as an
explicit subset of Strong. Invalid outcomes have no reliability-bin membership
and remain in the operational and all-case quality measures.

For subject classification, measure false biological assertions against known
non-biological references (and synthetic human-only policy fixtures). Measure
biological assertions on indeterminate references separately as unsupported;
unknown ground truth cannot establish factual falsity. Both remain represented
in the subject confusion matrix, and unsupported named guesses still count in
offered precision and confident-error measures.

| Measure                                  | Required calculation and limit                                                                                                                                                                                                                                                                      |
| ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Exact species correctness                | Correct primary species / `S`. Refusal, invalid output, operational failure, unknown execution, and unresolved name mapping contribute no correct answer.                                                                                                                                           |
| Offered-answer precision                 | Correct offered identities / all named biological results, including wrong biological answers on negative cases. Show the denominator and `not estimable` when it is zero.                                                                                                                          |
| Answer coverage and correct-answer yield | Within `B` only: named results / `B`, plus correct offered results / `B`. Pair these with precision so abstaining everywhere cannot appear to win.                                                                                                                                                  |
| Subject/uncertainty behavior             | Separate subject-class confusion from named/unresolved resolution. Report false biological assertions and unsupported specificity. Only a valid normalized domain outcome can count as appropriate uncertainty; refusal or execution failure cannot. Synthetic human-policy checks remain separate. |
| Confident errors                         | Wrong named results at the current profile's Strong threshold across `N` / `N`, and / all Strong named results across `N`. Also report the diagnostic-band subset and each denominator.                                                                                                             |
| Confidence reliability                   | Correct offered results / all named results in each interval defined above, with counts and mean reported score, split by profile. No threshold tuning or claim that a self-reported score is a calibrated probability.                                                                             |
| Operational outcomes                     | Separate refusal, invalid output, operational failure, unknown execution, local validation failure, and unattempted cases. Never discard errors from the report to improve quality.                                                                                                                 |
| Time                                     | p50/p95 for completed provider executions, successful identifications, and local normalization separately, with counts, timeouts, and failure duration. These are not full app latency and success-only timing can be biased.                                                                       |
| Cost                                     | Estimated total and per attempted call, plus cost per correct offered result. Include paid failures/repeats in spend; separate stages. Missing billable usage produces an explicit unknown component/lower bound, never zero cost.                                                                  |

Use the canonical `thresholds.ts` values and the resolved profile. Reported
score versus observed correctness can reveal overconfidence; it does not
establish calibration automatically. The
[scikit-learn calibration guide](https://scikit-learn.org/stable/modules/calibration.html)
describes bin-based reliability measurement; this plan uses the diagnostic idea
without treating Gemini's score as a trained classifier's probability.

Report counts by input group and profile first; biological/difficulty slices are
secondary and may be sparse. Mark a balanced-corpus aggregate explicitly.
Compute 95% intervals for proportions and paired differences using a reviewed
method with observation groups as the independent units; freeze the
implementation, resampling seed, and method version. Repeats assess stability,
not additional sample size. Forty held-out groups per input cannot establish
fine differences reliably; no minimum detectable improvement is claimed here.

Score every predeclared held-out case. Partial runs are incomplete, not passing
comparisons. Quarantine reference disputes before a run. A later discovered
label error requires a versioned correction and consistent rescoring of all
profiles, retaining the original report; never selectively remove a model's
failures. Missing usage can coexist with quality results but blocks a definitive
cost comparison.

## 6. Comparison and decision contract

The comparison tool first checks corpus/split, task/input scope, dispatch-order
seed, frozen taxonomy digest and selection eligibility, scorer/taxonomy,
preparation, and measurement-boundary compatibility. Reject different evidence,
missing required cases, unexplained model/source changes, or incompatible
scoring versions. A declared candidate profile may intentionally change
model/provider, prompt, or confidence interpretation; record all such
differences and compare complete assignments, not a misleading claim that only
the vendor changed.

For a real future candidate, qualify every assigned input combination, retain
the complete included evidence, and run a contemporaneous Gemini reference when
the old baseline is stale. Compare the same groups with paired analysis. A
photo-only candidate cannot qualify audio, and native-video results cannot
qualify the sampled-frame path.

The report includes a decision specification: required input groups; maximum
quality, coverage, confident-error and failure regressions; desired cost/latency
benefit; interval method; and safety/subject-policy vetoes. Product and Backend
set numerical limits after reviewing the baseline but before any candidate
results. Until filled, the report verdict is `measurement_only`. Incompatible,
incomplete, or statistically inconclusive evidence cannot yield `qualified`.
Synthetic comparisons prove these verdict rules in Slice 5.

The baseline may complete while exposing weaknesses. Record those weaknesses and
recommend one next experiment. A future `qualified` verdict is evaluation
evidence only: actual processor permission, admission, accounting, consumer
compatibility, and authorized deployment still follow provider onboarding.

## 7. Implementation sequence and verification

Slice 1 is **implemented locally**: versioned corpus/prediction/report
contracts, strict record validation, evidence projection/fingerprints, pure
point scoring, and twelve synthetic cases. The
[tooling guide](../../services/supabase/scripts/identification_evaluation/README.md)
owns the delivered contract, hand-worked results, curation rubric, and current
limits. At that Slice 1 checkpoint, no real corpus or live evaluation existed.

Slice 1 local verification on 22 September 2026: all 24 evaluation tests and 29
subchecks passed in the complete `make test-supabase-tooling` gate (336 standard
tests, plus the existing isolated DTO suites of 19 and 20 tests and shell
checks). The gate type-checked its complete imported tooling graph. Recursive
functions/scripts formatting and lint passed, as did changed-Markdown formatting
and the evaluation documents' local links. Review corrections covered WebP and
single-MIME fidelity, cross-input description leakage, indeterminate-subject
scoring, and aggregate labeling. At that checkpoint no deployed Function source
changed; hosted candidate CI, full database/runtime tests, and live biological
evaluation were not run for this tooling-only slice.

Slice 2 is **implemented locally**. Production and evaluation share one pure
normalizer; the handler retains admission, outcome/error handling, diagnostic
logging, hydration, final wire validation, and persistence. Ten direct tests
cover both tiers and all six input forms, candidate boundaries, names/pets,
processed materials, audio states, context, immutable inputs, and strict parsing
before legacy sanitizers. Three evaluation bridge tests run without runtime
permissions. Older tests of copied normalization logic were removed. The
expanded actual-handler suite has 27 steps, including hydration and invalid
final-envelope behavior. Before/after checks passed against the original handler
and its captured normalization block as well as the extracted code. This is
synthetic local parity evidence, not live accuracy or deployment evidence.

Slice 2 local gates on 22 September 2026 passed: 37 focused
evaluation/normalizer tests plus 29 steps with network/environment/filesystem
access denied; the full tooling gate's 339 tests plus 29 steps, isolated DTO
suites (19 and 20), and shell checks; all 101 isolated Edge entrypoint type
checks; and configuration/import validation for 101 functions and 365 runtime
files. Recursive formatting/lint, changed-Markdown formatting, local
evaluation-document links, and diff whitespace checks passed. No public DTO or
SQL changed.

A fresh temporary Supabase project replayed the current migrations with the
pinned CLI. Its 52 catalog fixtures passed 388 assertions; the complete Edge
task passed 2,050 tests and 195 steps with zero failures or database skips. The
task used an explicit temporary loopback DB and denied the usual port 54322
database destinations, preserving the existing local stacks. Database lint found
no schema errors; security/performance advisor error gates passed with the
existing 105 security and 80 performance warnings, not fixes to those warnings.
The temporary project's containers and volumes were removed and their absence
verified; the existing local stacks remained running. Hosted exact-SHA candidate
CI, deployment, device verification of this extraction, and paid identification
evaluation were not run. The real corpus remains at 0/60 development and 0/240
held-out groups.

Slice 3 is **implemented locally**. The scripts-only runner preflights every
asset, freezes requests/settings/source, persists and flushes claims before
sequential dispatch, and resumes only never-started attempts. It saves bounded
normalized records, regenerates reports without inference, and rejects
incompatible/incomplete comparisons. Wilson 95% proportions and paired group
bootstrap differences use the frozen method and seed in `reports.ts`; all
verdicts remain `measurement_only`. Synthetic fixtures and crash/cross-process
lock tests supply local mechanics evidence, not biological quality or live cost.

Prepared image checks cover container structure, metadata, hashes and bounds,
not full pixel decoding; curation must decode and review the final images.
Prepared WAV is constrained to metadata-free PCM16 mono/stereo at 8–96 kHz
before the production parser/trimmer/resampler runs. The adapter cannot separate
actual timeout causes from other unknown executions, so reports retain unknown
counts and observed durations without inventing timeout classifications.

Slice 3 local verification on 22 September 2026 passed the complete tooling
gate: 347 standard tests plus 29 steps, seven isolated evaluator tests plus four
crash steps, the isolated DTO suites (19 and 20), and all shell checks. All 101
Edge entrypoints passed isolated type checks; config/import validation covered
101 functions and 366 runtime files. The complete Edge suite passed 2,051 tests
and 195 steps against a fresh disposable database after replaying the
migrations, with no database skips. The new request-projection owner retained
the existing SDK parameter/single-invocation and actual-handler checks.
Recursive formatting and lint, changed-Markdown formatting and diff checks
passed. The offline CLI demo and report regeneration succeeded with
network/environment denied and no credential. Independent contract review
findings were resolved; the disposable database and its volumes were removed.
Hosted exact-SHA CI, deployment, real corpus collection and paid evaluation
remain pending. Real coverage remains 0/60 development and 0/240 held-out
groups.

Slice 4 **collection preparation is ready** on 22 September 2026. The
[pilot collection guide](../development-guides/20-identification-evaluation-pilot.md)
provides proposed coverage for 60 independent development groups and blank case
and independent-review forms. Pending forms are not executable corpus records;
they remain outside the admission contract until real eligibility and reference
reviews are complete. No observations, reviews, corpus approval or paid-run
authorization are supplied by these templates. Real progress remains 0/60
development and 0/240 held-out groups. Source material and two independent
reference reviewers are the next dependencies. No runtime or schema changes are
part of this preparation.

Owner clarification on 22 September: independent reference reviewers are not
currently available. The
[solo workflow](../development-guides/20-identification-evaluation-pilot.md#start-here-when-you-are-working-alone)
documents six to twelve manual app checks and purpose-collected source intake
with one owner's provisional assessments. This is a development aid, not an
approved corpus or Slice 4 measurement. App submit-to-result timing must remain
separate from evaluator execution timing and cost. At that documentation-only
checkpoint, the executable corpus still required two independent reviewer
references and ten development cases per input group. The subsequent automated
exploratory mode below adds a separate development route; those formal
reference-corpus requirements remain unchanged.

Automated exploratory testing was added locally on 22 September at the owner's
request. `identification_exploratory_corpus_v1` is distinct from the formal
corpus: one to twelve unique development groups, `evidenceOrigin: real` or
`synthetic`, and a nullable `provisionalReference` per case. Real records
require an eligibility record, retention date, explicit owner/automated reviewer
kind, source/permission evidence, and completed rights, privacy and
near-duplicate checks. These are eligibility assertions, not verified reference
labels. Synthetic records cannot supply real eligibility or enter live
execution.

`identification_exploratory_run_spec_v1` requires `stage: exploratory`, one
repeat, all corpus groups and at most twenty-four calls. Live execution uses
both existing Gemini profiles once per group and the existing reviewed-key,
processor-readiness, pricing, bounded-budget, immutable-source and durable-claim
controls. No second provider or deployed runtime behavior changes. The original
formal corpus version, two-reviewer rule, full coverage gates and scorer remain
unchanged; neither formal reports nor formal comparisons accept exploratory
corpora.

`preflight DIRECTORY` verifies prepared assets, taxonomy and native request
fingerprints without network, environment access, a credential or dispatch
claims. It writes `preflight.json` with coverage, planned calls and, when
current pricing is supplied, conservative reservations.
`dispatchAuthorized: false` makes clear that preparation is not paid-run
authorization. `demo-exploratory` runs the separate contract against invented
media/outcomes with network and environment denied. The ordinary `report`
command regenerates the corresponding exploratory report without inference.

`identification_exploratory_report_v1` records operational outcomes for every
scheduled case, but provisional agreement only for non-null references. A null
reference does not mean a known non-biological subject or expected abstention.
Reports show untested groups, provisional/unverified counts, zero independently
reviewed labels, and `verdict: measurement_only`. Formal correctness, confidence
calibration claims and provider qualification are outside this report. Provider
time and usage estimates are meaningful only for actual live calls; synthetic
reports explicitly record mechanics-only evidence. Local verification and run
artifacts are recorded in the
[exploratory experiment record](./identification-exploratory-benchmark-2026-09-22.md).
No paid direct-evaluator run has occurred. A subsequent
[production-app checkpoint](./identification-production-app-benchmark-2026-09-22.md)
completed two owner-approved photo submissions through the ordinary production
workflow, recording first visible results and client timing. Its separate
`identification_production_app_benchmark_v1` evidence is an app observation
record, not a runner report or reviewed corpus. Exact model, provider timing,
cost and source revision remain unmeasured; installed code-file hashes are
retained. One provisional and one unverified reference do not advance the formal
0/60 development or 0/240 held-out counts, and no provider comparison was run.

Slice 4 measurement and Slice 5 remain **planned**, with the primary implementer
owning writes. Reconcile paths with the then-current merged source before each
slice; keep unrelated folder organization separate.

The subsequent
[app measurement slice](../development-guides/21-identification-app-measurement.md)
adds a bounded fresh-response header and native/observer projections for actual
model, source identity, provider/Edge timing and nullable usage. Optional
offline cost reuses the evaluator's pricing contract and conservative estimator,
scoped to the observed primary attempt. Local instrumentation does not complete
Slice 4, attest a hosted deployment or revise the first app checkpoint's missing
values.

The subsequent
[timing verification](./identification-timing-capture-verification-2026-09-22.md)
records successful bounded observer shutdown and provider/Edge timing on one
live repeat, while retaining missing spans on the other. The
[six-photo preparation](./identification-source-photo-pilot-2026-09-22.md) then
used the existing exploratory contracts without runtime changes: six independent
development photo groups, five provisional species references and one
non-biological unresolved control. Offline preflight passed with network and
environment denied, preparing twelve requests for the two current profiles with
`dispatchAuthorized: false`. The preferred app plan is a separate six-submission
ordinary-app pass, not the direct evaluator's dry schedule. References and
source records remain outside input projections and Git. Preparation made no
model calls, and formal reviewed counts remain 0/60 and 0/240.

The subsequent
[six-photo app benchmark](./identification-source-photo-app-benchmark-2026-09-22.md)
completed six sequential first submissions on the installed timing-fix build.
Each passive window retained seven events, fresh Gemini 2.5 Pro diagnostics and
valid provider/Edge timing, then closed normally. Five provisional species
agreements and one non-biological agreement remain separate from formal scores.
Its selected UI outcomes and bounded numeric records are app-observation
evidence, not direct-runner output; no new runtime code or deployment was
needed.

The subsequent
[two-description benchmark](./identification-description-app-benchmark-2026-09-22.md)
used a separately frozen two-group exploratory corpus. Offline preflight
prepared four requests without dispatch; the ordinary app submitted each
description once. Both windows closed with five events, fresh Gemini 2.5 Pro
diagnostics and valid provider/Edge spans. The mushroom answer agreed at genus
level but exceeded the reference's specificity; the ambiguous
non-biological-source description returned a Strong biological answer. Neither
is independent accuracy evidence. That build's nonvisual path emitted no visual
preflight marker and omitted the immediate Describe clock needed for
first-render timing. Both missing fields remain null in the frozen report.
Audio/video capture was live-only, and the passive observer was simulator-only;
no controlled audio/video cases ran.

The subsequent native implementation forwards the immediate Describe clock and
adds a Debug simulator-only local replay input under `Capture/Scan/Debug`. Fixed
inbox files are copied and validated against normal recording limits, then
prepared with the existing WAV and five-frame video services. Replay requires a
complete frame set and audio when the source contains it; stale, cancelled and
failed work cleans owned artifacts. Accepted evidence enters ordinary staging
with automatic submission disabled. The manual Identify action still owns
consent, entitlement/admission, durable queueing and the unchanged Gemini route.
The feature adds no DTO, schema, provider adapter, release activation or live CI
request. The
[app measurement guide](../development-guides/21-identification-app-measurement.md#controlled-audio-and-video-replay-in-the-simulator)
owns activation and measurement limits. The
[controlled replay benchmark](./identification-replay-app-benchmark-2026-09-22.md)
subsequently verified the new Describe first-render marker on one repeat and
recorded a first video result. Their non-overlapping windows closed normally
with six and seven events, respectively, fresh Gemini 2.5 Pro diagnostics and
valid provider/Edge spans. The video retains five snapshots and companion audio,
but its decoded audio samples are all zero; it does not establish useful audio
fusion. Offline preflight passed for that single grouped observation with no
dispatch. Source/review asset hashes do not attest the app's final payload or
context. At that checkpoint, standalone audio still awaited listening review.

The owner subsequently completed the listening review, and the
[first audio benchmark](./identification-audio-app-benchmark-2026-09-22.md) used
a new frozen packet for the final allowed app submission. Offline preflight
passed one audio group without dispatch. The ordinary-app window completed with
six events, 19.022 seconds to first rendered frame and unchanged app/backend/
Gemini 2.5 Pro identity. Wood Thrush with a Strong match disagreed with the
source's provisional Northern Cardinal label. Neither privacy review nor
successful transport establishes species correctness; independent reference
review remains open. Earlier JSON packets, formal counts and direct-evaluator
controls are unchanged.

The
[audio reference review](./identification-audio-reference-review-2026-09-22.md)
subsequently verified both prior private freezes and reproduced the staged PCM
exactly from the original source. A separately frozen BirdNET-Analyzer 2.4.0 /
model V2.4 diagnostic ran once locally with networking denied, all 6,522 classes
and four retained windows. Pyrrhuloxia ranked first in the three complete
windows; the padded tail favored Pacific Antwren. The source/Gemini/BirdNET
disagreement leaves species identity unresolved. This is diagnostic evidence
outside the shared evaluator, with no provider adapter, runtime dependency, paid
request, biological-reference promotion or change to formal denominators. The
original app request/context was not retained and remains unattested.

The
[six-audio preparation](./identification-audio-six-preparation-2026-09-22.md)
preserves a frozen checkpoint before owner listening review. Following that
review, a new admitted corpus passed canonical preflight for six audio groups
and twelve in-memory profile requests, with no dispatch. The
[six-audio app benchmark](./identification-audio-six-app-benchmark-2026-09-22.md)
records six sequential first submissions with normal Gemini 2.5 Pro selection
and no manual retries. All three animal results were Strong matches that
disagreed with provisional source species; all three source/owner-reviewed
non-biological controls returned No wildlife detected. Earlier results and
formal denominators remain unchanged.

The
[audio-path verification](./identification-audio-path-verification-2026-09-22.md)
completed that local trace. Native synthetic tests preserve PCM samples through
Core Audio preparation, simulator replay, file persistence and intercepted live
request serialization. The handler test verifies the exact processed WAV at the
adapter boundary; existing SDK interception covers the native request. Offline
processing of all six frozen inputs records actual trimming and 16 kHz
conversion. A synthetic 12 kHz tone aliases strongly to 4 kHz in the previous
linear downsampler. The
[audio preprocessing fix](./identification-audio-preprocessing-fix-2026-09-23.md)
replaces it with bounded Blackman-windowed sinc resampling and measures the
final partial silence window. Output remains 16 kHz mono PCM16. Both handlers
map processing-budget overflow to `413 payload_too_large` before provider
admission; the existing sparse-video fallback remains covered. Local signal,
handler, full-backend and disposable-database checks pass. Six frozen clips have
new offline measurements; historical evidence remains immutable. Prompts,
confidence and provider assignment are unchanged. The subsequent
[production deployment](../release-evidence/identification-audio-preprocessing-deployment-2026-09-23.md)
passed exact-SHA hosted candidate validation, deployment and automated smoke and
health checks. No new paid identification was submitted. A fixed-context
same-Gemini comparison remains ahead; no species-accuracy benefit is claimed.

These tests do not attest historical live request bytes or private contextual
fields. Replay retains ordinary location/time context when available, a
potential confound for source recordings made elsewhere. Future comparisons must
fix the context policy as well as media and model configuration. The
[fixed-context replay slice](./identification-fixed-context-replay-2026-09-23.md)
implements a Debug simulator-only, request-local `audio-minimal-v1` profile for
one staged audio clip. The profile is part of the admission snapshot and
foreground telemetry; it omits live capture telemetry before durable enqueue and
cancels/ignores stale prefetch instead of starting deferred enrichment. The
normal request builder emits fixed English/UTC/January/noon context through the
existing fields. Normal capture, device/Release behavior, authentication,
admission, provider assignment and recovery remain unchanged. The
[measurement guide](../development-guides/21-identification-app-measurement.md#fixed-context-for-foreground-audio-comparisons)
owns the exact profile and activation contract.

Queue storage does not persist the Debug profile. Offline, interrupted, failed
or recovered attempts remain excluded, including a fresh provider result from
background recovery. Historical measurement-v1 records do not attest to the
request profile. The
[provenance preparation slice](./identification-audio-comparison-provenance-2026-09-23.md)
adds v2 profile-only attestation for a validated final request body, active
foreground owner and initial fresh HTTP response. The strict observer retains v1
compatibility and both versions' cost projection. Its new profile check requires
complete app identity, reviewed backend fingerprint and exact model; it does not
associate the result with a case/media hash or prove a completed UI outcome.

Tooling-only `audio-linear-full-windows-v1` and `audio-sinc-partial-tail-v1`
arms prepare the six frozen standalone clips with identical `audio-minimal-v1`
context, Gemini Pro prompt/schema/generation and confidence settings.
Preparation freezes source/processed/request hashes and a 12-assignment order
alternating which arm runs first. The legacy DSP lives only under scripts; the
current arm invokes the deployed route's shared helper. No production selector
or live dispatch was added. Existing evaluator RunSpecs cannot execute these
preparation artifacts. Before the proposed paired run, implement controlled
server-owned arm assignment and case/media/outcome binding through the ordinary
authenticated production route, preserving existing admission, accounting and
release controls. An explicitly selected direct evaluator lane would require its
own existing readiness/budget contracts and would measure a different execution
path. No new paid identification, accuracy claim or formal benchmark result is
added here.

The subsequent
[server assignment slice](./identification-audio-comparison-assignment-2026-09-23.md)
implements the backend portion locally and leaves it disabled. A generated fixed
12-slot table binds the immutable preparation's
source/processed/request/settings hashes. Private owner/bundle/window
configuration gates an optional handle and stable reserved scan UUID. Normal
quota admission remains authoritative; reopened attempts refund and stop before
ingestion, and service replay cannot bypass the gate. Fresh durable success
alone carries a bounded comparison proof header. The legacy processor now has a
route-private owner shared with offline tooling. The subsequent
[app integration](./identification-audio-comparison-app-integration-2026-09-23.md)
adds generated native slots, exact source/queue binding, authenticated receipt
collection, typed persistence outcome and exact UIKit first-draw proof. Its
offline gate joins those records to one complete observation-v2 window with the
reviewed app/backend identity; it rejects replay, interruption, missing proof
and legacy evidence. Configuration stays unset and no paired experiment has run.
It records confidence/biological status without species prose, so it does not
score reference agreement or increase the formal qualification counts.

The subsequent reusable
[experiment control](../backend-and-data/06-supabase-deployment-runbook.md#audio-comparison-activation-hold)
adds protected GitHub inspection, activation and deactivation without changing
the runtime or executing identifications. Infrastructure remains installed;
individual runs use the exact reviewed account/plan/bundle and a window of at
most two hours. Expiry makes a stored setting inactive. The control cannot reset
the twelve assignments, widen the corpus, or establish a paired result; fresh
plans still require reviewed generated bindings and ordinary benchmark evidence.

| Slice                     | Implementation and verification                                                                                                                                                                                                                                                                                                                                                                                                                        |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1. Contracts and examples | Add schemas, eligibility/split validation, curation rubric, report contract, and synthetic cases with hand-worked expected metrics. Prove ground-truth isolation, complete ordered frame/audio evidence, unsupported-specificity scoring, strong false biological answers on negatives/unresolved cases, zero denominators, and rejection of cross-split duplicate groups. Start curation outside Git.                                                 |
| 2. Production normalizer  | Extract existing logic without changing semantics. Exercise both profiles and all input forms against existing handler fixtures, including malformed drafts, names/pets, processed material, acoustic precedence, candidate boundaries, and refusal/failure handling. Prove the helper has no I/O; preserve final hydrated wire validation and admission/replay contracts.                                                                             |
| 3. Runner and reports     | Add offline execution, deterministic scoring, normalized artifacts, comparison compatibility checks, and explicit live mode. Test denied network/defaults, import safety, call/spend guards, missing usage, racing run processes, durable-claim crash boundaries/resume, processor-readiness mismatch, SDK single invocation, and no raw output logging. Update the deliberate dispatch/guard inventory in `_tests/aiQuotaCoverage.test.ts` as needed. |
| 4. Reviewed baseline      | Approve the development corpus and bounded pilot specification, then explicitly request that paid run. Fix measurement defects on development cases. Freeze rules and independently reviewed held-out cases before their separately requested run; retain complete counts and sanitized evidence.                                                                                                                                                      |
| 5. Decision readiness     | Test reports with intentionally better, worse, abstaining, incomplete, incompatible, and inconclusive synthetic candidates. Publish the Gemini baseline internally, its limits, comparison procedure, and prioritized follow-up. No second live adapter is required.                                                                                                                                                                                   |

During implementation run the narrow relevant fixtures first, then the complete
affected-surface gates in the
[testing strategy](../development-guides/08-testing-strategy.md): recursive Edge
type checks and tests, complete Supabase tooling checks, DTO parity for the
runtime extraction, and the disposable-database candidate gate when backend
runtime changes are submitted. Ordinary CI never receives a paid evaluation key
or automatically calls Gemini. Keep synthetic network-intercepted tests distinct
from the measured live corpus.

Markdown changes require `deno fmt` and `make validate-markdown-format`. Changes
under functions/scripts also require
`deno fmt --check services/supabase/functions services/supabase/scripts`. No
SQL, wire changes, or generated Swift changes are intended; any discovered need
for them must be scoped and reviewed under their owning contracts.

Completion requires the PRD deliverables and an auditable report, not a new live
provider. Corpus approval, reference-review capacity, and a concrete paid-run
budget are dependencies for Slice 4; they do not block implementing and testing
Slices 1–3 offline. This planning change authorizes no paid run, deployment,
production data export, or external publication.
