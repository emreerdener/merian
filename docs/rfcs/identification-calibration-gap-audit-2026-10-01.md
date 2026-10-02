# Photo calibration gap audit and next implementation design

Date: 1 October 2026

Status: **offline audit and implementation design complete**. No provider calls,
production changes, new model candidate, threshold change or database migration
were made for this checkpoint. The completed
[provider decision](identification-photo-provider-decision-2026-10-01.md)
remains closed, with its scores and references unchanged. Released Sol-low
remains the beta configuration.

The subsequent
[offline implementation checkpoint](#offline-implementation-follow-up--1-october-2026)
below implements development tooling without changing this audit's findings.

## Decision

Reuse the existing explicit-primary foundation. The repository already has the
versioned wire contract, immutable server storage/replay, V53 native
persistence, rank-aware consumers and protocol-5 reader support. The missing
production piece is a qualified producer and its rank-aware live orchestration,
not another rank field, DTO or SwiftData migration.

The next scoped implementation should improve development-only mapping
observability and prepare one explicit-resolution candidate against the
**current confidence prompt**, with no live admission. Do not tune numerical
confidence until identification behavior and reference/mapping coverage are
adequate. Do not promote either failed September candidate or the October
evidence candidate.

## Offline evidence and reproducibility

The audit read the archived October packet, frozen taxonomy and all 220 bounded
result records. It called the checked-in `parseTaxonomy`,
`normalizedTaxonomyName`, `resolveTaxon` and fingerprint helpers with network,
environment and filesystem writes denied to Deno. A shell captured its bounded
JSON report in a separate audit directory; the original study was read-only. No
unknown names were guessed, brute-forced or reconstructed from hashes.

| Catalog check                                                     | Finding |
| ----------------------------------------------------------------- | ------- |
| Taxa                                                              | 91      |
| Canonical names plus synonym entries                              | 970     |
| Distinct normalized names                                         | 969     |
| Missing reference IDs or rank mismatches                          | 0       |
| Canonical-name round-trip failures                                | 0       |
| Shared normalized synonym                                         | 1       |
| Synonym entries deliberately unresolved because of that collision | 2       |
| Matched study outputs using a synonym                             | 0       |
| Ambiguous study outputs                                           | 0       |
| Unmapped study outputs / distinct sanitized-name hashes           | 25 / 12 |
| Unmapped output hashes matching any frozen catalog name           | 0       |

The shared synonym is `Papilio archippus`, present under both the catalog's
`Danaus plexippus` (`gbif:5133088`) and `Limenitis archippus` (`gbif:5132398`).
This is a collision in this catalog, not an adjudication of historical
nomenclature. The current resolver correctly refuses to pick one. No attempted
result used that alias, so it explains none of the observed gaps. Do not remove
one owner, choose the first match or use the expected answer to resolve it. Any
future disambiguation needs a separately reviewed identity key or authoritative
context before freezing the next catalog.

| Phase / configuration     | Matched canonical names | Unmapped names | Non-named outcomes |
| ------------------------- | ----------------------- | -------------- | ------------------ |
| Development released, /20 | 14                      | 2              | 4                  |
| Development evidence, /20 | 14                      | 2              | 4                  |
| Validation released, /60  | 39                      | 9              | 12                 |
| Validation Gemini, /60    | 43                      | 5              | 12                 |
| Validation evidence, /60  | 40                      | 7              | 13                 |

Mapping success is not correctness: mapped names can be unsupported or too
broad. The failed-outcome partitions and paired accuracy remain those of the
completed report. In particular, Gemini's four gains all replace released
unmapped names; the candidate's five gains include two genuine rank corrections
and three mapping-dependent gains, offset by two too-broad answers and a subject
error.

One unknown sanitized-name hash recurred eight times across both OpenAI profiles
and four observations (`c0003`, `c0004`, `c0114`, `c0163`), including all three
high-score released validation mapping failures. Those observations have
_Coprinus comatus_ references; that fact **does not identify the missing model
name**. The repetition proves a recurring output pattern, not a missing synonym,
a wrong organism or correctness. Other shared hashes recur across Gemini and
OpenAI on limited-evidence cases. Provider agreement likewise supplies no truth.

## What the evaluator can and cannot diagnose

The evaluated path is provider draft → production normalization → exact finite
catalog lookup → bounded prediction. Its owners are:

- [`normalizeIdentification`](../../services/supabase/functions/_shared/identify/normalizeIdentification.ts)
  sanitizes scientific names, canonicalizes supported pet conventions and
  applies subject rules. It does not establish a taxon's rank or image
  correctness.
- [`sanitizeScientificName`](../../services/supabase/functions/identify/sanitize.ts)
  adjusts whitespace/case and removes some authors/qualifiers before lookup.
- [`resolveTaxon`](../../services/supabase/scripts/identification_evaluation/taxonomy.ts)
  applies NFC, whitespace and case normalization, then exact canonical/synonym
  matching. Zero matches is unmapped; multiple owners is ambiguous. It performs
  no network lookup, fuzzy guessing or reference-dependent fallback.
- [`projectConfidenceOutcome`](../../services/supabase/scripts/identification_evaluation/confidenceProjection.ts)
  and the Gemini projection retain resolved ID/rank or an unknown mapping;
  alternatives never repair the primary answer.
- [`photoDecisionRunner`](../../services/supabase/scripts/identification_evaluation/photoDecisionRunner.ts)
  records a hash and name-form flag **after normalization**. Consequently,
  `plain` cannot prove that the original provider string lacked qualifiers or
  that normalization preserved its intended meaning.

All known catalog names resolve as designed except the deliberately ambiguous
alias. There is no demonstrated exact-matcher defect or supported alias addition
for the 25 unmapped outputs. Missing synonyms, unsupported names, genuinely
wrong taxa and normalization effects remain competing explanations. The existing
records cannot distinguish them. No catalog patch is justified by guessing. The
finite evaluation lookup is also distinct from production dictionary/GBIF
hydration; its mapping rate does not establish the production lookup failure
rate.

For the next development implementation, add bounded pre/post-normalization
flags and mapping stage/status, preserving unknown rank for legacy outputs. Keep
provider-declared resolution separate from catalog-resolved rank. To adjudicate
a genuinely new name, use a private transient development review of only the
bounded scientific-name field, without request/response dumps, logging,
screenshots or persisted provider prose. Persist only reviewed public taxonomy
IDs/ranks, mapping disposition and source-review references. Unreviewed values
remain hashes/unknowns. Invalid or prose-like fields must not enter review logs.

This is a prospective review design, not a relaxation of the completed study's
privacy or scoring rules. Freeze any reviewed catalog update before a new
validation collection; never repair validation mappings after seeing outputs.
Keep unverified mapping coverage in the report so excluding unknown labels
cannot make a calibrator look artificially accurate.

## Existing contract and remaining production gap

The canonical semantics remain the
[primary-resolution implementation record](identification-primary-resolution-contract-2026-09-29.md)
and
[current API contract](../backend-and-data/05-api-contracts.md#scan-response-replay).
This checkpoint refines the next work; it does not replace those contracts.

| Boundary                | Already implemented                                                                                                                              | Remaining work before activation                                                                                                                                          |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Wire                    | `primary_identification` v1, five-state resolution, required nullable names, bounds and consistency checks in `contract.ts`; generated Swift DTO | A new producer must actually construct and emit it under its required provenance schema                                                                                   |
| Server storage/replay   | Immutable scan/job snapshot, owner-bound recovery, stored/reconstructed response validation                                                      | Pass the finalized snapshot through the live producer and every completion path                                                                                           |
| iOS                     | `PrimaryIdentification`, V53 storage, history merge, labels/rank captions, species-effect and review gates                                       | Verify the actual released reader and install-over behavior for the selected producer; do not add another persisted field                                                 |
| Public/shared consumers | Separate original AI identity from verified species selection in public labels, Field Chat, exports and species effects                          | Preserve existing privacy/publication restrictions; no generic raw snapshot exposure                                                                                      |
| Reader compatibility    | Native source advertises exactly protocol 5; primary responses require 5, legacy results remain readable                                         | A qualified explicit producer needs typed snapshot/provenance support and exact minimum-5 admission, registry and quota support; existing binding minima remain unchanged |
| Producer                | Separate strict Sol-primary evaluation decoder/normalizer already exercises five states                                                          | Current released profile is legacy; the old explicit candidate failed visual-grounding review and cannot be promoted                                                      |

The active multimodal route's `isIdentifiedBio` is biological subject plus a
nonempty scientific name. It can send a genus through species dictionary and
enrichment paths because the current model contract carries no explicit rank.
The same legacy pattern exists in image and description routes. This is a
source-level semantic limitation, not proof that a particular archived scan
created a bad species row; no hosted scans were inspected.

The existing explicit result states supply the needed meaning:

| Resolution              | User-visible meaning                                            | Species effects                                                                                  |
| ----------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| `species`               | Named species, with model estimate attached to that answer      | Eligible only after affirmative accepted-species identity/rank checks                            |
| `genus` / `family`      | Named broader taxon and existing rank caption                   | No species association, alternatives, pet data, reference imagery, novelty or species enrichment |
| `unresolved_biological` | Biological subject; insufficient evidence for a supported taxon | Biological true, scientific name null; retain observation and normal add-evidence actions        |
| `non_biological`        | Object/mineral or other nonbiological subject                   | Biological false; optional object label; no species effects                                      |

Use existing unresolved copy and add-evidence/refinement entry points first. A
species-specific request such as “photograph the gills” is appropriate only when
supported by the identified group and observed limitation; do not invent a new
diagnostic claim or an automatic second inference. The original explanation
format remains unchanged. A retry/replay restores the same result; a new photo
is a deliberate new/refined observation under existing submission rules.

No rank may be inferred from token count, confidence, a dictionary hit, plan
tier or a typed user override. A separately validated species confirmation can
supply an effective species identity without rewriting the original AI rank or
score. A genus badge must never imply confidence in an unseen species.

## Concrete implementation sequence and acceptance

### 1. Development observability

Extend the existing evaluation projection with a separately versioned record;
leave historical parsers, records and scores untouched. Prove deterministic
flags for unchanged names, stripped authors/qualifiers, pet aliases, ambiguity,
unmapped names and explicit/catalog rank conflict. Retain fixed bounds,
content-free durable artifacts and no network fallback. Reuse the existing
catalog audit rather than create another evaluation platform.

Acceptance: all synthetic known-name variants and collisions have the intended
status; unknowns receive no invented rank/credit; no raw name or provider prose
is present in saved diagnostics. A reviewed future catalog may expand coverage,
but the frozen October catalog and summary must remain byte-identical.

### 2. One isolated explicit-resolution candidate

Build from `buildOpenAIPhotoRequestParameters` for today's confidence profile.
Reuse the five-state decoder/normalization concepts from `openaiSolPrimary*`,
with new evaluation identities. Do not replace the current builder wholesale
with the old model-profile builder: that would also change the confidence/traits
baseline. Preserve the `confidence_score` field description and unrelated
confidence, explanation and traits instructions/schema fields, image
bytes/detail, low reasoning, model, output ceiling, native moderation and one
invocation per observation. Explicitly allow changes to identification
instructions, resolution, rank-consistent names and nullability, species-only
alternatives, and the new structured-output format identity.

The focused change is required explicit resolution with mutually consistent
names/subject and species-only alternatives. Preserve supported species rather
than broadly abstaining; a missing diagnostic feature is unknown, not absent. No
benchmark species names or answers enter instructions. Synthetic structured
output success is contract evidence, not evidence that the model sees correctly.

Acceptance must cover all five states, missing/contradictory resolution,
qualifier rejection before lossy normalization, supported pets/minerals, empty
species alternatives, family lineage, low/zero-confidence biological abstention
and processed-material demotion. Request parity tests must compare all request
settings against the released builder except that named allowlist of intentional
changes, with deep assertions for unchanged confidence, explanation and traits
schema fields. The candidate must remain inadmissible in production.

Use the now-exposed October cases as development regression evidence, including
both successful and failed observations, alongside the earlier explicit-primary
fly-grounding failure and pet/mineral cases. Never count repeated calls or
multiple arms as independent observations. A new candidate must preserve all
three October species regressions while retaining the five genus successes on
that fixed challenge subset and introducing no new subject error; this is a
screening goal to freeze prospectively, not a claimed result. Include the six
unresolved biological cases and retain every failure. If one frozen candidate
fails the screen, report failure rather than repeatedly tune against fresh data.
Model screening remains unrun and requires separately bounded collection.

### 3. Qualified live orchestration and compatibility

Only after model qualification, compose a production-only profile under the
reserved `merian_identify_primary_v1` durable schema and its own new
prompt/binding identity. Extend the closed `AIAttemptSnapshot` union with a
separately typed production snapshot; the legacy `OpenAIPhotoSnapshot` hardcodes
the old binding/schema. Update the adapter, multimodal result policy, provenance
validation, exact admission/registry and quota paths together. Never cast the
new producer through legacy assertions. These paths currently reject the new
primary identity; a prompt change and database tuple alone cannot enable it.

Derive top-level names/subject from the final snapshot. Use
`resolution == species` as a necessary gate for every primary/candidate
hydration, enrichment, upsert, species ID, novelty and delayed side effect;
accepted-species verification remains necessary as well. Broader or unresolved
answers cannot take the legacy “nonempty name” branch.

Preserve current profiles and their replay semantics. Limit first admission to
still-photo multimodal requests; other routes must either implement the same
boundary or remain unable to receive the new profile. Add a forward exact
minimum-5 database-reservable binding tuple only when warranted, initially
unassigned, with matching admission, registry and quota support. Do not
reinterpret `openai_photo_v1`, upgrade old attempts or trust worker-supplied
capability. Preserve original capability proof and owner/generation checks.

Required integration scenarios: species/genus/family/unresolved/nonbiological
live completion; zero non-species species effects; missing dictionary lookup;
saved/relaunched/second-device results; duplicate and missing-row recovery;
malformed or absent required snapshot; protocol 4 denial and protocol 5 success;
legacy compatibility; verified confirmation replacement/clear; public rank and
privacy projections. No replay may cause another provider call. Use actual-role
and concurrency tests for database changes, generated DTO validation if the
schema changes, and the complete affected backend/iOS/web gates. Existing local
foundation tests do not establish deployed reader readiness.

### 4. Confidence calibration after behavior is fixed

Keep 0.95/0.60 and `openai_unqualified_v1` unchanged now. The calibration target
is a correct, evidence-supported answer at the displayed rank.

The iOS `InferenceConfidencePolicy` recognizes exact legacy binding/schema and
prompt identities. A new primary profile does not automatically inherit its
confidence bands. Initially retain neutral confidence presentation for that new
profile; existing profiles keep their current bands. Any future recognition of
the new provenance must be separately reviewed and tested with its declared
calibration status. A genus confidence must never be presented as species
confidence.

All six unresolved biological references were named by every October arm;
changing a badge cutoff cannot repair that decision.

Use representative authorized observations with independently supported identity
and exact-image answerability review. State whether review is assistant-led or
independent human review. Keep a diagnostic challenge set separate from the
traffic-representative calibration sample. Neither the deliberately balanced
October mixture nor repeated development calls estimate traffic accuracy.

Split related subjects before fitting; fit at most one predeclared simple
calibrator and test it on untouched observations. Choose the target Strong
precision, uncertainty requirement and minimum coverage before collection, then
derive the needed sample size from those requirements. No arbitrary new cutoff
or sample count is asserted by this audit. Distinguish operational verified
coverage from biological correctness; an unmapped name is a failed verified
outcome, not automatically a false biological label for fitting. Report unknown
coverage and perform adjudication before fitting or explicitly bound its effect.

The 60 October holdouts are now exposed development evidence for any new tuning.
Their original frozen comparison stays valid as recorded. The other 40 old
holdouts are not an automatic replacement set: recheck eligibility, clustering
and exposure before any new study. No new validation, paid sample or rollout is
scheduled by this document. Preserve the original score and version any future
calibration by exact provider/model/prompt/preparation policy; historical scores
must not be silently rewritten.

## Verification and remaining limits

The read-only gap calculation completed with zero provider calls and zero packet
writes. All 220 result-file hashes are bound into its output inventory digest;
taxonomy digest matches the frozen study. Repeated execution must produce the
same sorted result inventory and aggregate counts.

A focused existing suite passed **38 tests, zero failures**, with network and
environment permissions denied: strict explicit-primary request/normalization,
primary wire consistency, exact taxonomy matching/collisions and read-only audit
behavior. Two read-only source reviews independently traced backend and
native/shared-consumer boundaries. These checks verify reusable behavior; they
do not qualify the unsuccessful candidate or a new production producer.

This checkpoint changes documentation only. Complete runtime/database/iOS build
gates are not rerun or claimed for this design; they are required when the
implementation surfaces change. The API guide's stale “native advertises 4”
sentence is corrected to 5, matching `IdentificationDispatchAuthorization` and
the existing reader checkpoint. Current API semantics stay unchanged.

Private audit artifacts are retained separately from the closed study at
`/Users/emreerdener/Developer/merian-evaluation/2026-10-01-photo-calibration-audit-v1`.
They contain the reproducible read-only calculation, bounded result, focused
verification log and source/input hashes, with no images, provider prose or
credentials. Their hash groups are diagnostic and never an identity reference.
The original archive and its retention deadline remain unchanged.

## Offline implementation follow-up — 1 October 2026

The next offline slice is implemented in source:

- `functions/_shared/ai/openaiPhotoPrimary.ts` builds the new
  `openai_photo_confidence_primary_low_v1` evaluation candidate from the current
  confidence builder. Its binding is
  `openai_photo_confidence_primary_evaluation_v1`, prompt is
  `openai_identify_vision_confidence_primary_v1`, and private provider schema is
  `merian_openai_confidence_primary_evaluation_v1`. These identities are
  separate from the September candidate and the reserved durable schema. The
  request changes only the identification instruction/schema allowlist above. It
  reuses `decodeSolPhotoPrimaryDraft` and `normalizeSolPhotoPrimaryDraft`; the
  historical modules themselves are unchanged.
- `scripts/identification_evaluation/developmentProjection.ts` implements
  `projectDevelopmentDraft` and the separately versioned
  `photo_development_diagnostics_v1` projection. It records bounded before/after
  lexical flags, sanitizer and pet-alias changes, processed-material demotion,
  mapping status and canonical/synonym match, declared/effective resolution and
  catalog rank. A lexical flag is not taxonomic proof. Exact catalog rank
  conflicts receive an invalid outcome without identity credit. Unknown or
  ambiguous names remain unverified; legacy names retain unknown declared rank.
  No name, explanation, raw normalization event, reference answer, credential or
  response body enters the returned record.

The projection is a pure in-memory helper, not a collector or safety approval.
There is no new live adapter, CLI, runner, production route, quota binding,
database change or client change. Future collection still requires exact profile
binding, native moderation, bounded accounting, durable attempt claims and a
separately authorized frozen protocol. Closed studies are neither resumed nor
rescored. No provider calls or additional charges were incurred.

The focused suite passed 47 tests, including all five states, zero-confidence
biological abstention, qualifier rejection before sanitation, explicit/catalog
rank conflict, unchanged/sanitized/pet/synonym/ambiguous/unmapped names, content
omission and production rejection. Request parity checks cover every field
outside the named allowlist, including the full image/generation/moderation
settings and unchanged schema properties. A read-only independent review found
no material defect. This is contract evidence only: no new model output has been
collected, no accuracy gain is established, and live qualification, confidence
calibration and rollout remain unrun.

The recursive schema check preserves required nullable fields and closed
objects, consistent with the official
[Structured Outputs contract](https://developers.openai.com/api/docs/guides/structured-outputs).
It does not prove that the model will choose a biologically correct answer.

Complete affected-surface verification for this follow-up:

- Runtime suite: 2,239 passed, 343 steps, zero failures, 11 existing skips.
- Tooling: 489 standard tests and 140 evaluator tests passed; the separate DTO
  suites passed 20 and 21 tests, and executable/generated DTO checks passed.
- All 103 Function entrypoints passed recursive checks with their deploy-time
  configs; dependency/config synchronization checks passed.
- All 17 shell test files passed. The first sandboxed tooling command stopped at
  the Gemini launcher's synthetic hidden-input test because terminal echo
  control was unavailable. The unchanged test passed outside the sandbox, and
  the complete shell portion was rerun successfully there with synthetic
  credentials and local fake executables. No real provider or hosted operation
  occurred.
- Recursive backend formatting/lint, changed-Markdown formatting and local
  documentation-link checks passed. CI now explicitly includes the new
  candidate's offline test and its transport/credential exclusion guard.

No iOS build or disposable-database execution was needed for this source slice:
it changes neither client code, public/durable DTOs nor SQL. Those integration
gates remain required for the future live orchestration slice.

Unrelated iOS and backend implementation edits appeared concurrently in the
shared checkout during verification. They were preserved and were not reviewed
as part of this slice. The counts above report completed checks against the
source visible when each ran; they are not exact-SHA release evidence or a
qualification of the concurrently changing checkout.

## Bounded collector follow-up — 1 October 2026

The
[separate development protocol](identification-photo-primary-screen-2026-10-01.md)
connects the current-baseline explicit-primary candidate to the existing
evaluator. It schedules 20 exposed observations in two arms with content-free
normalization diagnostics, paired pass criteria, durable no-retry claims and a
separate $10/40-call ceiling. The completed screen used 40 calls and
$1.541925002 in conservative accounting. Supported outcomes rose from 7/20 to
11/20, but the candidate failed the frozen screen: one species-reference loss,
one historical gain not retained and no appropriate abstention on six unresolved
cases. Retain the released configuration. The budget is closed; production
routing and confidence thresholds remain unchanged.
