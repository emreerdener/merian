# Photo identification evidence and rank consistency

Date: 2026-09-28

Status: The separately approved
[corrected comparison](identification-sol-rank-comparison-results-2026-09-29.md)
completed all eighteen calls and six challenge pairs. The candidate improved
broader-rank behavior but made two concrete visual-evidence errors, so it is not
qualified for promotion. Retain the unchanged Sol profile for Free and Pro. The
[first stopped run and reference adjudication](identification-sol-rank-screen-results-2026-09-29.md)
remain intact. Production rank handling and confidence calibration are
unfinished. The next slice is offline rank/resolution contract design; preserve
the explanation format and Strong / Possible / Weak labels.

## Problem and intended behavior

The completed
[Luna/Sol comparison](identification-luna-sol-candidate-results-2026-09-28.md)
found unsupported species names even when explanations acknowledged missing
diagnostic evidence. A plausible species with a disclaimer still presents that
species as the main identification. We want the primary scientific name, common
name, candidates and explanation to agree about what the image establishes.

For example, if visible traits support a plant genus but cannot distinguish its
species, return the genus and a matching group name. Explain the observed traits
and the missing evidence in the existing explanation format. A missing or
obscured trait is not evidence that the trait is absent. Do not solve this by
lowering every result's specificity: a well-supported species should remain a
species identification.

This addresses accuracy and consistency. It does not establish confidence
thresholds, qualify Luna, or prove that an upgraded model deserves a stronger
badge. Keep Strong / Possible / Weak, existing policy versions and explanation
length and structure. Backend admission continues to assign providers and models
by input and entitlement; this introduces no user provider picker.

## Why a production prompt change needs more work

OpenAI photos reuse the shared visual instruction through
`buildOpenAIPhotoRequestParameters` → `buildOpenAIRequestParameters` →
`getSystemInstruction`. Its biological rules currently require a binomial,
permit genus only when species determination is impossible, require species
identification for preserved specimens, and require two alternative species.
These rules need a coherent override in an OpenAI evaluation candidate. Changing
the shared instruction directly would also affect other profiles.

The executable model schema and normalizer accept genus and family strings
already. That is not an end-to-end rank contract. In
`identify-multimodal/index.ts`, `isIdentifiedBio` treats a biological result
with any scientific name as identified and allows species dictionary hydration
and enrichment. iOS likewise presents non-placeholder names as resolved. Neither
path has an explicit primary rank to distinguish a genus from a species.

Therefore the first prompt candidate stays in direct evaluation. Before any
production activation, introduce explicit primary rank/resolution semantics
through the executable contract, normalization, generated DTOs, storage,
historical/retry responses and presentation. Gate species dictionary hydration,
species IDs and species-specific enrichment on a supported species result.
Review broader-rank enrichment separately. Do not infer rank by counting words,
and do not rewrite historical species records from their spelling. The exact
nullable/version compatibility and migration design belongs to that later
cross-surface contract slice.

## Slice 1: measurement foundation — implemented

`audit_photo_taxonomy.ts` is a read-only, network/environment-denied command. It
checks a reviewed v2 catalog against an exploratory photo corpus, using the
resolver's identical Unicode NFC, whitespace and case normalization. It detects
duplicate canonical names, canonical/synonym collisions, shared synonyms,
missing IDs, rank mismatches and missing reference labels. It emits bounded IDs,
ranks, counts and input digests, with explicit truncation flags; it never emits
catalog names, observations or explanations. Exit 0 means catalog consistency
only, 2 means issues were found, and 1 means invalid input or an unavailable
audit. Even a clear report grants no dispatch or reference review.

The read-only audit of the completed candidate packet found **two** duplicate
canonical identities among 96 taxa, with no broken reference IDs:

| Rank    | IDs sharing a canonical name               |
| ------- | ------------------------------------------ |
| Species | `col-6qb84`, `species-limenitis-archippus` |
| Genus   | `col-92dbx`, `genus-limenitis`             |

The genus collision is additional preparation evidence; it does not revise any
completed prediction or score. The inspected corpus digest is
`ea644e055bbbdaffa3a5d1aedbd91e184d009985774810f9c036579c464775e7` and catalog
digest is `ce346223dcea755bf3018f0f9c6db422c953c4572b35ffa0cb602b6bb3ddd930`.

`photo_model_attempt_v2` adds bounded primary mapping status (`matched`,
`ambiguous`, `unmapped`, `not_applicable`) and canonical/synonym match category.
Its pure projection preserves the existing normalized prediction, timings,
safety and cost fields without saving returned taxon names or prose. It requires
a reviewed v2 catalog because legacy name lists do not distinguish canonical
names from synonyms. The parser rejects impossible status/identity combinations
and extra fields. The existing measured-reference scorer can now distinguish
mapping gaps from identity disagreement or valid abstention.

