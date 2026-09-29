# Photo identification evidence and rank consistency

Date: 2026-09-28

Status: Offline measurement foundation implemented. Prompt candidates, versioned
live admission and production rank handling remain planned. Retain Sol for both
Free and Pro. This work makes no model calls and does not change production
instructions, explanation format or confidence badges.

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

## Slice 2: prepare a corrected packet and isolated prompts

1. Copy the existing no-description photo evidence into a fresh development
   packet. Preserve the original packet and all journals. Optional description
   text does not justify redoing the completed benchmark.
2. Make an explicit reviewed old-ID → canonical-ID remapping for each duplicate.
   Check names and ranks before merging; homonyms and cross-rank collisions must
   not be merged automatically. Apply the same mapping to every reference,
   remove duplicate acceptable IDs, and preserve each reference's supported
   rank. Freeze new corpus/catalog versions and digests and retain the mapping
   as preparation evidence. Add reviewed plausible alternatives and broader
   ranks before freezing, rather than adding predicted names after scoring.
3. Resolve relevant fact-card gaps from available source evidence where
   possible. Record any remaining gap honestly; catalog consistency does not
   establish biological truth or turn provisional labels into independent
   references.
4. Prepare distinct, evaluation-only Luna and Sol candidate profile versions.
   Both use the same evidence-limits objective, but each gets its own request
   identity and comparison to its own unchanged baseline. Preserve the current
   mineral improvement in the Luna baseline. Sol's biological candidate changes
   biological rules only; keep its known mineral limitation visible for a
   separately attributed change.
5. Replace the conflicting biological clauses coherently and fail if the
   expected baseline anchors drift. Select the most specific supported rank; use
   a binomial only when visible evidence supports species-level discrimination.
   Align the common name and alternatives with that limit; allow fewer
   alternatives when two cannot be supported. Explain missing distinguishing
   evidence without inventing observations or using location, popularity, model
   size or a high score as a substitute. Keep all other instructions and current
   explanation structure.
6. Verify deterministic request parity, production-profile isolation and
   synthetic species/genus/family/unresolved normalization. These tests prove
   configuration and transport behavior, not better identification quality.

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
