# Identification evaluation tooling

## OpenAI confidence assessment

`../assess_openai_confidence.ts` owns the separate
`identification_openai_confidence_assessment_v1` report. Follow the
[frozen study contract](../../../../docs/rfcs/identification-openai-confidence-assessment-2026-09-30.md)
for reference, rank, category, outcome, denominator and decision rules. It uses
the revised production-equivalent `openai_identify_vision_confidence_v1`
request; the historical evaluator below keeps its original builders and disabled
OpenAI confidence metrics. Production now selects the same revised request under
its existing `openai_photo_v1` authority; the assessment binding remains
excluded from production. All 200 frozen request/settings digests were checked
offline before activation; no further provider calls or study changes were made.
See the
[activation record](../../../../docs/release-evidence/openai-confidence-activation-2026-09-30.md).

Prepare one private directory outside Git containing `confidence-corpus.json`,
`taxonomy.json`, `pricing.json`, `confidence-evidence.json` and the approved
media under `assets/`. Use `openai_confidence_corpus_v2` with `kind: reference`,
`splitSeed: 20260930`, `referenceStatus: valid`, the matching reviewed taxonomy
version and exactly 200 cases. Each case contains the existing photo-only
`input` (empty description texts, frozen region/month), evidence-supported
`reference`, exclusive `category`, `taxaGroup` and reviewed `curation`. Curation
has `permission: openai_evaluation`, distinct opaque `sourceRecordRef`,
`referenceRecordRef`, `answerabilityRecordRef`, one to eight distinct
`independentEvidenceRefs`, `reviewMethod: source_grounded_visibility_v1`, an
honest `reviewerRef`, `independentHumanValidation: false`, and true
`rightsApproved`, `personalDataExcluded`, `nearDuplicatesReviewed`,
`referenceVerified`. `developmentOnly` is a required boolean; set it true for
previously supplied plant examples. Model output or a user confirmation alone
cannot populate verified references. This confidence-specific source-supported
review does not require the separate historical baseline's two human reviewers.
Corpus v1 is rejected instead of being silently reinterpreted.

Keep the actual review records in the private packet. The source record retains
asset-level rights and source revisions; the reference record contains
independent identity support; the answerability record binds the final image
hashes to visible supporting traits, missing diagnostics and the predeclared
rank. The automated reviewer must inspect the final pixels against those sources
before collection. Source labels, a model's judgment or an unverified user
confirmation alone do not establish a supported reference. Candidate intake
records with pending checks cannot be converted to verified curation merely to
fill the quotas. The report explicitly names the automated review method and
does not claim independent human validation.

`confidence-evidence.json` has `version: openai_confidence_evidence_v1` and a
`records` array. Each record has exactly `id`, `kind`, `reviewerRef`, `caseId`,
`assetDigests`, `reference`, `relatedRefs`, `sourceUrls`, `sourceRevisionRefs`
and `findings`. IDs are opaque tokens. Findings are bounded reviewed facts, not
raw source pages, provider responses or personal data. Public source URLs use
HTTPS; revision references identify the reviewed source revision or content
hash.

Each case has three distinct records with matching case ID, final asset hashes
and curation reviewer. A `source` record has null `reference`, no related
references and at least one source revision reference; its findings record
rights and source provenance. A `reference` record repeats the exact predeclared
reference and links its source record plus all independent evidence records. An
`answerability` record also repeats the reference, links the
source/reference/independent records, and records visible traits and missing
diagnostics. Each `independent` record has null case/reference, empty
asset/related-reference arrays, and at least one public source URL and revision
reference. It may support several cases. Missing, duplicate, unlinked,
wrong-case or mismatched records fail preparation. This structural check does
not replace the actual scientific review.

Use `evaluation_taxonomy_v2` with reviewed canonical IDs, ranks and unambiguous
synonyms. Ambiguous/unknown returned names remain named, unmapped outcomes with
no inferred rank. Use the existing `evaluation_openai_pricing_v1` contract with
reviewed current synchronous prices and input/output ceilings including
reasoning tokens. Paid dispatch rejects future-dated prices and prices reviewed
more than seven days ago, using the existing evaluator's freshness convention.
Reporting remains available after price expiry. Synthetic fixture prices and
labels are never live readiness evidence.

From the repository root, set `study_dir` to that private directory. Offline
commands have network/environment denied and fingerprint the source with Git:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$study_dir" --allow-write="$study_dir" --allow-run=git \
  services/supabase/scripts/assess_openai_confidence.ts assign-splits "$study_dir"

deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$study_dir" --allow-write="$study_dir" --allow-run=git \
  services/supabase/scripts/assess_openai_confidence.ts prepare "$study_dir"
```

`assign-splits` applies the deterministic grouped allocation and exact category/
rank quotas before freezing. It refuses an existing manifest/journal. `prepare`
verifies every media byte and freezes `confidence-manifest.json` as
`openai_confidence_manifest_v2`, including request/settings, corpus, taxonomy,
protocol, pricing, implementation-source and actual review-record content
hashes. It produces a non-dispatching readiness file and report; preparation is
not a paid run. Replace `prepare` with `report` to reconstruct the report
without requests. Changed files/source fail frozen resume rather than resetting
either budget. The full evidence bundle is rechecked before every dispatch;
changing facts behind an unchanged record ID also stops collection. Reports
expose only the `referenceEvidence` hash, not the private review prose. Existing
account/key admission is unchanged; no new processor approval or human-review
step is added.

After the corpus is independently reviewed and the bounded collection is ready,
the explicit `--live` command uses only `OPENAI_EVALUATION_API_KEY` and
`api.openai.com:443`. Supply the existing key through the established
hidden-input or scoped-secret process; never put it in a command, file, chat or
artifact:

```bash
deno run --frozen --no-prompt \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$study_dir" --allow-write="$study_dir" --allow-run=git \
  --allow-net=api.openai.com:443 --allow-env=OPENAI_EVALUATION_API_KEY \
  --deny-env='SUPABASE_*,R2_*,GOOGLE_*,GEMINI_*,WS_*,OPENAI_API_KEY' \
  services/supabase/scripts/assess_openai_confidence.ts --live "$study_dir"
```

The explicit environment denials are required by credential admission;
`--no-prompt` alone leaves ungranted variables in the `prompt` state. The
documented grants/denials passed a synthetic-key admission check without a
network request.

Both splits share one journal, 200 attempted requests and an initial $10
ceiling. The explicit owner-approved $20 continuation below is cumulative. No
automatic retries or replacement cases exist. Before invocation, exclusive
fsynced claims in `confidence-attempts/` reserve conservative cost including
maximum reasoning output. The next reservation must fit alongside settled and
outstanding costs. Required missing/contradictory usage, unexpected returned
model/tier, failed or uncertain execution retains cost and stops. Mismatched
model/tier drafts receive no scored identification even if billing is later
reconciled. Resume skips every claim, including uncertain calls. Do not delete
claims, copy to a fresh run to reset budgets or alter the manifest.

`openai_confidence_result_v2` adds bounded numeric accounting evidence. It keeps
optional missing cache-write counts null and accepts valid positive counts,
while charging all input at the maximum reviewed rate. Explicit contradictory
cache writes fail in the confidence-only decoder before an absent count could
mask them. Required input/output/reasoning/cached/total counts and
tool/model/tier checks remain enforced. The ledger recomputes v2 settlement from
these facts and continues accepting original v1 records; neither version retains
model prose, raw responses or request identifiers.

After an owner-approved accounting repair and genuine billing reconciliation,
the offline command below may create one exclusive continuation. Set
`manifest_digest` to the original frozen manifest digest and use opaque
`authorization_ref`/`review_ref` values identifying the actual owner decision
and source review:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$study_dir" --allow-write="$study_dir" --allow-run=git \
  services/supabase/scripts/assess_openai_confidence.ts prepare-continuation \
  "$study_dir" "$manifest_digest" "$authorization_ref" "$review_ref"
```

This writes `confidence-continuation.json` with
`version: openai_confidence_continuation_v1`, the original manifest/source,
replacement `SourceIdentity`, approval/review references,
`budgetKind:
cumulative_total`, fixed `budgetNanoUsd: 20000000000`,
`maxAttempts: 200`, the reconciled prefix's attempted/settled/outstanding counts
and exact-file digest, and `nextOrdinal`. It refuses unreconciled predecessors,
altered study inputs, wrong manifest identity and an existing continuation.
Requests retain their original digest, settings, order and per-case reservation.
The same `--live` command then starts at the next original case and enforces
cumulative accounting. Source or prefix drift fails; never delete the amendment
to reset an attempt. Original protocol/manifest files stay immutable. Reports
add `continuation` and `executionSource` hashes while preserving the original
`source` hash.

`confidence-selection.json` immutably records the lowest qualifying development
cutoff, its hash and development-result hash before any held-out request. No
candidate stops collection at 100 attempts and retains 0.95. Incomplete or
failed validation also retains 0.95, without searching held-out results for
another threshold. `confidence-report.json` includes fixed raw-score bins,
Wilson intervals, scheduled denominators, category/rank breakdowns, all outcome
classes, budget completeness and hashes. Synthetic tests can pass the mechanics
rule but cannot recommend a live threshold.

When genuine provider billing evidence resolves an outstanding attempt, retain a
private immutable `<caseId>.reconciliation.json` next to its claim, with exactly
`version: openai_confidence_reconciliation_v1`, the claim's `claimDigest`,
opaque `billingEvidenceRef` and `reviewRef`, and integer `settledNanoUsd` within
its reserved ceiling. It settles accounting only; the uncertain/failed
prediction and consumed request remain. No receipt is synthesized from missing
usage. A subsequently invalidated reference is recorded in
`confidence-invalidation.json` with
`version: openai_confidence_invalidation_v1`, `manifestDigest` and opaque
`reviewRef`; it stops dispatch and makes a threshold decision ineligible without
rewriting the frozen references.

Current readiness, September 30: the private 200-photo confidence reference
corpus is frozen and passed offline preparation, with 100 development and 100
held-out cases and all category/rank quotas satisfied. Its linked source,
reference, answerability and independent diagnostic evidence is frozen with the
requests. One identification completed, then the runner stopped for billing
reconciliation before a second call. The original artifact lacks numeric usage;
the accounting correction cannot reconstruct it or authorize replay. Reviewed
provider usage has now reconciled its upper cost at $0.03499, and the exclusive
$20 cumulative continuation resumed at ordinal 2. All 100 development attempts
are now complete (99 normalized, one invalid output), with $3.512790008
conservatively accounted and zero outstanding reservation. No cutoff met both
rules, so the runner recorded `no_development_cutoff` and left the 100 held-out
cases unattempted. The
[results record](../../../../docs/rfcs/identification-openai-confidence-results-2026-09-30.md)
reports the retained 0.95/0.60 fallback and its limits. The
[release record](../../../../docs/release-evidence/openai-confidence-assessment-2026-09-30.md)
retains the hashes. Synthetic tests and corpus readiness do not establish
calibration. The new reader keeps 0.95/0.60 following this fallback decision;
distribute and verify the final mapping on a device before separately authorized
backend activation.

The current conservative reservation is $5.37288 per sequential call, including
the full model-context and output ceilings at reviewed maximum rates. Successful
complete usage releases the unused reservation before the next call. The shared
200-request/effective-budget limits are ceilings, not a completion guarantee.
Insufficient headroom or unresolved usage stops dispatch without changing
settings, adding retries or expanding the budget.

Slices 1–3 of the
[PRD](../../../../docs/product/04-identification-evaluation-prd.md) and
[SRD](../../../../docs/rfcs/identification-evaluation-srd.md) are implemented
here as local, offline tooling. The production route and tooling reuse the same
pure normalization helper. No production function imports these scripts modules.
The CLI runs offline by default and has a separate, explicitly gated live mode.
The historical multi-provider baseline has no formal reviewed corpus. The
September 25
[OpenAI photo/text pilot](../../../../docs/rfcs/identification-openai-photo-text-pilot-2026-09-25.md)
completed seven paid direct-evaluator results and retained one unknown execution
across eight unique attempted cases. Its provisional references do not establish
formal accuracy or provider qualification. The earlier two-photo exploratory
corpus passed local preflight; its
[experiment record](../../../../docs/rfcs/identification-exploratory-benchmark-2026-09-22.md)
retains scope and limits. A subsequent
[six-photo source packet](../../../../docs/rfcs/identification-source-photo-pilot-2026-09-22.md)
also passed offline preflight with provisional references and no model calls.
Its completed
[six-photo app benchmark](../../../../docs/rfcs/identification-source-photo-app-benchmark-2026-09-22.md)
records ordinary-app outcomes and passive measurements separately from the
direct evaluator's dry schedule. At that September 22 checkpoint, Gemini was the
only production provider. The later beta OpenAI photo binding is described
below. Video evidence is ordered snapshots and included WAV audio, never a
playback video.