Historical photo-model plans, runners and journals still accept and emit only
`photo_model_attempt_v1`. The new Sol controller below explicitly binds v2;
there is no automatic journal upgrade. Do not reconstruct a missing mapping from
an old null taxon, modify old artifacts or rerun an old plan. The new controller
must bind v2 explicitly to a new manifest/approval before using it.

## Slice 2: corrected packet and isolated Sol candidate — prepared offline

The offline candidate is `openai_photo_sol_rank_limits_low_v1`, bound to
`openai_sol_rank_evaluation_v1`, prompt `openai_identify_vision_rank_limits_v1`
and schema identity `merian_openai_identify_rank_v1`. Its pure implementation
now lives in `_shared/ai/openaiSolRank.ts`, with a stable script re-export.
`createOpenAISolRankEvaluationAdapter` reuses the bounded transport and
exact-model/native-moderation decoder. Production and historical live profile
constructors reject it; only the new Sol controller accepts this candidate.

The candidate replaces conflicting biological instructions and four schema field
descriptions: scientific name, common name, candidates and distinguishing
feature. Schema descriptions previously required a binomial and exactly two
alternative species even if a prompt allowed broader ranks. The candidate now
keeps these sources of guidance consistent:

- Keep a species name when diagnostic evidence distinguishes that species.
- Use the supported genus or family and matching group name when that is the
  limit; use null when none of those ranks is supportable.
- Allow zero to two supported alternatives at the supported rank. Do not invent
  names to fill the array.
- Treat unseen features as unknown, not absent. A disclaimer, lower confidence
  score, seasonal expectation or regional popularity cannot justify a finer
  primary name.

Only instructions, descriptive schema guidance and the schema identity change.
JSON keys, types, bounds, required fields and strict decoding remain identical.
The existing 1–3 sentence explanation definition, confidence guidance, mineral
rules, moderation identity, Sol model, low reasoning effort, high image detail,
8,192-token output ceiling and request controls remain fixed. Each expected
instruction/description anchor must match; drift fails preparation.

The candidate instruction SHA-256 is
`2ce09781a640db6909494740e7a25cbdf8d53f8f944f9b524c3459dd69472f77`. The complete
output-format descriptor digest is
`630cc0447b70d10a9d6de25105a35c9d3ded73a124649a0d177cb348a69364a4`. Both are
pinned in deterministic tests. These identities describe an experiment, not
measured quality or a production promotion.

