# Photo identification evidence and rank consistency

Date: 2026-09-28

Status: Offline measurement, an isolated Sol candidate and a corrected
development packet are implemented. Reference coverage review, versioned live
admission and production rank handling remain unfinished. Retain Sol for both
Free and Pro. No new model calls or production changes have occurred. Complete
this identification-quality work before returning to confidence thresholds;
preserve the explanation format and Strong / Possible / Weak labels.

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

Existing plans, runners and journals still accept and emit only
`photo_model_attempt_v1`. V2 is an offline building block, not an automatic
upgrade or a live mode. Do not reconstruct a missing mapping from an old null
taxon, modify old artifacts or rerun an old plan. The new controller must bind
v2 explicitly to a new manifest/approval before using it.

## Slice 2: corrected packet and isolated Sol candidate — prepared offline

The offline candidate is `openai_photo_sol_rank_limits_low_v1`, bound to
`openai_sol_rank_evaluation_v1`, prompt `openai_identify_vision_rank_limits_v1`
and schema identity `merian_openai_identify_rank_v1`. Its implementation lives
entirely under the evaluation scripts. Production and historical live profile
constructors reject it; no existing runner accepts this candidate.

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

## Slice 3: measure one model's change at a time

Prioritize Sol because it currently serves both tiers. Prepare the established
shape of six candidate regression screens, then six challenge pairs against the
unchanged Sol baseline, alternating pair order: at most eighteen calls, one
attempt each. Recalculate the conservative reservation with current rates; the
old $40 allowance and remaining allocation do not authorize this run. Only after
that decision should a separately bounded Luna comparison be considered.

Before dispatch, version the plan, manifest, approval and record admission so v2
mapping records cannot mix with historical v1 journals. Bind the corrected
catalog, references, request profiles and source digest. Preserve spending,
claim, stop, review and interruption controls. A complete run still does not
automatically qualify or activate anything.

Predeclare these decisions:

- All six regression screens must remain useful and correctly scoped. Record
  reference gaps separately; an actual wrong identity or explanation failure
  stops the screen.
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
human review workflow is introduced by this plan.

## Slice 4: production contract and model selection

If the prompt result warrants promotion, implement and verify the explicit rank
contract described above, including saved observations, retries, older-client
behavior and enrichment. Keep rollout and rollback tied to the exact reviewed
provider/model/prompt/schema/confidence profile. Production activation is a
separate operation; no future plan or successful offline test changes today's
Sol assignments. OpenAI audio evaluation follows the photo decision as its own
input and model comparison.

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