Checkpoint, 27 September 2026: the
[matched Gemini/OpenAI comparison](../../../../docs/rfcs/identification-gemini-openai-matched-results-2026-09-27.md)
completed all sixteen scheduled attempts. The
[current optimization plan](../../../../docs/rfcs/identification-optimization-preserving-results-2026-09-27.md)
preserves explanation format and detail and starts with existing measurements.
The earlier concise screen remains closed; the commands and profiles below
remain executable contracts, not instructions to restart it or spend its unused
allocation. Formal reviewed-corpus counts and qualification requirements are
unchanged.

Current direction, 29 September 2026: finish OpenAI optimization before
calibrating confidence for the selected configuration. The new
[observed-traits candidate](../../../../docs/rfcs/identification-openai-observed-traits-candidate-2026-09-29.md)
retains a pure offline evaluation identity that none of this directory's runners
admits. Its two trait directions are now integrated into the production photo
prompt with separate production provenance and native reader support. Existing
Sol controls retain the original request and hashes rather than following the
new production instructions. Explanation format stays unchanged. The owner chose
targeted regression checks and ordinary beta smoke scans for this narrow wording
change, followed by confidence calibration on the final configuration. No new
comparison controller or paired run is planned. Normal release controls still
apply; completed experiments and budgets remain closed.

The
[retained-evidence audit](../../../../docs/rfcs/identification-openai-confidence-evidence-audit-2026-09-29.md)
verified eighteen compatible controls but only six distinct photos, with no
Strong-band biological result and no assessable Weak identity result. Retain
provisional display cutoffs; calibration collection resumes after configuration
selection. Changed-prompt results cannot be pooled with unchanged-profile
scores.

The later
[description app benchmark](../../../../docs/rfcs/identification-description-app-benchmark-2026-09-22.md)
adds two source-derived descriptions, one provisional genus agreement and one
biological assertion on an ambiguous non-biological-source description. Offline
preflight prepared four requests without dispatch; the separate ordinary-app
pass retained two complete five-event windows. Missing Describe timing markers
remain null in that run; its app build had no controlled audio/video import
route. No formal counts or direct-evaluator readiness gates changed.

The subsequent
[controlled replay app check](../../../../docs/rfcs/identification-replay-app-benchmark-2026-09-22.md)
verified Describe's first-render metric on a repeat and measured one first video
result through Debug simulator staging and normal manual Identify. Both windows
completed. The video packet passed offline preflight with five ordered snapshots
and its actual, digitally silent companion WAV. This does not establish useful
audio fusion. After the owner's listening review, the
[first audio app check](../../../../docs/rfcs/identification-audio-app-benchmark-2026-09-22.md)
completed one first submission and a six-event window. Its Wood Thrush Strong
match disagreed with the provisional Northern Cardinal source label. The new
single-group packet passed offline preflight without dispatch; earlier packets
remain frozen. At that September 22 checkpoint, the direct evaluator had no paid
run. The September 25 pilot above adds paid exploratory evidence; formal
reviewed-corpus counts remain unchanged.

## Alternative-provider comparison

The explicit `openai_gpt_6_sol` evaluation profile supports photos/text through
OpenAI Responses. The separate beta production photo binding uses OpenAI for
still photos and retains Gemini for other complete-input profiles. The
[provider guide](../../../../docs/development-guides/22-alternative-identification-provider.md)
owns the `demo-providers` command, new provider-run/pricing/readiness versions,
OpenAI-specific input permission, single-provider live runs and credential
scope. A reviewed Naturebook application project/key can also serve OpenAI
benchmarks; record `dedicatedEvaluationProject: false` and inject the key as
`OPENAI_EVALUATION_API_KEY`. The local
[`run_openai_evaluation.sh`](../run_openai_evaluation.sh) launcher supplies
hidden terminal key entry, an optional private credential fingerprint, and the
existing preflight/live commands without saving the key. Its procedure is in the
provider guide. Historical Gemini specifications, corpus permissions and audio
records remain unchanged. OpenAI raw confidence has no Gemini Strong/diagnostic
interpretation.

The manual **Compare identification providers** workflow can now use both
existing GitHub Production secrets with a reviewed public test bundle in the
existing `merian` R2 bucket. `hosted.ts`, `hostedStorage.ts`,
[`host_identification_comparison.ts`](../host_identification_comparison.ts) and
[`run_hosted_identification.sh`](../run_hosted_identification.sh) wrap this
controller without changing provider assignment or measurement. The
[hosted procedure](../../../../docs/development-guides/23-hosted-identification-comparison.md)
owns public export, exact-source validation, per-provider credential binding,
conditional remote claims, interruption behavior and summary publication. Source
implementation does not establish that a hosted comparison has run.

## Free/Pro photo-model preparation

`photoModelContracts.ts` and `photoModelPreparation.ts` own the separate
`photo_model_plan_v1` ($5 proposal), `photo_model_plan_v2` (up to $40 with
separate approval), `photo_model_facts_v1`, `photo_model_pricing_v1`, and
`photo_model_preflight_v1` contracts. The `preflight-free-pro-photo` CLI
validates 12 frozen no-description photo cases and prepares 12 Luna-low
assignments plus six production-equivalent Sol-low controls. It denies
network/environment access, checks contained media bytes, references, fact
cards, retention and explicit operator input scope, and emits content-free
digests and costs. It cannot create a live claim, dispatch a provider or change
production assignment.