`prepare_sol_rank_candidate.ts` creates a new private directory from whitelisted
source corpus, taxonomy, fact cards and media. It validates the old plan's input
digests without copying its plan, pricing, approval, key material or journals.
It rejects existing destinations, nested source/destination paths, symlinks,
stale facts and changed media. The completion receipt is written last and
contains only bounded identities, digests and preparation status. It never
stores request bodies or grants live authority. See the
[operator procedure](../development-guides/22-alternative-identification-provider.md#offline-photo-catalog-audit-and-rank-consistency).

The prepared twelve-case packet retains every no-description photo and fact card
from the completed comparison. The explicit `photo_taxonomy_remap_v1` merges
`col-6qb84` into `species-limenitis-archippus` and `col-92dbx` into
`genus-limenitis`. Both pairs have identical normalized canonical names and
ranks. Synonyms are retained. The helper rewrites and deduplicates references
where needed while preserving their supported rank; this packet already used the
retained IDs, so no reference ID changed.

The resulting catalog has **94 taxa, zero name collisions, zero broken
references and zero cases missing provisional references**. The four source JSON
files and all twelve media files were checked unchanged after preparation. No
old score, journal or prediction was rewritten.

| Artifact       | New digest                                                         |
| -------------- | ------------------------------------------------------------------ |
| Corpus         | `fd5d0106756e32214bd57d2956cb1d66db7da3f2a3412589e6e1e5b88c85dc58` |
| Taxonomy       | `bb24ba63b0ec77c4faa29b22f33ba566d9683d33eaf438ecc9c115dd90e6b6a6` |
| Explicit remap | `ad1d690d707a23a4f264fdb1143d76705c90acb306d674f67d4b3d22c05ec430` |

This repairs duplicate identity bookkeeping only. Source labels and fact cards
remain provisional, the finite catalog can still miss valid alternatives, and
some biological distinctions remain unassessable. Resolve relevant gaps from
reviewed source evidence before live admission; record unresolved gaps rather
than inventing certainty. Do not add names from predictions after scoring.

The receipt binds twelve prepared cases and a proposed schedule of six candidate
screens plus six alternating Sol/candidate challenge pairs. It explicitly states
`dispatchAuthorized=false`, `liveControllerAvailable=false`,
`readyForLive=false` and `referenceReviewComplete=false`. A failed or incomplete
directory must not be reused as a completed packet. Luna's existing mineral
candidate remains unchanged; any subsequent Luna rank experiment needs its own
comparison.

OpenAI recommends representative evaluations around focused prompt changes;
family-level prompting guidance still requires validation on the chosen model
and workload. We retain the explicit Luna/Sol models and low reasoning effort to
isolate the instruction change. See the official
[optimization guidance](https://developers.openai.com/api/docs/guides/model-optimization)
and
[model guidance](https://developers.openai.com/api/docs/guides/latest-model).

## Slice 3: measure one model's change at a time — controller implemented

Prioritize Sol because it currently serves both tiers. Prepare the established
shape of six candidate regression screens, then six challenge pairs against the
unchanged Sol baseline, alternating pair order: at most eighteen calls, one
attempt each. Recalculate the conservative reservation with current rates; the
old $40 allowance and remaining allocation do not authorize this run. Only after
that decision should a separately bounded Luna comparison be considered.

The separate `sol_photo_rank_plan_v1`, `sol_photo_rank_approval_v1` and
`sol_photo_rank_run_v1` contracts bind v2 mapping records without broadening
historical plan/profile/record parsers. `sol-rank-plan.json` binds the original
preparation receipt, corrected corpus/catalog, unchanged fact cards, a new
reference-review record and reviewed prices. Preflight rebuilds every request
and requires exact agreement with the receipt before adding spending
reservations.

`sol-rank-reference-review.json` records assistant inspection of all twelve
inputs and their frozen facts. Source references remain provisional; this is
neither independent truth verification nor exhaustive taxonomy coverage. For the
prepared real packet, sunflower, columnar cactus and bark-only references retain
additional identity limits. A nonmatching identification on a limited reference
is unassessable unless the explanation review establishes a concrete failure. No
catalog names are added from model outputs.

The new approval binds the clean source commit/implementation digest, plan,
Naturebook credential fingerprint, budget, review delegation and at most a
24-hour window. It cannot inherit an old run's authority. Admission is checked
under the lock and before each claim. Fresh invalid admission creates no run
manifest; an existing invalid run retains a terminal configuration stop.

At the reviewed Sol tariff ceilings ($5/M input and $15/M output, including the
largest published long-context/cache-write rates), eighteen full-context
reservations plus the 10% regional allowance total **$106.383024**. The new plan
allows a **$110 ceiling**, subject to its bound approval. This is an
intentionally conservative full-context reservation, not predicted spend or a
price per photo. The unchanged output cap is 8,192 tokens. Prices must be
reviewed within seven days. See the official
[Sol pricing](https://developers.openai.com/api/docs/models/gpt-6-sol).

The sibling `sol-photo-rank-run/` journal exclusively claims each assignment,
writes its v2 result before transient assistant review, and retains a terminal
stop for failure, interruption or a missing review. No retry or continuation
mode exists. Record parsers and recalculated cost bounds validate resumed
artifacts; stopped or completed runs never issue additional requests.
`summary.json` keeps mapping/identity categories, review gaps, failed or
unreviewed results, per-phase denominators, paired provider time and known cost
bounds. Claims with no result retain their full reservation in `state.json`. A
complete run still does not qualify or activate anything.

Predeclare these decisions:

- All six regression screens must remain useful and correctly scoped. An actual
  wrong identity or explanation failure stops with `screen_failed`. Unmapped or
  ambiguous primary names, or nonmatching limited references, stop with
  `screen_unassessable`. Explanation claims marked `insufficient_reference` may
  pass the screen only when the primary identity agrees; they remain gaps and
  never count as passed explanation evidence.
- On assessable rank-limited challenges, the primary names and explanation must
  respect the reference rank. Unsupported specificity cannot be rescued by a
  disclaimer. Track failures on species-answerable cases so broad abstention
  cannot win by avoiding all identifications.
- Report identity coverage, ambiguity, unmapped names, disagreement, valid
  abstentions and explanation ratings separately, with denominators and gaps.
  Preserve partial/failed attempts. Keep timing, token usage and conservative
  cost separate from quality, and compare within the same model.
- Treat reused cases as development regression evidence. Do not call them an
  unseen benchmark or claim population accuracy or a Pro quality advantage.

Assistant review remains the operational approach requested by the owner. Where
available evidence cannot resolve a claim, record it as unassessable. No new
human review workflow is introduced by this plan. The hidden-key launcher uses
`--sol-rank-photo-live`; the offline command is `preflight-sol-rank-photo`. The
preparation receipt remains an immutable record with its original false
readiness flags; only the new plan/preflight/approval can admit execution.

### First live screen and source adjudication — 29 September

One request and review completed before `screen_failed`; none of the paired
challenges ran. The primary matched its provisional reference, but the
explanation rating depended on incomplete notes. The
[result and source audit](identification-sol-rank-screen-results-2026-09-29.md)
preserve the original stop and explain why it does not establish a model defect.
Four prospective fact cards distinguish publisher metadata, visual support and
reference gaps. No prompt change, resumed run, production promotion or
confidence qualification follows from this result. Prospective
`sol_photo_rank_summary_v2` reports raw reference comparisons and qualified
identity interpretations separately, preserving explanation failures and the
original v1 journal.

### Corrected comparison completed — 29 September

The fresh approval bound source `56f33e6b57bdbefad734fc04276c3a190e1b06d7`, the
corrected facts and the unchanged candidate requests. All eighteen calls and
reviews completed, with all six candidate screens clearing the existing screen
policy and all six challenge pairs retained. Four screens passed every
explanation criterion; two retained reference gaps.

The
[completed results](identification-sol-rank-comparison-results-2026-09-29.md)
record two candidate grounding/certainty failures, one control specificity
failure, and the separate mapping/reference gaps. The candidate's supported
genus behavior on three challenges does not outweigh those visual failures for
promotion. Keep the current Sol assignment and close this paid experiment. Total
usage-based conservative cost was $0.597531010; this is an upper estimate, not
an invoice or the $110 spending ceiling. The journal and summary were verified
offline without additional provider calls.

## Slice 4: production contract and model selection

The evaluated candidate is not eligible for production. Begin with an offline
design of rank/resolution semantics and compatibility; a new paid comparison
requires a separately scoped candidate and approval. Do not expand or repeat the
completed packet.

If a future prompt result warrants promotion, implement and verify the explicit
rank contract described above, including saved observations, retries,
older-client behavior and enrichment. Keep rollout and rollback tied to the
exact reviewed provider/model/prompt/schema/confidence profile. Production
activation is a separate operation; no future plan or successful offline test
changes today's Sol assignments. OpenAI audio evaluation follows the photo
decision as its own input and model comparison.

## Verification

Focused deterministic tests cover mapping statuses, rank retention, v1/v2
rejection, privacy projection, unsupported-specificity scoring, catalog
normalization/collisions, missing references and bounded audit output. The
isolated CLI test checks exit behavior and unchanged input bytes with writes,
network and environment denied. An independent contract review caught and
resolved legacy catalogs being accepted by the new mapping projection; a
regression preserves v1 alias matching while rejecting it for v2.

The complete tooling gate passed: 463 standard tests, 91 isolated evaluator
tests, both DTO suites (20 and 21 tests), generated-contract validation,
recursive script type checks and all shell suites. The Edge suite passed 2,171
tests with nine database-dependent tests ignored. Recursive functions/scripts
formatting and lint, changed Markdown formatting, all 102 Function config and
dependency graphs, local documentation links and diff whitespace also passed. No
live benchmark, iOS build, disposable-database run, migration or deployment is
part of this slice.

The subsequent Sol preparation slice adds six deterministic contract tests and
three isolated filesystem/CLI tests. These verify request parity and pinned
guidance, production binding rejection, synthetic
species/genus/family/unresolved normalization, exact remapping, source
preservation, private output permissions, no authority copying and rejected
drift/symlinks. An independent read-only review found no actionable issue. These
are software checks; they do not demonstrate better identification. The complete
tooling gate passed again: **469 standard tests, 94 isolated evaluator tests, 20
and 21 DTO tests**, recursive checks for 115 standard TypeScript sources,
generated-contract validation and all 12 shell suites. No Function runtime or
public DTO implementation changed in this slice; the earlier Edge-suite result
above belongs to Slice 1. No new live benchmark, database run, iOS build or
deployment was performed.

The live-controller slice passed **470 standard tooling tests, 101 isolated
evaluator tests (47 steps), both DTO suites (20 and 21), and all 12 shell
suites**. The Edge suite passed **2,171 tests (343 steps), with nine
database-dependent tests ignored**. The adapter test verifies the unchanged
pinned request and exact-model/native-moderation behavior. Controller tests
cover admission, frozen requests, v2-only records, failed/unassessable screens,
missing reviews, interruption, changed source/inputs, budget bounds and no
redispatch.

The launcher tests exercise hidden input, scoped child permissions, old/new
contract rejection, stopped state and cancellation with synthetic credentials
and zero API calls. An independent read-only review found no remaining blocker
after admission was revalidated under the run lock. The generated identification
bundle identity was regenerated and its diff reviewed; the pure-adapter
ownership guard now explicitly inventories the Sol configuration.

Recursive formatting/lint, all 102 Function config/dependency graphs, generated
DTO validation, six changed Markdown files, 343 local documentation links and
diff whitespace passed. All twelve copied images and frozen fact cards still
match their source inputs. No paid requests, hosted mutations, database run, iOS
build or production deployment occurred during controller implementation. The
subsequent live execution and reference adjudication are recorded above and in
the linked result report.