The historical `Profile`, run-spec, pricing, experiment and fact-card contracts
stay unchanged. A new 12-card wrapper reuses individual card validation without
increasing the old eight-card limit. The
[provider guide](../../../../docs/development-guides/22-alternative-identification-provider.md#lunasol-photo-comparison-preparation)
owns packet fields, commands, the spending decision and private approval. The
real twelve-photo packet is prepared; no Luna quality result is claimed.

`photoModelAdmission.ts`, `photoModelRunner.ts` and `photoModelRecords.ts` own
separate versioned approval, immutable claims/results/reviews and the durable
state summary. The existing terminal launcher accepts `--photo-model-live` for
this controller. It reserves the entire 18-call schedule plus a regional premium
before the first call, requires a clean source and credential-bound approval,
and revalidates every dispatch. Six correct Luna screen outcomes with passing
assistant explanation ratings must precede challenge calls. Missing results,
missing reviews, unknown billing, refusal or technical failure stop the run;
restart cannot repeat a claim. A completed challenge run still requires an
assistant selection report and grants no production authority.

The existing one-use explanation view is shared through
`normalizedExplanationDisplay`; historical normalization and record parsers
retain their original profiles. New tests use invented media and mocked
responses with network and environment access denied. The owner approved the
v2/$40 packet. Its
[first live screen](../../../../docs/rfcs/identification-luna-sol-photo-screen-results-2026-09-28.md)
completed one reference-matching Luna identification, then stopped because a
material explanatory comparison was not assessable against the frozen notes.
`screen_failed` includes this reference-coverage outcome; it does not by itself
establish a wrong identification. The remaining seventeen calls did not run in
that original journal.

The owner subsequently approved completing only those seventeen assignments
under `reference_gaps_recorded_v1`, with the same combined 18-call/$40 cap.
`photoModelContinuation.ts` validates and fingerprints the original manifest,
terminal stop, claim, result, review and approval. The separate
`preflight-free-pro-photo-continuation` mode writes
`photo-model-continuation-preflight.json`; `--photo-model-continuation-live`
requires a new `photo-model-continuation-approval.json` and writes a sibling
`photo-model-continuation/` v2 journal. The original journal and first rating
stay unchanged. Its lock is held before the sibling lock throughout execution,
and its immutable evidence is rechecked before every dispatch.

The continuation inherits ordinal 1 and its reservation, then admits only
ordinals 2–18 once. It permits `not_assessable / insufficient_reference` during
screening while retaining that rating as a reference gap. Wrong identifications,
actual explanation failures, reviewer uncertainty/unavailability, technical or
safety failures and unknown billing still stop the screen. Aggregate v2 state
reports inherited/new calls and `referenceGapOrdinals`; `complete` describes
finished calls, while `explanationEvidenceComplete` separately requires every
rating to pass. Neither grants model qualification or production authority.

The approved continuation completed ordinals 2–6, preserving ordinal 1. All six
primary outcomes matched their provisional references, but the mineral control
failed the explanation specificity criterion. The retained `screen_failed` stop
prevented all twelve challenge calls, including every Sol control. The linked
screening result records the combined timing/cost measurements and decision to
retain the current Sol assignment. Completing those six calls does not qualify
Luna or establish a comparative Free/Pro advantage.

The separate
[Luna evidence-limit candidate](../../../../docs/rfcs/identification-luna-evidence-limits-candidate-2026-09-28.md)
uses a fresh packet and `photo_model_plan_v3`. Only Luna instructions change;
Sol, input evidence, facts and model tariffs remain identical. The existing
18-call controller requires a distinct `photo_model_candidate_approval_v1` for
`18_call_luna_evidence_limits_sol_photo_comparison`, explicitly binding
`reference_gaps_recorded_v1`. It records gaps separately and still stops on real
screening failures. The old approvals and continuation cannot authorize the
candidate. Use the same preflight/hidden-input launcher against the new root;
never overwrite or restart the stopped journals. Local verification alone does
not qualify the model.

The separately approved v3 run completed all eighteen calls. Its
[results and selection record](../../../../docs/rfcs/identification-luna-sol-candidate-results-2026-09-28.md)
retain every rating, reference gap and bounded measurement. Mineral evidence
limits passed, but biological quality failures block the Free switch; retain Sol
for both tiers. Three named challenge results per profile lack a machine
taxonomy mapping, including a correct displayed Sol name made ambiguous by
duplicate catalog identities. Null mappings are not wrong-identification or
abstention scores. Preserve these journals and repair mapping coverage only in a
versioned future packet/result contract. No additional calls are authorized.

### Photo rank-consistency preparation

The
[rank-consistency plan](../../../../docs/rfcs/identification-photo-rank-consistency-2026-09-28.md)
owns the historical rank work. The current optimization-first ordering above
supersedes its earlier next steps; completed rank packets remain closed.
`photoTaxonomyAudit.ts` checks duplicate names and reference IDs/ranks without
rewriting a frozen catalog. The separate `audit_photo_taxonomy.ts` command reads
only corpus/catalog inputs; a clear audit does not establish reference quality
or authorize dispatch. The actual completed packet has two canonical collisions,
including both species and genus identities. A new offline Sol packet merges
only these reviewed duplicate IDs; the original packet remains unchanged.

`projectMeasuredPhotoModelOutcome` and `parsePhotoModelMeasurementRecord` add
the isolated `photo_model_attempt_v2` primary mapping field. They retain enum
status and canonical/synonym match category, never returned taxon names or
prose. Historical photo plans and runners remain on v1 and reject v2 records.
The separate Sol plan/manifest/approval below binds the new projection; old null
taxon records cannot be repaired retrospectively. Use `assessMeasuredReference`
to keep mapping gaps separate from identity errors. Only the separately admitted
Sol mode writes live v2 photo records.

`solPhotoRankCandidate.ts` re-exports `_shared/ai/openaiSolRank.ts`, which
projects an isolated Sol prompt and four descriptive schema fields. It preserves
strict JSON structure, generation settings, explanation format and mineral
rules. Production and old live evaluation constructors reject the new profile.
`photoTaxonomyRepair.ts` requires a digest-bound explicit remap with equal
canonical names and ranks; it preserves input evidence, synonyms and supported
reference ranks.

`prepare_sol_rank_candidate.ts` validates and copies the twelve existing photos
into a new private packet, preserving completed artifacts and excluding plans,
approvals, credentials, prices and journals. Its receipt binds
baseline/candidate request digests and a proposed 18-call schedule, with live
readiness and dispatch explicitly false. Existing fact cards remain provisional.
The
[operator instructions](../../../../docs/development-guides/22-alternative-identification-provider.md#offline-photo-catalog-audit-and-rank-consistency)
cover the remap fields, scoped offline command and incomplete-directory
handling. No paid run or confidence calibration occurs in this preparation.

`solPhotoRankLivePreparation.ts` rebuilds these exact requests under
`sol_photo_rank_plan_v1`, checks a new digest-bound assistant reference review,
and adds a fresh full-context reservation. The new approval binds source, key
fingerprint, budget and review delegation. `solPhotoRankRunner.ts` uses a
separate `sol-photo-rank-run/` journal and only `photo_model_attempt_v2`.
Historical photo controllers and approvals cannot enter it.

The offline command is `preflight-sol-rank-photo`; the hidden-key launcher mode
is `--sol-rank-photo-live`. Screens stop separately for genuine failures and
unassessable mapping/identity references. Missing explanation references are
recorded as gaps; they never become passes. Results are durable before the
assistant's temporary review. Interrupted or stopped claims are never retried.
The summary separates screen/challenge denominators, reference agreement,
mapping, ratings, paired timing and known cost. Completing all 18 calls grants
no production or confidence-calibration authority. The
[first live screen and
source adjudication](../../../../docs/rfcs/identification-sol-rank-screen-results-2026-09-29.md)
retain a one-request stop whose explanation failure is undermined by incomplete
reference notes. Prospective fact corrections are separate; no historical
record, request or prompt was changed. Missing source coverage must not be
promoted into proof of a model error. Prospective `sol_photo_rank_summary_v2`
retains each raw `assessment` and adds `identityInterpretation`, plus separate
per-phase `identityCounts` and `identityInterpretationCounts`. Limited-reference
mismatches are `unassessable_limited_reference`; subject disagreement and
missing mapping remain distinct. Explanation ratings, failures and missing
reviews are preserved independently. New `sol_photo_rank_run_binding_v2`
bindings freeze this summary version. Legacy v1 bindings are rejected before
admission or summary generation; their complete journal, including state, stop
and summary, remains unchanged even after source or approval inputs change.

The separately approved
[corrected comparison](../../../../docs/rfcs/identification-sol-rank-comparison-results-2026-09-29.md)
completed all eighteen calls and reviews. Two candidate visual-evidence failures
block promotion despite improved broader-rank behavior. Its final v2 summary and
all 57 JSON journal artifacts were verified offline. Keep this completed packet
immutable and retain the unchanged Sol production assignment.

## Shared measurement repair (optimization Slice 1)

New exploratory packets may opt into `evaluation_taxonomy_v2`. Standalone live
v2 admission rejects before credential lookup with
`evaluation_measurement_live_pending`; the verified Slice 2 controller below is
the only controlled live path. Existing v1 live admission is unchanged. The
catalog records a frozen `taxonomyVersion`, `catalogRef` and `reviewRef`, with
each canonical taxon ID/rank, `canonicalName` and accepted `synonyms`. Review a
catalog containing plausible alternatives as well as references before a real
run; the new format and synthetic demo do not establish that review. Hash the
catalog into a new corpus/spec. Never change an old packet to recover an unsaved
name.

Resolution compares Unicode NFC, case and normalized whitespace only. Different
IDs sharing a name remain ambiguous, including canonical/synonym collisions;
there is no fuzzy or live lookup. New projections store `matched`, `ambiguous`,
`unmapped` or `not_applicable`, the canonical/synonym match category, canonical
IDs/ranks and candidate mapping states. They retain no returned name or prose.

The v2 catalog selects `identification_exploratory_decisions_v2`,
`evaluation_attempt_v2` / `evaluation_openai_attempt_v2`, and
`identification_exploratory_report_v2`. A run cannot mix these with v1 records
or change taxonomy during resume. Existing v1 packets keep their original
matching, scoring and nearest-rank p50 reports. Formal evaluation continues to
use its existing format and `compare`; v2 measurement is exploratory only.

V2 reports keep all scheduled outcomes. They separately show subject agreement,
identity-assessment coverage, mapped identity agreement, ambiguity, unmapped
names, unsupported specificity, valid abstentions and failures. An unmapped
identity is unassessed, not a verified disagreement. A genus reference does not
verify a more specific species prediction. Subject agreement remains measurable
when the name is unmapped; unverified references never enter quality rates.

Successful provider time uses the arithmetic median (average the middle two for
an even count). Partial medians remain diagnostic: complete latency eligibility
requires every scheduled case to normalize with a positive duration and no model
mismatch. Normalization, completed-call and failure timing stay separate. Each
report includes photo, description and combined summaries; empty groups remain
untested.

The separately labeled `rate_aware_usage_v1` estimate sums full-allocation cost
at reviewed rates. OpenAI input is partitioned into ordinary, cache-read and
cache-write tokens; visible output plus reasoning is charged once. Missing or
contradictory write counts stay unknown. Gemini discounts observed cache reads
and uses validated modality counts when input rates differ. Incomplete usage,
unknown execution or unattempted cases prevents a complete cost total. Known
partial cost and the unchanged conservative upper estimate remain visible.
Reviewed rates may be tier ceilings; neither estimate is an invoice. Current
profiles have no explicit cache objects or setup/storage operations; supporting
those later requires new accounting. The dispatch spend guard still uses its
original conservative estimate and applies to one run. Controlled experiments
add the outer accounting boundary below.

`compare-exploratory` validates saved v2 manifests/records, matched source,
corpus, taxonomy, preparation, order and evidence, then produces
`identification_exploratory_comparison_v1`. It preserves incomplete cases and
reports descriptive paired changes with
`100 * (baseline - candidate) / baseline`. A missing/nonpositive baseline or
incomplete measurements produces no percentage; cost percentages additionally
require matching pricing digests. Different-provider totals remain visible;
paired rate-card validation for a cross-provider cost percentage is deferred to
a reviewed candidate comparison. Cache comparability and screening are
explicitly unestablished. This ordinary command does not establish experiment
membership or completion; use `experiment-report` for controller evidence. This
report never qualifies a switch. The concise OpenAI candidate below uses the
separate v2 experiment report for cache verification and explanation ratings;
ordinary comparisons cannot establish those controls.

For a disposable demonstration using **four invented photo/text cases**, run
from the repository root:

```bash
measurement_parent=$(mktemp -d /private/tmp/naturebook-measurement.XXXXXX)
measurement_packet="$measurement_parent/packet"
deno run --frozen --no-prompt --deny-env --deny-net \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$measurement_parent" --allow-write="$measurement_parent" \
  --allow-run=git services/supabase/scripts/evaluate_identification.ts \
  demo-measurement "$measurement_packet"
deno run --frozen --no-prompt --deny-env --deny-net \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$measurement_parent" --allow-write="$measurement_parent" \
  --allow-run=git services/supabase/scripts/evaluate_identification.ts \
  compare-exploratory "$measurement_packet" \
  offline-measurement-v2 offline-measurement-v2 gemini_pro openai_gpt_6_sol
```

Both commands use synthetic outcomes with no credentials/provider calls. The
comparison JSON filename includes both run IDs and profiles. The existing
`report` command regenerates either report version from saved records without
media or inference. Real experiments still require the independent live
admission and budget contract. The
[completed matched comparison](../../../../docs/rfcs/identification-gemini-openai-matched-results-2026-09-27.md)
is the eight-case development outcome; it does not qualify production use. The
[current optimization plan](../../../../docs/rfcs/identification-optimization-preserving-results-2026-09-27.md)
owns future priorities, while the
[earlier plan](../../../../docs/rfcs/identification-provider-optimization-plan.md)
retains the history of these measurement controls.

## Reusable profiles and experiment controls (optimization Slice 2)

`reusableProfiles.ts` owns two reviewed evaluation baselines:
`gemini_photo_text_v1` and `openai_photo_text_v1`. Their versioned descriptors
include provider/API, supported complete inputs, snapshot/generation settings,
confidence policy, and hashes of actual native settings, prompts and schemas.
The native settings hash excludes observation content. Golden fingerprints and
per-case projection checks bind the descriptor to the unchanged request
builders. No endpoint, generation override or candidate definition is accepted
from packet JSON. Production still selects its fixed Gemini binding.

The v1 controller accepts those two baselines and retains their automatic cache
behavior recorded as uncontrolled. The separate v2 candidate contract below adds
the uncached control and concise OpenAI profile with mandatory private review.
No packet can supply arbitrary native settings. Neither contract adds
prewarming, cache objects, paid judge calls, retries or a production selector.

These are code-defined allowlists. V2/v3 admit only their existing concise
hypothesis and review contract; they are not a generic candidate runner. A new
cache, prompt, media or native-setting hypothesis requires reviewed profile
registration and compatible plan/report/accounting support before live
admission. Do not repurpose a completed packet, change a frozen profile or relax
validation to fit a new candidate. The hosted wrapper likewise accepts only its
fixed baseline pair.

### Frozen plan and accounting

`experimentContracts.ts` validates `identification_experiment_plan_v1` in a new
private packet's `experiment.json`. It freezes source, corpus, taxonomy,
preparation, case/evidence digests, order seed, review reference, metric
formulas, a window of at most 24 hours, and one to four ordered single-provider
runs. There are at most eight cases and 32 scheduled calls. Every run names a
reviewed profile ID/digest, its exact call/USD allocation, a reviewed pricing
card/digest and, for live execution, a readiness digest. Full conservative
reservations must fit each allocation; their sums must fit the overall limits.
Unused funds never transfer between runs. Synthetic packets use explicitly
labeled simulated accounting with invented rates.

Live readiness records live only in `approvals/<runId>.json` and use the
existing provider-specific approval schema. They are not copied into experiment
records. The active provider's key, readiness, input permissions, pricing age
and consent review are revalidated through the existing admission before each
invocation. The controller never obtains both provider keys. Preparation of all
frozen inputs and profile settings precedes dispatch.

For a shared paid Gemini application project, use the explicit
`evaluation_gemini_processor_v1` readiness record described below. The
[matched photo/text comparison plan](../../../../docs/rfcs/identification-gemini-openai-matched-comparison-2026-09-27.md)
uses these two existing baselines and keeps preparation separate from live
approval. `experiment-preflight` requires complete readiness records even though
it does not dispatch. While reviews or the run window are pending, retain a
non-executable draft and use ordinary corpus `preflight` without `spec.json`; do
not fabricate readiness hashes or approvals to make controller preflight pass.

The controller creates immutable `experiment/manifest.json`, linking the plan,
profile descriptors and existing per-run manifests. Both the input marker and
controller directory prevent ordinary `prepareRun`/`executeRun` from taking over
a controlled packet. A private, expiring in-process capability is registered
only after verification under the experiment lock; JSON or injected runner
callbacks cannot enable controlled live execution. Fresh experiments reject
preexisting run journals. V1 specifications, assignments and reports keep their
original interpretation.

Lock order is experiment, then run. One active controller holds the experiment
OS lock throughout execution. Before **every** invocation it reconciles all
linked journals, checks the frozen run order, time window and both budget
levels, and durably writes a global reservation before the existing local claim.
The sequence is reservation → local claim → one invocation → durable result →
settlement. A saved result without a settlement is reconciled exactly once. An
unmatched reservation/claim, unknown execution, model drift, operational
failure, missing budget-critical usage or another runner stop blocks all later
runs. A call finishing after expiry is recorded and settled before stopping.

Known validated conservative usage replaces its reservation once. Uncertain
execution and unknown cost retain the full reservation. The controller uses
integer nanodollars, rounding charges up and budgets down; rate-aware reporting
remains separate. `experiment/state.json` exposes charged/retained amounts,
completed allocations and the global stop. Normal allocation completion permits
the next frozen run; restarting or asking for another run cannot clear a stop.
There is no reset/continuation command. A future reviewed continuation must
preserve prior claims and original aggregate caps, never replay an uncertain
attempt or erase the stop file.

### Commands and reports

For an offline demonstration with four invented cases and two baselines:

```bash
experiment_parent=$(mktemp -d /private/tmp/naturebook-experiment.XXXXXX)
experiment_packet="$experiment_parent/packet"
deno run --frozen --no-prompt --deny-env --deny-net \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$experiment_parent" --allow-write="$experiment_parent" \
  --allow-run=git services/supabase/scripts/evaluate_identification.ts \
  demo-experiment "$experiment_packet"
```

The same offline permission boundary supports `experiment-preflight <packet>`,
`experiment-offline <packet> <runId>` and `experiment-report <packet>`.
Preflight prepares every run without loading a key, claiming an attempt or
dispatching. `demo-experiment` invokes eight synthetic outcomes; these are not
provider calls or real accuracy/performance evidence. `report <packet> <runId>`
still reads the existing per-run records. Both report forms regenerate after
media removal.

For an explicitly authorized real experiment, the active OpenAI run uses the
existing hidden-input launcher:

```bash
bash services/supabase/scripts/run_openai_evaluation.sh \
  --experiment-live /absolute/private/packet openai-baseline-run-id
```

The launcher checks the selected provider before prompting, runs credential-free
experiment preflight, and grants OpenAI network/key access to
`--experiment-live <packet> <runId>`. V2/v3 candidate runs additionally receive
only the loopback listener and fixed macOS browser opener permissions described
below. Gemini uses that same controlled CLI with its existing single-provider
environment/network grants from the provider guide. Keys never appear in
arguments, files or artifacts. This command is a procedure, not authorization to
run a paid experiment. Regenerate `experiment-report` in a separate offline
process after a live run; it requires neither keys nor media.

To execute an approved OpenAI-only plan in one local session, use:

```bash
bash services/supabase/scripts/run_openai_evaluation.sh \
  --experiment-session /absolute/private/packet
```

This prompts once and retains the key only in process memory while invoking the
existing controller for each frozen run in order. Every selected run must be an
allowlisted OpenAI profile. It checks the controller's durable state after each
run, including successful process exits: a stop, missing state or incomplete run
ends the session before another profile starts. Changing the plan ends the
session as well. Interruption preserves the existing claims and never retries an
uncertain call. Delegated explanation review still needs the active assistant
for each result; session mode does not supply an unattended judge or relax any
readiness, spending, cache or quality requirement.

`identification_experiment_report_v1` verifies frozen run membership, saved
record compatibility, reservation/result links and settlements under the
experiment lock. It distinguishes a completed allocation from an unstopped
complete experiment and from provider qualification. It includes the Slice 1
measurements and retains incomplete cases. Ordinary `compare-exploratory`
remains descriptive and is not a controller completion record.
Different-provider rate cards still produce descriptive cost totals without a
percentage verdict; frozen cards alone do not establish paired-rate
comparability. Cache comparability remains `not_established`, screening is
`deferred_no_candidate`, and production qualification is always false in these
development reports.

## OpenAI explicit-null candidate

The current implementation follows the
[explicit-null candidate record](../../../../docs/rfcs/identification-openai-null-fields-candidate-2026-09-27.md).
`openai_photo_null_fields_v1` supports photos with optional observation context.
It changes exactly four omission instructions to explicit null instructions in
`openai_identify_vision_null_fields_v1`; the common strict schema and
explanation definition are unchanged. Reusable profile construction checks the
frozen candidate prompt/schema digests. Text-only, audio and sampled-video input
fail as a whole. Production registration and assignment remain separate.

`identification_experiment_plan_v4` admits exactly these ordered runs:

1. `openai_photo_text_v1`, the unchanged reusable OpenAI baseline executing
   `openai_gpt_6_sol`.
2. `openai_photo_null_fields_v1`, the isolated wording candidate.

Both runs bind the same rate-card digest. Live plans require exactly six photos,
six calls per arm and twelve total; offline synthetic demonstrations can be
smaller. Every case must be a photo in both arms. Accepted photo evidence and
optional observation text stay intact. The decision is
`null_fields_consistency_ai_review_v1`, metrics use `thresholdPercent: null`,
and cache control is `automatic_uncontrolled_no_extra_requests`. Native cache
options match the baseline. V1 remains restricted to the original two baselines,
while v2/v3 keep the original concise pair, eight cases and explicit zero-cache
requirement.

V4 uses `identification_provider_run_spec_v3` and
`identification_provider_run_v3`. Candidate attempts are
`evaluation_openai_attempt_v4`; unchanged baseline attempts remain
`evaluation_openai_attempt_v2`. Older specs, manifests and attempts cannot claim
the new candidate identity. Standalone admission rejects both controlled
candidate specification versions, including offline. Source, complete-input
preflight, readiness, reservations, global stops and no-replay accounting remain
mandatory; a new plan version is not live authorization.

The review is the same delegated assistant method described below:
`assistant_local_v1`, an opaque delegation reference, frozen fact cards and
rubric, `calibrationDigest: null`, and bound `explanation_assessment_v2`
records. Missing or failed review stops later calls. This mode does not require
owner practice, invent human review or add paid judge requests. The same private
review disclosure and retention limits apply.

V4 does not impose the old zero-cache condition. Observed cache reads/writes are
retained, and unknown counters stay null. Conservative upper estimates still
enforce budgets; missing budget-critical usage retains its reservation and
stops. Rate-aware cost can remain unknown even when a conservative charge is
known. Neither unknown nor nonzero cache counters are interpreted as savings.

`identification_experiment_report_v4` regenerates from frozen manifests, bounded
attempts and bound assessments, without media or explanation prose. It reports
per-run measured times/costs, but improvement percentages are null, cache
comparability is `not_established`, and `performanceInterpretation` is
`descriptive_only_uncontrolled_cache`. `nullFieldsReport.ts` checks all twelve
completed assessments and six supported pairs without a speed target. New
quality faults retain the baseline; missing evidence, unresolved identities or
existing reference faults are inconclusive. Only a complete, supported screen
returns `no_observed_regression_in_six_photo_screen`. `productionQualified` is
always false. A six-photo screen cannot establish safety or quality outside its
covered inputs.

Run the new synthetic demonstration separately from the retained concise demo:

```bash
null_fields_parent=$(mktemp -d /private/tmp/naturebook-null-fields.XXXXXX)
deno run --frozen --no-prompt --deny-env --deny-net \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$null_fields_parent" --allow-write="$null_fields_parent" \
  --allow-run=git services/supabase/scripts/evaluate_identification.ts \
  demo-null-fields "$null_fields_parent/packet"
```

This uses invented outcomes and synthetic ratings only. It does not invoke a
model, grant an allocation or establish identification quality. The hidden-key
launcher supports a reviewed v4 packet using the existing session command only
after its fresh bounded paid allocation and processor readiness are authorized.

## Concise OpenAI candidate and private review

This retained contract belongs to the
[closed 26 September screen](../../../../docs/rfcs/identification-openai-concise-screen-2026-09-26.md).
Concise explanations are not selected in the current plan. Keep its profiles,
tests and immutable outcomes; do not resume the fifteen unattempted assignments
or treat their unused budget as available for a different experiment.

The two additional code-defined profiles are `openai_photo_text_uncached_v1`
(control) and `openai_photo_text_concise_uncached_v1` (candidate). Both use
`prompt_cache_options: {mode: "explicit"}` with no breakpoints. Only the
candidate adds the plan's `ai_reasoning` instruction and its own vision/text
prompt versions. Model, low reasoning, high image detail, output limit, schema,
input bytes and normalization stay identical. Baseline fingerprints and native
requests are unchanged. Account support and live zero-cache behavior remain
unverified; missing or nonzero read/write counters stop without a fallback call.

`identification_experiment_plan_v2` admits exactly these two ordered runs, one
shared pricing digest and `concise_explanation_latency_v1`. Live plans require
six photos and two descriptions: eight calls per arm, sixteen overall. Existing
allocations, readiness, source binding, lock and stop rules still apply. The
candidate uses `identification_provider_run_spec_v2`,
`identification_provider_run_v2` and `evaluation_openai_attempt_v3`; v1/v2
historical attempts keep their meanings and reject candidate identities.
Standalone candidate dispatch is rejected even offline.

Before freezing either review mode, prepare private `review/facts.json`
(`explanation_facts_v1`) from the exact evidence and complete the owner's
calibration only when selecting the v2 human-review mode. Each fact card binds
case/input digests, observed and missing facts, acceptable reasons,
supported-rank limits and bounded requirements. These facts never enter provider
requests. The plan's `review` binds the rubric, aggregate facts, individual card
and calibration digests, an opaque reviewer reference, and a 60–600-second
review timeout. A real v2 human-review packet must contain actual owner choices;
the synthetic demonstration's certificate is rejected for live use. The
delegated v3 mode below does not require a human calibration certificate.

When the user delegates explanation analysis to the active assistant, use
`identification_experiment_plan_v3` with
`candidateDecision: concise_explanation_latency_ai_review_v1`. Its review adds
`method: assistant_local_v1` and an opaque `delegationRef` recording that
instruction, and requires `calibrationDigest: null`. No owner certificate is
created or inferred from the synthetic answer key. The delegated assistant
actually inspects each case's supplied evidence, frozen facts and bounded
explanation in the existing private view, then submits the same three ratings.
This is a supervised assistant workflow, not an unattended judge service or
keyword heuristic; it adds no paid judging API requests. The owner need not
complete the practice form or grade every result.

Delegation covers only the task-approved evaluation corpus. The view's bounded
content is processed in the assistant session and may be retained in that
service's conversation/tool context; this mode must not be described as
local-only or entirely in memory. Do not export screenshots, whole responses,
hidden reasoning, private user observations or credentials into an analysis
archive. Evaluation files still retain only bound enum assessments and
measurements. User delegation does not approve new inputs, another processor,
spending or production use.

V3 emits `explanation_assessment_v2` with `assistant_local_v1` for actual review
and `synthetic_fixture_v1` for offline tests. V1 owner assessments cannot be
substituted for these records, and synthetic assessments never satisfy live
review. `identification_experiment_report_v3` explicitly identifies AI-reviewed
development evidence, `independentHumanValidation: false`, zero additional judge
calls and the possibility of shared model errors. All existing quality, cache,
budget, timeout, ledger and no-replay checks remain in force. Historical v2
human plans keep their original calibration and assessment contract.

For the optional v2 human mode on a Mac, run calibration without any API key or
provider-network permission:

```bash
review_packet=/absolute/private/packet
mkdir -p "$review_packet"
chmod 700 "$review_packet"
deno run --frozen --no-prompt --cached-only --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$review_packet" --allow-write="$review_packet" \
  --allow-net=127.0.0.1 --allow-run=/usr/bin/open \
  services/supabase/scripts/evaluate_identification.ts \
  calibrate-explanations "$review_packet" owner-review-v1
```

The owner scores eight invented examples using each page's Observation text as
the reference; there is no separate photo or external source to look up. All
expected ratings must match before `review/calibration.json` is created. A
failed calibration writes bounded `review/calibration-feedback.json`; review its
expected/actual ratings and rerun calibration. No real explanation is in that
feedback. Calibration cannot replace an existing certificate or run after the
experiment begins.

During live execution, the bounded provider result and cost settle before the
browser opens. The private view shows evidence, frozen facts, decision,
`ai_reasoning`, extracted traits and applicable alternative explanations. It
hides profile, tokens, timing, cost and prior ratings. The view uses escaped
text, a one-use random capability, same-origin checks, no third-party assets, no
browser storage and no response caching/logging. The opener has an empty child
environment. Loopback/opener permissions are checked before a paid claim. Do not
save, photograph or record real review pages. Sequential owner review is
provisional and cannot guarantee full blinding.

The next provider call waits for all three ratings. Close, timeout, unavailable
review, failed or unassessable criteria stop the whole experiment. Durable
`explanation_assessment_v1` files under
`experiment/assessments/<runId>/<attemptKey>.json` contain only bounded
ratings/reason codes and exact
plan/run/request/profile/input/card/result/rubric/ calibration/reviewer
bindings. No raw explanation enters these files or reports. A crash after
settlement preserves the known result and charge; the missing assessment stops
recovery without repeating inference.

`identification_experiment_report_v2` validates and includes assessment records
and their digests; it regenerates without facts, media or model prose. Per-run
measurement reports point to it for explanation status. An offline result says
`synthetic_mechanics_only`. A real screen requires all sixteen assessments to
pass, verified zero cache reads/writes, complete paired quality/time/cost, at
least 10% combined median latency improvement and no cost or input-group
regression above 10%. Unresolved quality makes it inconclusive; a new quality
fault retains the control. Passing means only
`candidate_for_further_qualification`, with `productionQualified: false`.

Run the complete synthetic path with no network or credentials:

```bash
candidate_parent=$(mktemp -d /private/tmp/naturebook-candidate.XXXXXX)
deno run --frozen --no-prompt --deny-env --deny-net \
  --config services/supabase/functions/deno.json \
  --allow-read="$PWD,$candidate_parent" --allow-write="$candidate_parent" \
  --allow-run=git services/supabase/scripts/evaluate_identification.ts \
  demo-candidate "$candidate_parent/packet"
```

This makes four invented cases and eight synthetic outcomes/assessments. It
proves workflow mechanics, not semantic review or model performance. A real
packet, owner calibration and paid execution remain pending. Use the existing
hidden-input launcher only after the exact paid experiment is authorized.

## Owners and use

| File                                   | Responsibility                                                                                                                                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| [contracts.ts](./contracts.ts)         | Versioned corpus, input, reference, curation, normalized prediction, and aggregate score-report types. These are internal evaluation records, not public API DTOs.                               |
| [validation.ts](./validation.ts)       | Runtime validation of corpus/input/prediction records, approval assertions, split/duplicate checks, media relationships, and content-free error codes.                                           |
| [evidence.ts](./evidence.ts)           | Allowlisted evidence projection, existing production capture-context formatting, and canonical SHA-256 fingerprints.                                                                             |
| [scoring.ts](./scoring.ts)             | Pure point estimates over normalized predictions, using current Gemini thresholds only for Gemini; OpenAI confidence bands are unqualified. No provider invocation or real-output normalization. |
| [normalization.ts](./normalization.ts) | Validates input records and passes actual media-presence/tier facts into the shared production normalizer. No copied identification policy or I/O.                                               |
| [fixtures.ts](./fixtures.ts)           | Twelve invented cases across all six input groups, with invented taxonomy IDs, asset descriptors, and normalized outcomes. No actual media files.                                                |

Additional owners:

- `assets.ts` loads prepared evidence and reuses the production multimodal
  builder.
- `profiles.ts` resolves Gemini production profiles or the explicit OpenAI
  evaluation binding and fingerprints native parameters; the pure shared
  `functions/_shared/ai/geminiRequest.ts` avoids SDK initialization.
- `runContracts.ts` validates specifications, pricing, readiness, manifests,
  durable claims and bounded attempt records.
- `admission.ts` binds live corpus, taxonomy, project/key review and
  permissions.
- `files.ts` owns private files, exclusive OS locks and flushed writes.
- `runner.ts` owns preflight, single-call execution, immutable resume and
  per-run budgets. `reusableProfiles.ts` owns reviewed profile descriptors;
  `experimentContracts.ts` owns bounded plans and allocation math;
  `experiment.ts` owns controller capability, locks, cross-run journals and
  stops; `experimentReport.ts` owns controlled reports. `experimentOffline.ts`
  supplies invented controller demonstrations; `candidateOffline.ts` adds the
  retained concise path. `candidateReport.ts` owns its fixed screening gate.
  `nullFieldsOffline.ts` supplies the separate photo-only v4 demo;
  `nullFieldsReport.ts` owns its consistency screen without a speed verdict.
- `explanationContracts.ts` owns bounded ratings, bindings and private fact-card
  validation; `explanationCalibration.ts` owns invented practice anchors;
  `explanationView.ts` owns the ephemeral loopback view; `explanationReview.ts`
  owns its in-memory projection and calibration workflow.
- `projection.ts` maps normalized decisions/usage without persisting model
  prose. `taxonomy.ts` owns frozen catalog validation and bounded mapping.
- `measurementCost.ts` owns rate-aware estimates; `exploratoryMeasurement.ts`
  owns v2 provisional assessments/metrics, and `exploratoryComparison.ts` owns
  descriptive comparisons with incomplete-case accounting.
- `reports.ts` regenerates metrics, intervals, timing/cost and paired
  comparisons.
- `offline.ts` builds invented PNG/WAV fixtures for local mechanics tests.
- `exploratory.ts` owns the separate provisional corpus and shared run-corpus
  helpers; it does not relax the formal corpus contract.
- `exploratoryReport.ts` records operational outcomes and provisional reference
  agreement without admitting exploratory evidence into formal scores.
- `preflight.ts` prepares and fingerprints a supplied corpus without claims, a
  key or network access.
- `appObservation.ts` validates content-free native measurements, projects
  bounded numeric logs and reuses `profiles.ts` for optional conservative
  primary-attempt estimates. `appObserver.ts` owns collector readiness, bounded
  shutdown, event limits and content-free exit diagnostics.
  `../observe_identification_app.ts` passively records a bounded simulator
  window into a new private JSONL file. It submits no requests and has no
  network or provider-key access. Its artifacts are observations, not runner
  reports or formal quality scores. See the
  [app measurement guide](../../../../docs/development-guides/21-identification-app-measurement.md).
- `../evaluate_identification.ts` is the thin CLI; importing it performs no I/O.

`parseEvaluationCorpus(unknown)` validates and copies a complete corpus record.
`projectEvaluationEvidence(input)` accepts only the input record; passing an
entire case or adding reference fields fails. Its result preserves observation
text, ordered asset/clip descriptors, and the production context projection,
including `Context: no telemetry.`. It is a loader input, not an SDK request.
Only coarse two-letter region and month are currently allowed as context.

`fingerprintCorpus` freezes all corpus records, including references and
curation. `fingerprintEvidence` hashes only the projected evidence. Object key
order does not affect either hash; ordered arrays do. Declared asset hashes are
included. `prepareEvidence` verifies contained regular files, rejects symlinks
and hardlinks, bounds reads, checks actual bytes/hashes, and enforces the
current route media budgets. The exact native request is separately
fingerprinted. Image checks validate JPEG/PNG/WebP containers, dimensions and
metadata rules; they are **not full pixel decoding**. Curation must decode and
visually/privacy review final prepared files before hashing. Unknown metadata,
EXIF/XMP/comments and animated WebP are rejected. Prepared WAV must be PCM16,
one or two channels, 8–96 kHz, with consistent lengths/rates and no extra
metadata chunks; the actual production WAV parser, mono/resampling and trimming
then run. These restrictions are evaluation preparation rules, not changes to
production upload admission.

The shared processor includes partial-window silence measurement and bounded
windowed-sinc resampling to 16 kHz. Evaluator preparation inherits the same
output/work ceilings; a processing-budget failure cannot dispatch a provider
request. See the
[audio preprocessing comparison](../../../../docs/rfcs/identification-audio-preprocessing-fix-2026-09-23.md)
for the offline evidence. Historical run fingerprints remain frozen; a new
processor requires a new run rather than overwriting a prior baseline.

### Prompt assignment and observation integration

`generate_audio_prompt_comparison_plan.ts --write` checks the immutable Slice 1
preparation digest and derives separate backend/native tables with 36 stable
scan IDs. `--check` and its root test detect stale output. Neither mode
recreates the old preparation or grants runtime permission. Runtime A/B request
and policy hashes must still match the frozen source preparation; the newly
generated backend bundle identity records the extended runtime graph separately.

`audioPromptComparisonObservation.ts` strictly parses the new bounded native
proof. `comparisonWindow.ts` shares unchanged lifecycle admission with the old
DSP wrapper; `audioPromptComparisonWindow.ts` requires exactly 120 seconds and
retains actual subject state, conditional confidence and provisional name-hash
agreement. The separate
[offline admission CLI](../admit_audio_prompt_comparison_observation.ts) writes
exclusive private evidence with no network or environment access. See the
[measurement guide](../../../../docs/development-guides/21-identification-app-measurement.md#prompt-comparison-observation)
for command, input shape and evidence limits. The old DSP controller cannot
activate this new plan. The separate prompt controller and offline execution
ledger below own its bounded operation.

### Offline prompt execution freeze and ledger

[prepare_audio_prompt_execution.ts](../prepare_audio_prompt_execution.ts)
creates a new private execution packet from the two retained reviewed source
packets and a reviewed metadata JSON file. Unlike the dated preparation, this
requires a clean actual source/app pair, matching generated backend/native
tables and bundle, current reviewed pricing, and three bounded windows. It
verifies the retained source/reference permissions and request hashes, copies
six exact WAVs to case-only filenames, and freezes `run.json` with exact-file
and canonical hashes in `freeze.json`. A failed preparation cannot resume or
overwrite an output. No owner ID, credential, session data or provider response
is accepted.

The strict review shape is `audio_prompt_execution_review_v1`: `reviewedAt`,
`sourceSha`, `deployedSha`, the five-field measurement `app` identity,
`backendBundleSha256`, `pricing` (the existing `evaluation_pricing_v1`
contract), `windows` (ordered blocks 1–3, each with `block`, `startsAt`,
`expiresAt`) and `privatePreflight`. Use UTC millisecond timestamps. The pricing
snapshot must cover all three windows; each window is at most two hours inside
source retention. Obtain the actual clean app and deployment identities after
review, not from a synthetic fixture or the previous dirty test build.

`privatePreflight` has exactly `version: audio_prompt_private_preflight_v1`,
`checkedAt` and five true boolean assertions:
`ownerMatchesReviewedConfiguration`, `sameReviewedOwner`, `consentCurrent`,
`appMatchesReview`, `foreground`. Perform those checks privately against the
current authenticated simulator and reviewed configuration before recording the
witness. It must be at most five minutes old and, for each new claim, no earlier
than activation or the previous observation's completion. It is an unsigned
operator witness, not proof of authentication; backend owner/consent checks stay
authoritative. Never record the actual account/configuration/session values.

Replace uppercase placeholders with absolute private paths. `OUTPUT_PARENT` must
exist, `RUN` must be its new child, and all paths must be canonical:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=.,SOURCE_V2,SOURCE_VISIBLE,REVIEW,OUTPUT_PARENT \
  --allow-run=git --allow-write=RUN \
  services/supabase/scripts/prepare_audio_prompt_execution.ts \
  SOURCE_V2 SOURCE_VISIBLE REVIEW RUN
```

[manage_audio_prompt_execution.ts](../manage_audio_prompt_execution.ts) and
[audioPromptExecution.ts](./audioPromptExecution.ts) maintain `slots/` and
`controls/` under that packet, with exclusive locking and flushed, create-only
records. `claim` verifies all six frozen WAV hashes again and the unchanged
clean local implementation, then reserves the next first attempt **before**
manual Identify. It accepts only the exact block's sanitized activation receipt
and a fresh witness. It submits nothing. Example claim for slot 1:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=.,RUN,ACTIVATION,WITNESS --allow-run=git --allow-write=RUN \
  services/supabase/scripts/manage_audio_prompt_execution.ts \
  claim RUN 1 ACTIVATION WITNESS
```

The other operations have four arguments: `admit RUN SLOT OBSERVATION` and
`close RUN BLOCK CLEANUP`. Use the same denied network/environment flags,
`--allow-read=.,RUN,INPUT --allow-write=RUN`, and the corresponding private
input file; neither operation needs `--allow-run`. `admit` requires the exact
frozen pricing, a matching fresh 120-second window after the claim, and
completion before block expiry. It retains normalized proof, subject state,
score, timing and cost provenance, never response prose. A failed observation
creates an immutable exclusion and cannot be replaced by a later good window.

A claim without completion blocks all subsequent slots, including after a crash
before the tap. There is no retry, skip, reset or budget expansion API. Complete
unfavorable outcomes are retained; missing cost stays unknown for the final
screen. Close each block with verified deactivation evidence after its last
completion or exclusion. A failed block can close for recovery but cannot
resume. The next block requires the previous twelve completions and verified
cleanup before its own activation. Recovery may use a different controller SHA
with trusted workflow-artifact provenance and verified absence. The offline
ledger validates receipt shape and bindings, not ancestry or current-main
status; identification still uses the frozen app/runtime bindings.

Follow the
[activation/recovery procedure](../../../../docs/backend-and-data/06-supabase-deployment-runbook.md#audio-prompt-comparison-activation-prerequisites).
The controller and ledger do not authorize a deployment, secret creation or paid
run; they also do not prove that a request happened or replace the server's
single-attempt gate. Actual admission requires the app's runtime receipts. Keep
the frozen checkout throughout execution, stop on uncertain submissions, and
preserve every record through the source retention deadline.

### Explicit continuation after an expired between-trial pause

[manage_audio_prompt_continuation.ts](../manage_audio_prompt_continuation.ts)
creates one separately versioned amendment at the fixed sibling path
`ORIGINAL.continuation`. It does not reopen the original ledger. Eligibility
requires a contiguous completed prefix ending **inside** a block, all activated
original blocks closed with verified absence, the final partial block cleaned up
after its window expired, and no local evidence or operator uncertainty about
later submissions. Open claims, exclusions, gaps, and a prefix ending at a block
boundary are ineligible.

[audioPromptExecutionEvidence.ts](./audioPromptExecutionEvidence.ts) re-admits
every original observation and binds the exact manifest, claims, completions,
control receipts, observation bytes, and any retained operator/witness files. It
checks all six original assets each time. The original's existing `.lock` inode
is locked read-only; it is never created, replaced or written. Operations take
that lock before the sidecar lock. The fixed sibling directory is create-only,
so a second preparation or continuation-of-continuation fails closed. The
separate successor protocol below leaves this legacy behavior unchanged. Keep
both directories canonical and private. Never copy the original to manufacture
another eligible path or remove a failed sidecar.

The continuation pins the clean tooling commit/digest and the reviewed current
deployment revision separately from the original app, deployment history,
generated assignments and runtime bundle.
[audioPromptContinuationContract.ts](./audioPromptContinuationContract.ts)
requires the new control SHA and amended window while keeping the original
runtime identity. The app is not rebuilt for a tooling-only continuation.
Pricing cannot be refreshed: the original reviewed snapshot must remain valid
through all new windows, each at most two hours and within media retention.

First inspect the stopped original offline:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=.,ORIGINAL \
  services/supabase/scripts/manage_audio_prompt_continuation.ts inspect ORIGINAL
```

Prepare a strict `audio_prompt_continuation_review_v2` review with `reviewedAt`,
`sourceSha` (the clean tooling/controller SHA), `deployedSha` (the current
successful deployment resolved by the protected control workflow),
`originalEvidenceSha256` from inspection, `firstSlot` (exactly the completed
prefix plus one), ordered `windows` for the remaining blocks, and the existing
fresh `privatePreflight` witness. It also requires true `noUnrecordedAttempts`,
`remainingNeverSubmitted`, and `pauseBetweenCompletedSlots` operator assertions,
plus `analysisPolicy: original_screening_rules_with_disclosed_interruption`.
These are unsigned assertions, not a provider-dispatch audit. Obtain separate
authorization for the new bounded windows before activation; preparation and
inspection submit nothing.

The reviewed deployment SHA may advance after a tooling-only release, while the
original bundle, prompts, plan and app must still match. Activation must equal
the new review's exact `deployedSha`; merely naming any valid revision is
insufficient. Keep the original evidence's deployment SHA unchanged. Existing
`audio_prompt_continuation_review_v1` packets retain their original-deployment
binding and reject an added `deployedSha`; they are never upgraded in place.

For preparation, `ORIGINAL_PARENT` is the existing canonical parent directory of
`ORIGINAL`. Its read grant covers the new sibling and the parent-directory flush
needed to make creation durable. The write grant stays limited to the sibling.

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=.,ORIGINAL_PARENT,REVIEW --allow-run=git \
  --allow-write=ORIGINAL.continuation \
  services/supabase/scripts/manage_audio_prompt_continuation.ts \
  prepare ORIGINAL REVIEW
```

For `claim ORIGINAL SLOT ACTIVATION WITNESS`, `admit ORIGINAL SLOT`, and
`close ORIGINAL BLOCK CLEANUP`, use the same denied network/environment flags
and `--allow-read=.,ORIGINAL,ORIGINAL.continuation,INPUTS`, plus
`--allow-write=ORIGINAL.continuation`. Claim and admit also need
`--allow-run=git` to verify the pinned tooling. Substitute the actual
receipt/witness files for `INPUTS`.

Report requires an existing canonical private `OUTPUT_PARENT` outside both
packets. It writes a new direct child file and cannot overwrite an existing
report:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=.,ORIGINAL,ORIGINAL.continuation,OUTPUT_PARENT --allow-run=git \
  --allow-write=ORIGINAL.continuation,OUTPUT_PARENT \
  services/supabase/scripts/manage_audio_prompt_continuation.ts \
  report ORIGINAL OUTPUT_PARENT/report.json
```

Claim verifies the original evidence again and reserves only the next untouched
assignment. Stage that original slot and WAV in the unchanged app, start the
normal passive observer at `ORIGINAL.continuation/observations/slot-NN.jsonl`,
wait for `observer_ready`, then tap Identify once. Admit reads this fixed file,
requires the full matching 120-second window and frozen pricing, and records a
distinct continuation completion. Invalid observations become terminal sidecar
exclusions. An open claim cannot be retried even if the tap may not have
happened. A previously used server assignment fails first-attempt admission; it
never authorizes another slot or replacement.

Close every activated amended block after its last claim/completion/exclusion.
Close can retain verified cleanup even if the original files or tooling later
change; claiming and reporting still reject that drift. The next block requires
the preceding block's final completion, verified cleanup and subsequent new
activation. Failure or expiry closes this sidecar permanently.

The content-free combined evidence report identifies original and amended rows
separately. All 36 unique first attempts, known required timing/cost and
verified cleanup are required before evaluating the unchanged screening rules.
The report does not itself score visible names, declare a candidate win or
authorize promotion. Preserve the original stopped-run report and disclose the
interruption in any subsequent analysis. See the
[canonical amendment procedure](../../../../docs/backend-and-data/06-supabase-deployment-runbook.md#amend-an-expired-prompt-comparison-between-completed-trials).

### Explicit successor after a closed first continuation

The separate
[manage_audio_prompt_successor.ts](../manage_audio_prompt_successor.ts) creates
exactly one fixed sibling, `ORIGINAL.continuation.successor`. It is a new
protocol, not an upgrade or reset of either predecessor. Existing v1/v2
continuations stay terminal after failure or expiry. No additional successor,
copied packet, alternate directory, replacement slot or uncertain attempt is
eligible.

`audioPromptSuccessorEvidence.ts` re-admits both original and continuation
observations, requires a contiguous completed prefix ending inside a block, and
requires every activation closed, with the final continuation cleanup after its
expiry. It hashes all continuation records and binds two retained stopped
reports as opaque, bounded private JSON files. Private path locators stay inside
the private manifest; inspect and derived report output expose only their
hashes. Those report hashes preserve history; their contents never replace
runtime observation validation or prove biological truth. Their paths and bytes
must remain unchanged.

Locks are acquired in order: the existing original lock read-only, the existing
continuation lock read-only, then the successor lock. Preparation uses a
create-only directory and fsynced files. Parent evidence is revalidated before
each claim, admission and report. Parents and reports receive read permissions
only. A pending or excluded successor trial permanently prevents further
progression. Cleanup stays available after parent/tooling drift.

Inspect both parents before preparing a new review:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=.,ORIGINAL_PARENT,ORIGINAL_REPORT,CONTINUATION_REPORT \
  services/supabase/scripts/manage_audio_prompt_successor.ts \
  inspect ORIGINAL ORIGINAL_REPORT CONTINUATION_REPORT
```

The strict `audio_prompt_successor_review_v1` has `reviewedAt`, `sourceSha`,
current `deployedSha`, inspected `predecessorEvidenceSha256`, `firstSlot`
(exactly the completed prefix plus one), ordered `windows` for remaining
original blocks, fresh `privatePreflight`, and `reports` with canonical absolute
`original` and `continuation` report paths. It requires true
`noUnrecordedAttempts`, `remainingNeverSubmitted`, `pauseBetweenCompletedSlots`,
and `analysisPolicy: original_screening_rules_with_disclosed_interruptions`.
Keep owner IDs, session data and private hosted configuration out of these
files. Reports must be private regular single-link JSON files, at most 8 MiB,
with private canonical parents.

After review, preparation is offline:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=.,ORIGINAL_PARENT,REVIEW,ORIGINAL_REPORT,CONTINUATION_REPORT \
  --allow-run=git --allow-write=ORIGINAL.continuation.successor \
  services/supabase/scripts/manage_audio_prompt_successor.ts \
  prepare ORIGINAL REVIEW
```

Use `claim ORIGINAL SLOT ACTIVATION WITNESS`, `admit ORIGINAL SLOT`, and
`close ORIGINAL BLOCK CLEANUP` with the same denied network/environment,
parent/report/source read grants and successor-only write grant. Claim and admit
need `--allow-run=git`; close needs only the successor and cleanup receipt. The
observer writes one new
`ORIGINAL.continuation.successor/observations/slot-NN.jsonl`. Wait for
readiness, tap Identify once, retain the complete 120-second window and admit it
before the next claim. Activation receipts bind the current reviewed controller
and deployment plus the unchanged runtime/plan. Admission also binds app and
pricing. Cleanup verifies absence and binds the window/bundle when those fields
are present; a later recovery controller is allowed. Each activation remains at
most two hours. Verified cleanup precedes the next block.

`report ORIGINAL OUTPUT_PARENT/report.json` also needs read/write access to a
canonical private output parent outside all three packets. It creates a new
report and refuses overwrite. The report distinguishes original, continuation
and successor rows/controls, and requires all 36 unique first attempts, required
known timing/cost/score and verified cleanup before screening. It neither scores
visible labels nor authorizes promotion. Retain bounded UI labels separately,
disclose both interruptions, and follow the
[successor authorization procedure](../../../../docs/backend-and-data/06-supabase-deployment-runbook.md#continue-after-a-second-between-trial-expiry).

### Offline audio uncertainty prompt preparation

[The six-clip prompt design](../../../../docs/rfcs/identification-audio-uncertainty-comparison-plan-2026-09-24.md)
has a separate offline builder:
[prepare_audio_uncertainty_comparison.ts](../prepare_audio_uncertainty_comparison.ts).
It accepts the two previously reviewed private source packets and a fresh output
directory. Network and environment permissions must be denied. The builder has
no provider executor or client prompt selector. Slice 2 adds a separately gated
runtime registry arm and Debug client handle; the new lane remains default-off
behind its separate activation controller.

[Audio prompt comparison](./audioPromptComparison.ts) pins the complete design,
inserts its exact species-evidence block into the resolved current V2
instruction, and uses the production processor, Pro policy and Gemini request
projection. Both arms share the processed WAV and fixed context. A
native-request comparison removes only the system instruction and requires
equality. The actual processed WAV must be canonical mono PCM16 at 16 kHz and
0.5–15 seconds before its format is recorded.

[Frozen packet loading](./frozenAudioPacket.ts) verifies the design's completed
freeze, corpus, taxonomy, selected media, eligibility, source and reference
records. It requires current owner-reviewed retention, existing Gemini
evaluation permission, the exact selected groups/references, one bounded
standalone WAV and no observation text or source context. Private canonical
roots and regular single-link files are required. Historical outcomes and
response prose are not loaded.

Replace all uppercase path placeholders with absolute paths. `OUTPUT_PARENT`
must exist and `OUTPUT` must be its new child; these paths must have no symlink
aliases. Parent read access permits the directory sync after exclusive creation.

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=.,SOURCE_V2,SOURCE_VISIBLE,OUTPUT_PARENT \
  --allow-run=git --allow-write=OUTPUT \
  services/supabase/scripts/prepare_audio_uncertainty_comparison.ts \
  SOURCE_V2 SOURCE_VISIBLE OUTPUT
```

The private `preparation.json` contains only source/provenance/request/policy
hashes, settings, implementation identity and the 36 reviewed assignments.
`freeze.json` records both its exact-file and canonical-JSON hashes. Source and
completed packets stay immutable. Preparation slot handles use a new
`audio-uncertainty-v1` namespace; they are not reserved scan identities or live
authorization. Scan IDs, app/bundle/private owner/window bindings and live
dispatch remain unset. Repeats preserve request hashes and receive distinct
assignment hashes. Neither existing RunSpecs nor the historical DSP lane can
consume this artifact. Any implementation or binding change requires a new
preparation; formatting an evidence copy preserves its canonical digest but
changes its exact-file digest.

### Offline audio comparison preparation

`prepare_audio_preprocessing_comparison.ts` verifies the frozen six-audio
packet's manifest and source hashes, then prepares exactly two arms per case:
`audio-linear-full-windows-v1` (historical floor-window trimming and linear
resampling) and `audio-sinc-partial-tail-v1` (the current multimodal audio
helper). Both transforms now belong to the route-private
`functions/identify-multimodal/comparison/` owner, with canonical standalone
mono PCM16 44.1 kHz inputs bounded to 15 seconds before processing. The
historical transform is used only by offline preparation and the default-off,
server-owned comparison gate. Ordinary identification and evaluator runs retain
current DSP.

Both arms use `audio-minimal-v1` synthetic context and the current Gemini Pro
request builders. A non-audio request hash must match within each pair. The
preparation records source, processed-WAV, provider-request, policy and
confidence hashes, output format/length, model/prompt/schema/generation and the
complete local implementation fingerprint. It retains no raw media or request
bodies. Twelve prospective first-attempt assignments alternate the first arm by
case; there are no selective retries. A changed implementation requires a new
preparation and review, even if its arm name is unchanged.

From the repository root, use a new private destination (replace `SOURCE` and
`OUTPUT` with absolute paths):

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=.,SOURCE,OUTPUT --allow-run=git --allow-write=OUTPUT \
  services/supabase/scripts/prepare_audio_preprocessing_comparison.ts SOURCE OUTPUT
```

This emits `preparation.json` and a canonical-JSON digest in `freeze.json` using
exclusive creation and private permissions. It refuses changed source media or
an existing destination. It reads no provider key and enables no live dispatch.
The preparation version is intentionally incompatible with evaluator RunSpecs.
Ordinary app requests run the deployed processing policy. The
[server assignment slice](../../../../docs/rfcs/identification-audio-comparison-assignment-2026-09-23.md)
adds disabled request/media binding and a fresh durable proof header. The
[app integration](../../../../docs/rfcs/identification-audio-comparison-app-integration-2026-09-23.md)
adds generated Debug simulator slots, verified request bytes, compact native
receipt/finalization/first-draw proofs and offline complete-window admission.
The configuration remains unset; no new experiment is recorded by
implementation. V2 app `contextProfile` attests only fixed context on the
initial active foreground HTTP response. `requireFixedAudioMeasurement` enforces
that profile and reviewed execution identities; it is not a per-case or
formal-qualification gate. See the
[preparation record](../../../../docs/rfcs/identification-audio-comparison-provenance-2026-09-23.md).

The runtime comparison table is generated only from the previously frozen
preparation. To verify or regenerate it offline:

```bash
deno run --frozen --no-prompt --deny-net --deny-env \
  --config services/supabase/functions/deno.json \
  --allow-read=docs,services/supabase/functions/identify-multimodal/comparison,apps/ios/Merian/Core/Network/Inference \
  services/supabase/scripts/generate_audio_comparison_plan.ts --check
```

For generation, use `--write` and grant write access only to
`services/supabase/functions/identify-multimodal/comparison/plan.ts` and
`apps/ios/Merian/Core/Network/Inference/DebugAudioComparisonPlan.generated.swift`.
The native table derives scan UUIDs with the server's implementation; both
artifacts are checked by the normal tooling gate. Regenerate the normal
identification deployment identity after runtime edits. Neither command enables
configuration or authorizes live dispatch. Existing frozen preparations remain
immutable; record the new runtime fingerprint separately.

`admit_audio_comparison_observation.ts --observation OBSERVATION --expected EXPECTED
--output OUTPUT`
is an offline-only gate for the passive observer's new observation-v2 JSONL.
EXPECTED contains the slot, all five built-app identity fields and reviewed
backend bundle hash. OUTPUT must be new; it is created mode 0600 and includes
the source file hash. The gate requires one fresh fixed-context Pro response and
all three native proof events joined by the hash of the exact measurement JSON
bytes. A complete bounded window and exact draw timing are required;
malformed/duplicate/missing proof, extra HTTP attempts and old files are
rejected. Confidence and biological status are retained without species names or
provider prose. Admission does not score accuracy or authorize a run. The
integration record provides the command and evidence limitations.

`scoreEvaluation(corpus, predictions, { profile, split, inputGroup?, caseIds? })`
returns the typed `identification_scores_v1` report. Supply predictions for one
profile and split. Unknown cases, foreign splits, duplicate attempts, malformed
scores, and extra raw-output fields fail. Missing cases become `unattempted`;
repeated attempts cannot inflate sample size. The optional input-group filter
produces group-specific scores from that same split. The aggregate is unweighted
across cases and is not an estimate of production traffic.

The scorer expects normalized identities mapped to the frozen taxonomy version.
A named prediction with `taxon: null` means unresolved mapping and still counts
as an offered, unverified answer. `normalizeEvaluationDraft` parses an unknown
provider draft through the same production domain rules, before dictionary
hydration. It returns domain data, audio disposition, client candidates/life
stage, and in-memory diagnostics; it is **not** a durable prediction record.
`projectOutcome` discards prose/diagnostics and retains bounded IDs, decisions,
confidence, candidate presence, numeric usage and durations. A frozen taxonomy
map accepts exact names/synonyms ignoring case; there are no fuzzy or live
lookups. Genus/family answers earn credit only when expressly allowed at that
rank; a guessed species cannot earn credit from an allowed ancestor.

The normalization bridge requires the loader to verify that every declared asset
reached the actual request. It may not silently drop failed images or audio.
Device region and month do not establish the GPS or semantic location used by
the current invasive-status rule. No coordinates or identity enter the
normalizer. Server candidate presence is before dictionary hydration and is not
the final iOS candidate-review visibility decision.

Version 1 evaluates ranks from kingdom through species. Finer reference or
prediction ranks require an explicit mapping to an approved species identity
before admission; this contract does not silently infer taxonomy ancestry or
exclude finer-rank cases from the species denominator.

False biological assertions are measured against known non-biological subjects
and synthetic human-only cases. Indeterminate subjects have a separate
unsupported-biological-assertion rate: insufficient reference evidence must not
be presented as proof that a biological classification is factually false. Named
guesses on these cases still count in offered precision, specificity, and
confident-error metrics.

Every report has `verdict: measurement_only`, an explicit synthetic/reference
evidence kind, and complete/incomplete status. A complete report can contain
only failures; it is not a passing result. The original pure point-score object
retains `performance: not_measured` and `intervals: not_computed`. The
run-report wrapper separately supplies timings, cost estimates and confidence
intervals from durable records. Compatibility and paired comparisons are
implemented; qualification decisions and numerical acceptance criteria remain
Slice 5.

## Curation rubric and intake

Use the
[pilot collection packet](../../../../docs/development-guides/20-identification-evaluation-pilot.md)
for the proposed 60-slot coverage plan and blank case/reviewer forms. Completed
forms stay outside Git; pending intake records are not approved corpus JSON.

The
[solo phone/computer workflow](../../../../docs/development-guides/20-identification-evaluation-pilot.md#start-here-when-you-are-working-alone)
supports collecting examples and checking the app without independent reviewers.
Its records can now enter the separate exploratory mode described below, with
provisional or absent references and actual eligibility review. They cannot be
passed as independently reviewed or synthetic evidence. The formal corpus and
stage requirements below still apply to independently reviewed evaluation.

**Real-corpus progress: 0 of 60 development groups; 0 of 240 held-out groups.**
The fixtures below are not reviewed biological examples and do not count toward
these targets. Product and a biological reference reviewer own collection;
Backend owns format and preparation checks.

1. Create the working corpus outside Git in controlled storage. Assign opaque
   case/group IDs (`c0001`, `g0001`) and asset IDs (`a0001`). Put all views,
   frames, audio, and derived descriptions of one observation in one group.
   Version 1 admits one primary case per group. Preserve source provenance in a
   controlled curation record, referenced by an opaque token.
2. Establish that source rights cover sending the material to Gemini for this
   evaluation purpose. Exclude production observation exports, identifiable
   human imagery/speech, personal information, precise coordinates, credentials,
   and revealing metadata. Evaluation rights do not grant model-training rights.
3. Record observable evidence without copying taxonomy, answer-bearing
   filenames, or reference notes into prompts. Prepared asset paths have the
   exact form `assets/a0001.webp`, `.jpg`, `.png`, or `.wav`. WebP matches the
   current primary route's default. All visuals within a case use one MIME type,
   preserving that route's single image-MIME parameter. Preserve supplied frame
   indexes and clip/audio relationships. A partial frame set is allowed when its
   declared frame count and retained indexes remain honest; included audio
   cannot vanish.
4. Obtain two independent reviews, identified by different opaque role IDs
   (`r0001`, `r0002`). Verify the reference against independent evidence and
   record a reference-record token. Use `agreed` or document adjudication as
   `resolved`. Model output, a name lookup, or unverified user confirmation
   cannot establish truth. Do not lower the review requirement to fill a quota.
5. Label subject class and resolution separately. A biological subject can be
   unresolved. For named results, record the most specific supported rank and
   every acceptable canonical taxon/rank pair. For unresolved results, use a
   null supported rank and an empty acceptable-taxa list. Known source identity
   must not force species-level certainty from insufficient supplied evidence.
6. Review exact and near duplicates before splitting. The validator rejects
   repeated case/group IDs, cross-split groups, reused media hashes across
   groups, and repeated nonempty normalized observation text across any input
   groups. Absent text is not a duplicate; identical generic context on
   independent observations is conservatively rejected and should be omitted
   when it adds no evidence. The validator cannot detect all near duplicates or
   verify that different reviewer IDs represent different people.
7. Assemble ten development cases per input group, covering clear positives,
   lookalikes, degraded evidence, appropriate unknowns, and relevant negatives.
   Cover disagreement/incidental organisms in combined-media groups. Freeze the
   detailed coverage matrix after the pilot, then curate forty held-out groups
   per input group without tuning against their answers.
8. Record corpus approval, accountable role, retention date,
   taxonomy/preparation versions, split seed and membership. Retain the exact
   corpus digest. Any label, evidence, split, or curation change produces a new
   digest and report version; retain prior reports when corrections require
   consistent rescoring.

A reference corpus requires `approval` and `curation.kind: reviewed` on every
case, approved Gemini-evaluation rights, exclusion/review assertions, distinct
reviewer references, and resolved labels. Synthetic corpora require null
approval and synthetic curation. These fields are assertions for a controlled
intake, not cryptographic proof of permission, reviewer identity, or biological
correctness. Passing validation does not authorize a live run. OpenAI
additionally requires a recipient-specific permission record bound to the exact
corpus and selected cases; see the provider guide above. For real execution, the
implemented runner also requires asset preflight, reviewed processor/account
readiness, an approved digest and budget, durable dispatch, and explicit live
selection. The user must authorize the concrete paid run.

## Automated exploratory runs

This mode supports a solo owner before a reviewed biological corpus is
available. It uses `identification_exploratory_corpus_v1`, not the formal corpus
version. `kind` is `exploratory`; `evidenceOrigin` is `real` or `synthetic`.
There are one to twelve unique development groups. Each case contains the
existing strict `input`, a `provisionalReference` (the existing reference shape
or null), and separate `curation`. Reference values and provenance never enter a
request.

For real evidence, `eligibility` identifies a record token, opaque reviewer ID,
`reviewerKind: owner | automated`, and retention date. Each case requires
`curation.kind: eligibility_reviewed`, source and optional reference-record
references, `permission: gemini_evaluation`, and completed rights, personal-data
exclusion and near-duplicate assertions. A reference record is present exactly
when the provisional reference is non-null. Review the actual decoded media and
source permission before asserting these checks. One automated eligibility
review does not create independently verified biological truth. Synthetic
records instead require null eligibility and synthetic curation.

A legacy Gemini run uses `identification_exploratory_run_spec_v1`,
`stage: exploratory`, all selected corpus groups, one repeat, and both existing
Gemini profiles. The maximum is twelve groups and twenty-four calls. It retains
every live gate below: reviewed paid project/key, explicit processor readiness,
fresh reviewed pricing, retention, exact immutable inputs/source, a positive
authorized USD budget, durable claims and no automatic retry of unknown
executions. Synthetic evidence cannot run live, and real evidence cannot be
executed by the offline fixture transport. The formal corpus/scorer and its
two-reviewer requirement are unchanged.

Use the same permissions as the offline example below:

```bash
# Create and execute an invented exploratory experiment in a fresh directory.
deno run --frozen --no-prompt --deny-net --deny-env \
  --allow-read="$PWD,$evaluation_parent" --allow-write="$evaluation_parent" \
  --allow-run=git --config services/supabase/functions/deno.json \
  services/supabase/scripts/evaluate_identification.ts demo-exploratory "$evaluation_parent/exploratory"

# Check a supplied corpus, taxonomy and prepared assets without inference.
deno run --frozen --no-prompt --deny-net --deny-env \
  --allow-read="$PWD,$evaluation_parent" --allow-write="$evaluation_parent" \
  --allow-run=git --config services/supabase/functions/deno.json \
  services/supabase/scripts/evaluate_identification.ts preflight "$evaluation_parent/exploratory"
```

First initialize the private `evaluation_parent` with the `mktemp` commands
below. Preflight writes `preflight.json`: hashes, covered groups, profile
assignments and planned call count. A current `pricing.json` additionally
supplies conservative reservations; absent pricing leaves cost unknown. It never
creates dispatch claims or authorizes a paid run. Configure the real corpus's
`spec.json` and `readiness.json` under the live requirements before selecting
`--live`.

`report DIRECTORY RUN_ID` selects `identification_exploratory_report_v1` for
these records. All outcomes contribute to operational counts; null references
are excluded from every provisional quality denominator. A confident name on an
unverified example is not automatically correct or wrong. Every report states
zero independently reviewed labels, `measurement_only`, untested input groups,
and provisional evidence status. Unknown/unattempted calls leave the report
incomplete. Synthetic runs additionally state `synthetic_mechanics_only` and
supply no measured Gemini quality, latency or spend. Formal reporting and paired
`compare` reject exploratory corpora. Keep source/media and detailed curation
outside Git; retain sanitized run summaries with their exact hashes.

## Hand-worked fixture expectations

Each input group appears twice. All twelve cases are development fixtures; there
is deliberately no synthetic held-out accuracy claim.

| Cases           | Reference and normalized outcome                                                               |
| --------------- | ---------------------------------------------------------------------------------------------- |
| 1, 4            | Correct species, scores 0.99 and 0.90.                                                         |
| 2               | Genus-only evidence receives an unsupported species answer at 0.99.                            |
| 3, 5, 7, 11, 12 | Refusal, invalid output, operational failure, unknown execution, and unattempted respectively. |
| 6               | Non-biological evidence receives a biological species answer at 0.99.                          |
| 8               | Expected-unresolved biology receives a named species at 0.97.                                  |
| 9, 10           | Appropriate unresolved biological and non-biological outcomes.                                 |

For Flash, `N = 12`, biological cases `B = 10`, species-answerable cases
`S = 7`. There are five named answers and two correct identities:

| Metric                                                | Expected value                                     |
| ----------------------------------------------------- | -------------------------------------------------- |
| Exact species correctness                             | 2 / 7                                              |
| Offered-answer precision                              | 2 / 5                                              |
| Biological answer coverage / correct-answer yield     | 4 / 10 and 2 / 10                                  |
| Appropriate unresolved outcomes                       | 2 / 4; provider failure is not uncertainty credit. |
| False biological assertions on negatives              | 1 / 2                                              |
| Strong errors, all cases / Strong named cases         | 3 / 12 and 3 / 4                                   |
| Diagnostic errors, all cases / diagnostic named cases | 2 / 12 and 2 / 3                                   |
| Strong reliability / mean reported score              | 1 / 4 and 0.985                                    |

Pro's current Strong threshold also includes case 4: Strong errors become 3 / 5
and Strong correctness 2 / 5. This tests policy interpretation, not a measured
difference between Gemini models. Diagnostic is a reported subset of Strong, not
a fourth disjoint bin. Empty denominators return `not_estimable` with a null
value. The unattempted case makes both reports incomplete.

## Local CLI and artifacts

Use Deno `2.9.4` and the existing frozen dependency graph. A private directory
outside Git holds `corpus.json`, `taxonomy.json`, `spec.json`, and `assets/`.
Offline runs also need `fixtures.json` bound to the synthetic corpus digest.
These files are parsed strictly; unknown fields fail. Root and run directories
must be private (mode 0700) on a local filesystem supporting exclusive file
locks and file/directory fsync. A failed flush blocks dispatch. Do not use a
shared or cloud-synchronized run directory.

Create an invented demo from the repository root:

```bash
evaluation_parent="$(mktemp -d "${TMPDIR:-/tmp}/merian-evaluation.XXXXXX")"
evaluation_parent="$(cd -- "$evaluation_parent" && pwd -P)"
deno run --frozen --no-prompt --deny-net --deny-env \
  --allow-read="$PWD,$evaluation_parent" --allow-write="$evaluation_parent" \
  --allow-run=git --config services/supabase/functions/deno.json \
  services/supabase/scripts/evaluate_identification.ts demo "$evaluation_parent/demo"
```

The default command is `offline DIRECTORY` (or simply `DIRECTORY`). `demo`
requires a fresh directory and produces deliberately wrong/refused/failed and
uncertain synthetic cases as well as valid results. Its incomplete verdict is
intentional. `report DIRECTORY RUN_ID` rebuilds artifacts from saved records,
corpus and frozen taxonomy, without media loading, a key or inference. Use the
same denied network/environment flags; report generation needs no Git process.

`runs/RUN_ID/` contains an immutable `manifest.json`, permanent `.lock` inode,
`claims/KEY.json`, terminal `results/KEY.json`, `summary.json`, and `report.md`.
The latter two are deterministic for the same saved records. Never delete claims
to retry a case. A claimed attempt without a result becomes `unknown_execution`
and stops the run; even a crash between claim and invocation spends that
attempt. A changed spec, source digest, pricing, corpus or request cannot resume
the same run. A new run and explicit spend decision are required to retry
uncertainty.

The manifest records both full-schedule reservations and the approved
call/budget limits through its assignments/spec. Source identity covers commit,
dirty state, the functions/scripts TypeScript/config/lock/shell graph and exact
SDK version. Live rates and token ceilings are supplied through reviewed files,
never inferred from code defaults. Each call reserves the full reviewed model
input/output ceiling, including thinking, at worst-case modality rates. This
deliberately conservative bound can stop before a small budget is exhausted.
Usage estimates also use worst-case rates without a cache discount;
missing/contradictory usage stops further calls. Known components are estimates,
not invoice lower bounds.

`compare DIRECTORY LEFT_RUN RIGHT_RUN LEFT_PROFILE RIGHT_PROFILE` is an explicit
assignment comparison. Both runs must match corpus, selected groups, split,
stage, seed/order, taxonomy, scorer, preparation, measurement boundary and
source. Same-profile configuration/request drift and unexplained returned models
fail. Different named profiles are an explicit opt-in and their complete
differences are listed. Incomplete/unknown runs cannot compare. Missing usage
may leave quality measurable but blocks cost comparability. Every verdict
remains `measurement_only`; numerical qualification criteria belong to Slice 5.

Formal reports include fixed-population denominators, every failure/unattempted
case, confidence reliability, subject/resolution matrices, and scoring flags.
Proportions use Wilson 95% intervals. Paired differences use 3,000 seeded
observation-group bootstrap draws (one case per group), nearest-rank percentile
bounds and seed `20260922`. Any zero-denominator draw makes that interval
`not_estimable`. Repeats stay separate. Timings exclude upload, hydration and
app rendering; the adapter does not distinguish timeout causes from other
unknown executions. Offline durations and costs supply no live performance
evidence.

## Future explicitly approved Gemini live use

The following processor-review and SDK rules apply to Gemini. OpenAI uses the
[alternative-provider contract](../../../../docs/development-guides/22-alternative-identification-provider.md),
which has its own recipient-specific review.

Paid execution requires `--live DIRECTORY` or the separately controlled
`--experiment-live DIRECTORY RUN_ID`. Before using either, approve an eligible
real reference or exploratory corpus, its exact digest and selected profiles,
the actual paid project/key, call cap and USD budget. Standalone `spec.json` or
the controller's `experiment.json` binds these limits. `readiness.json` (or
`approvals/<runId>.json` in a controller packet) binds that corpus to opaque
project/credential/review references, a SHA-256 credential fingerprint,
review/expiry dates, paid service eligibility and reviewed terms, purpose, data
use, regional/subprocessor and retention/abuse-log treatment. This attestation
is not a programmatic proof of the vendor's billing settings. `pricing.json`
must be at most seven days old and cover both exact models, synchronous USD
rates across modalities/context tiers, thinking and reviewed model token
ceilings. The spec binds both files by canonical digest. Their parsers in
`runContracts.ts` are the authoritative field definitions.

The legacy `evaluation_processor_v1` record remains dedicated-project-only. New
`evaluation_gemini_processor_v1` records require `provider: gemini`, an explicit
Boolean `dedicatedEvaluationProject`, and
`inputPermission: {provider, corpusDigest, caseIds, reviewRef, approved}`. Use
`false` for an explicitly reviewed shared paid application project. The
permission must name Gemini, approve the exact corpus and selected case set, and
have `approved: true`. Paid-service, actual-credential fingerprint, source
retention and review/expiry checks still apply before every invocation. Neither
Gemini record authorizes OpenAI. Review references are operator assertions, not
independent proof of account settings or rights. A shared project's other
traffic consumes the same vendor limits; the evaluator accounts only for its own
calls. This local contract does not enable production routing or authorize
access to a hosted secret.

Read the reviewed key only from `GEMINI_PAID_API_KEY`; never put it in a command
argument or file. Grant only `generativelanguage.googleapis.com:443` for
network, the controlled directory/repository for reads, controlled directory for
writes, and Git for source identity. Do not grant broad environment or network
access. Explicitly deny environment access to `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`, `R2_ACCESS_KEY_ID` and
`GOOGLE_APPLICATION_CREDENTIALS`. Besides the key, the pinned Node SDK needs the
exact `SDK_ENVIRONMENT` allowlist in `admission.ts` to be readable but
**unset**; it covers backend/base-URL/key overrides, debug logging and WebSocket
optional module switches. The runner checks these before SDK import. Preserve
`--no-prompt` and the frozen config. No live command is implied by local
testing.

Working identification in the simulator establishes access through the ordinary
authenticated Supabase app path. Its provider key stays on the backend; the
app's scan allowance does not give this local runner a Gemini credential or a
USD run budget. Connect the reviewed paid project/key to the local runner and
retain any already granted user spend authorization. Do not extract simulator
session state or falsely mark a shared application project as dedicated.

Live preparation and each dispatch recheck the actual key, corpus and readiness
validity. All assets preflight before the first call, and request hashes are
rechecked immediately before dispatch. The CLI has no alternative adapter/host
flag and live mode rejects test dependency injection. It performs sequential,
standard synchronous calls with production settings and no retries. It stops on
every operational failure because the adapter combines 400 and 429 outcomes;
this stricter rule ensures rate-limit/authentication failures cannot be retried.
Unknown execution, model drift, missing usage, or the call/spend guard also stop
the run. Budget changes require a new spec/run rather than changing a resume.

## Verification and next slice

From the repository root, the focused tests need no network, environment,
filesystem, or subprocess permission:

```bash
deno test --frozen --config services/supabase/functions/deno.json \
  --deny-net --deny-env \
  services/supabase/scripts/identification_evaluation_contract_test.ts \
  services/supabase/scripts/identification_evaluation_scoring_test.ts \
  services/supabase/scripts/identification_evaluation_normalization_test.ts \
  services/supabase/scripts/identification_evaluation_run_contract_test.ts \
  services/supabase/functions/_shared/identify/normalizeIdentification_test.ts
```

Tests live at the scripts root so the existing `make test-supabase-tooling`
discovery includes them and type-checks their complete imported module graph.
Keep future tests discoverable; nested `*_test.ts` files alone are not selected
by that shell gate. Recursive repository formatting and lint include this
folder.

The tooling gate additionally runs `identification_evaluation_runner_test.ts` in
an isolated private temporary directory with network/environment denied. It
grants that directory read/write and repository reads, with `git` for the actual
CLI's source fingerprint plus `deno` and `ln` subprocesses to test cross-process
locks and rejected symlinks. Crash boundaries, immutable resume, complete media,
caps, sanitized artifacts, report regeneration and comparison are exercised
there. The main tooling suite also explicitly denies network and environment
access.

The first paid OpenAI exploratory pilot is recorded above. Formal Slice 4 still
requires the reviewed 60-group development corpus, exact processor/pricing
records and an explicitly authorized bounded run. Held-out evaluation and
decision qualification remain later work. Neither synthetic results nor the
small provisional pilot establish a provider accuracy, cost or latency win.
