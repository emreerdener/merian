# Explicit primary identification resolution

Date: 2026-09-29

Status: Slice 1 and the native persistence, backend review authority and native
review acknowledgement checkpoints of Slice 2 are implemented locally. The
shared-consumer and capability-5 reader checkpoints are implemented and locally
verified. Slice 3 now has a separate offline explicit-primary Sol candidate;
live evaluation and producer qualification remain pending. No deployment,
producer activation, model assignment or confidence policy change is included.
The design baseline below used `ca35e74bb` on
`codex/openai-free-pro-evaluation`; the dated checkpoint records distinguish
implemented foundation from pending consumers and model qualification.

The
[completed Sol comparison](identification-sol-rank-comparison-results-2026-09-29.md)
does not qualify its candidate for promotion. Keep the current Sol photo profile
for Free and Pro. This design completes the offline contract-design step in the
[photo rank plan](identification-photo-rank-consistency-2026-09-28.md); it
supplies the storage and compatibility foundation a separately qualified future
result would need.

## Decision and value

Represent the primary answer explicitly as species, genus, family, unresolved
biological subject, or non-biological subject. Preserve that answer through live
display, saving, history, replay and recovery. A genus or family answer must
never become a species result merely because its name is nonempty.

This prevents incorrect dictionary enrichment and loss of broader
identifications on another device. It does not prove that the model identified
the right organism or chose an evidence-supported rank. Model quality still
requires evaluation; rank, model confidence and a person's verification remain
separate facts.

The contract is provider-neutral. Its first prospective producer is an isolated
OpenAI photo profile. Current OpenAI and Gemini profiles keep their existing
contracts until deliberately migrated. Audio, sampled-video identification,
model selection, explanation length and Strong / Possible / Weak thresholds are
outside this implementation sequence.

## Design baseline before implementation

The [API contract](../backend-and-data/05-api-contracts.md#scan-response-replay)
and [database schema](../backend-and-data/04-database-schema.md#scans) describe
current behavior. The following table records the original design baseline; the
dated implementation checkpoints below supersede its gaps and explain why a
prompt-only fix was insufficient:

| Owner                                                                                                                                                                                                                                                                                                                                                                                | Current behavior                                                                               | Required change for an explicit result                                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| [`contract.ts`](../../services/supabase/functions/_shared/identify/contract.ts), `edgeResponseContract`                                                                                                                                                                                                                                                                              | Names and a lineage object; no primary resolution.                                             | Own the versioned result field, validation and generated Swift DTO.                  |
| [`normalizeIdentification.ts`](../../services/supabase/functions/_shared/identify/normalizeIdentification.ts), `normalizeIdentification`                                                                                                                                                                                                                                             | Sanitizes names and applies subject policies; does not preserve a primary rank.                | Validate explicit resolution against the final normalized subject and names.         |
| [`identify-multimodal/index.ts`](../../services/supabase/functions/identify-multimodal/index.ts), `isIdentifiedBio`                                                                                                                                                                                                                                                                  | Any biological result with a scientific name can reach species hydration and enrichment.       | Gate primary and candidate species operations independently.                         |
| [`db.ts`](../../services/supabase/functions/_shared/identify/db.ts), `insertScan`, `upsertSpeciesDictionary`                                                                                                                                                                                                                                                                         | The scan links a species row; name-based dictionary writes have no primary-rank discriminator. | Save a scan-owned primary snapshot and prevent broader taxa entering species writes. |
| [`completedResponse.ts`](../../services/supabase/functions/_shared/identify/completedResponse.ts), `buildCompletedIdentifyEnvelope`                                                                                                                                                                                                                                                  | Reconstructs from the scan and optional species relation.                                      | Reconstruct the same primary answer without requiring a species relation.            |
| [`SpeciesData+EdgeResponse.swift`](../../apps/ios/Merian/Core/AI/Models/SpeciesData+EdgeResponse.swift) and [`SpeciesData+Presentation.swift`](../../apps/ios/Merian/Models/Species/SpeciesData+Presentation.swift)                                                                                                                                                                  | Non-placeholder names imply a resolved biological identification.                              | Separate a usable biological taxon from a species-level identification.              |
| [`LocalScanRecordFactory.swift`](../../apps/ios/Merian/Core/Data/Database/LocalScanRecordFactory.swift), [`HistoricalSyncCloudClient.swift`](../../apps/ios/Merian/Core/Data/Database/HistoricalSync/Services/HistoricalSyncCloudClient.swift), [`HistoricalDatabaseActor.swift`](../../apps/ios/Merian/Core/Data/Database/HistoricalSync/Persistence/HistoricalDatabaseActor.swift) | Local storage has no rank; history depends on the dictionary for names.                        | Persist and merge the same snapshot across local and cloud recovery.                 |
| [`InferenceHistoricalRecordProjection.swift`](../../apps/ios/Merian/Core/AI/Inference/Hydration/InferenceHistoricalRecordProjection.swift)                                                                                                                                                                                                                                           | Resolved-name checks permit reference images and species enrichment.                           | Apply the same resolution policy after reopening a saved result.                     |

## Proposed wire and model contracts

Add optional `data.primary_identification` to the successful Identify envelope.
When present, it is a strict object with these required keys:

| Field             | Proposed contract                                                           |
| ----------------- | --------------------------------------------------------------------------- |
| `version`         | Integer constant `1`.                                                       |
| `resolution`      | `species`, `genus`, `family`, `unresolved_biological`, or `non_biological`. |
| `scientific_name` | Sanitized string, 1–255 characters, or explicit null.                       |
| `common_name`     | Sanitized string, 1–255 characters, or explicit null.                       |

Use one resolution enum rather than independent status/rank fields that can
contradict each other. Reject extra keys, unknown versions/resolutions and
objects larger than 4 KiB after serialization. The names use the existing name
bounds. This is a proposed identity snapshot, not a new field inside execution
provenance.

Keep existing top-level names and `is_biological_subject` for the shared
response shape. For explicit results they are server-generated projections of
this snapshot, and final validation requires exact agreement. Dictionary
hydration may normalize a species label only before the snapshot is finalized
and only after proving that it represents the same species. Stored replay cannot
update the primary label from today's dictionary or model settings.

| Resolution              | Biological flag | Scientific name | Downstream interpretation                                                                         |
| ----------------------- | --------------- | --------------- | ------------------------------------------------------------------------------------------------- |
| `species`               | true            | Required        | Model's species-level answer; eligible for species resolution checks, not automatically verified. |
| `genus`                 | true            | Required        | Genus-level answer; retain the group label and no species association.                            |
| `family`                | true            | Required        | Family-level answer; retain the group label and no species association.                           |
| `unresolved_biological` | true            | null            | Biological presence without a supported primary taxon; use existing unresolved display copy.      |
| `non_biological`        | false           | String or null  | Preserve existing mineral/object naming behavior; no biological taxon or species association.     |

Genus/family common names must describe the returned group. The deterministic
validator can check shape, contradictions and reviewed taxonomic mappings; it
cannot prove a natural-language group label or visual explanation is accurate.
Do not infer rank by word count, suffix, confidence, subscription tier or an
existing dictionary hit. Do not synthesize missing lineage values as proof. A
family result must not carry a more specific genus in its final taxonomy.

Start with species/genus/family because those are the biological ranks covered
by this work. Other ranks, hybrids, cultivars and infraspecific names need an
explicit extension or a reviewed mapping to a supported parent. Never truncate a
name to manufacture that mapping. Pet regressions, including the current
domestic-dog naming convention, are a qualification requirement before a new
producer can replace today's profile; legacy pet results remain unchanged.

The future isolated model-output schema adds a required resolution discriminator
beside its existing names. The server constructs the versioned public snapshot
after existing subject normalization and any eligible name canonicalization.
Processed-material or other deterministic subject demotion must update the
resolution consistently. Other contradictory or missing required values fail
validation; they never fall back to the old name-only path or become a second
provider request automatically.

The profile registry must declare whether a result requires this contract.
Current profiles remain legacy producers. Missing `primary_identification` is
valid for their old results, but invalid for a new producer that requires it.
Shared Gemini prompt/schema descriptions are not edited just to add the OpenAI
candidate. The failed `openai_photo_sol_rank_limits_low_v1` experiment remains
frozen and must not be repurposed into a different candidate.

### Alternatives and species enrichment

For the first explicit producer, genus/family, unresolved and non-biological
results return `candidates: null` and `pet_identification: null`. This avoids
reintroducing unsupported species through the existing species-oriented
alternative cards. Broader-rank alternative cards are a later extension, not an
implicit reinterpretation of current candidate UI.

A species primary may have zero to two alternatives. Each new candidate carries
an explicit `taxon_rank: "species"` beside the existing candidate fields,
checked in both model and wire contracts. The field remains absent on legacy
candidates. Every candidate in an explicit result must satisfy the new rule; a
missing or broader rank cannot authorize candidate hydration or upsert. Existing
confidence and candidate-selection restrictions still apply. Empty alternatives
are valid; there is no requirement to invent two names.

For an explicit result, `resolution == species` is necessary for species-only
work and is not sufficient proof that a dictionary match is correct. Use the
existing accepted-species resolver's rank/status/key checks before linking an
identity. `is_public_biological`, a positive GBIF key alone, usable kingdom and
a name-based cache hit are not species-rank evidence. A taxonomic resolver
verifies the named taxon's rank and identity, not whether the photograph depicts
it.

If that lookup is unavailable or inconclusive, preserve the model's species
answer in the snapshot, keep `species_id` null and skip species enrichment. Do
not fail an otherwise valid identification simply because optional enrichment is
unavailable. An accepted synonym may be canonicalized only with affirmative
same-species evidence before finalization. Broader matches cannot be narrowed by
enrichment.

For every explicit non-species result, primary cache hydration, dictionary
creation, species reference images, lookalikes, species-specific summaries and
the new-species milestone are disabled. Keep `species_id` null and
`is_new_to_merian_dictionary` false. Deferred/background enrichment must recheck
the durable result, not trust a client flag or the presence of a label. Ordinary
observation features remain available under their existing policies.

## Durable storage, recovery and review

Propose nullable `scans.primary_identification` JSONB with a strict bounded
validator and no default or initial index. It is server-owned observation data,
unlike the content-free `identification_provenance` field. It follows existing
scan visibility, retention, deletion and export rules. Do not log names or use
them in benchmark receipts. No client INSERT/UPDATE grant is added.

Persist the finalized snapshot with the exact owner scan and copy it atomically
to the matching ingestion-job recovery record, following existing provenance
ownership and generation checks. It is immutable for that completed generation.
Client `recovery_scan` JSON cannot assert or replace it. Missing-row recovery
uses only the matching server-owned backup. Duplicate completion cannot replace
the first result; no new provider call is needed to recover it.

Keep this snapshot out of the client recovery allowlist in
[`scanRecovery.ts`](../../services/supabase/functions/_shared/scanRecovery.ts).
Extend the server-owned recovery trigger/RPC boundary instead, following
[`guard_scan_identification_provenance`](../../services/supabase/migrations/20260926160249_persist_identification_result_provenance.sql).
Restored biological flags and species associations must agree with that trusted
snapshot; conflicting client recovery fields cannot give a genus a species ID.
The replay worker can finalize with a null response envelope, so testing only
the stored-envelope path is insufficient.

Update `COMPLETED_SCAN_SELECT`, row decoding, stored-envelope validation and
reconstruction together. A genus/family result must reconstruct its original
name from the scan snapshot with no dictionary relation. If a stored envelope is
unusable, reconstruction may use a valid owned snapshot; missing or damaged
required snapshot data is an integrity failure, never a guessed legacy result.
The immutable admitted prompt/schema profile identity records whether this
contract is required. Preserve that provenance in completion and recovery and
check both it and the snapshot at read boundaries; loss of the snapshot alone
cannot make the result legacy. The versioned snapshot does not replace existing
provenance.

Keep original AI identity separate from user confirmation and community
identification. A later accepted species confirmation may attach its own
verified identity through the existing authorized flow, without rewriting the
original broader AI snapshot or relabeling its score as species confidence.
Species counts, rewards and public projections must distinguish that confirmed
identity from the original AI answer.

Enforce this in native policy as well as SQL. Today,
`LocalScanRecord.hasResolvedBiologicalIdentification`,
`SpeciesData.hasResolvedBiologicalIdentification` and
`InferenceHistoricalRecordProjection` can give a typed override species-like
behavior. For an explicit non-species result, free text,
`user_confirmed_identification`, `ai_confirmed` and a community genus outcome
must not enable species references, lookalikes, candidates, novelty or other
species-only effects. Only a separately server-validated species confirmation
may supply an effective species identity. Its display/enrichment uses that
confirmed identity and existing permissions; the original AI rank, alternatives
and confidence remain attached to the original answer. Confirmation does not
convert the AI score into confidence in the confirmed species.

Public consumers often select `COALESCE(confirmed_species_id, species_id)`.
Preserve an independently accepted species confirmation, but never substitute a
free-text override, a community genus-best-possible vote, or an AI genus label
for a species FK. Review Field Trip goals, discovery counts, Explore cards,
species chat context and reference-image eligibility under that distinction. Do
not hide an otherwise eligible observation merely because it has no species
association.

The service-side DwC-A producer currently gets names from the dictionary
relation. Its explicit-result projection must retain the snapshot's primary name
and actual supported rank with no invented species ID. Add any export column
deliberately through its versioned DTO/metadata contract; keep already
materialized export jobs immutable. Public web/admin projections expose only the
appropriate published or authorized labels, not a wholesale internal JSON dump.

### Native persistence and legacy semantics

Add optional `LocalScanRecord.primaryIdentificationData` containing the
validated snapshot; map generated DTOs to a small domain value rather than
persisting a generated wire type. Do not reuse `identificationProvenanceData`
for labels. Carry the value through live completion, historical
selection/decoding/merging, single-scan recovery, local reopening and sharing
projections.

Also close the confirmation persistence gap: `HistoricalSyncCloudClient` does
not currently select `confirmed_species_id`, and `HistoricalScanResponse` does
not decode it. Add the ID and a narrow, explicitly disambiguated
confirmed-species relation/projection, then update `HistoricalDatabaseActor`,
local factories and historical presentation together. Propose a separate
optional `LocalScanRecord.confirmedSpeciesIdentityData` for the validated ID and
bounded canonical display identity, populated only by the authorized
confirmation response or a validated server projection. Include it in the same
planned schema migration. A raw local ID or override string is not proof of
species validation.

Unlike the immutable AI snapshot, confirmation can change through the existing
authorized review workflow. Its persistence/merge contract must distinguish an
older payload that omits confirmation from an authoritative clear or
replacement, and reject stale updates using that workflow's ordering evidence.
Missing-row recovery must apply the same species-validation boundary before
restoring a confirmed association. When that confirmation cannot be established,
preserve the AI snapshot and pending review information without granting species
effects. Test confirmation, replacement, clearing, relaunch and second-device
recovery; do not infer this state from the legacy confirmation boolean.

The inspected current schema is V52. At implementation time, re-read the current
alias and freeze the actual outgoing model and relationship graph before editing
active models. Compile that snapshot, then introduce the next schema and an
additive optional-field migration. Extend recent-version startup plans and use
disk-backed upgrade/relaunch fixtures. Never edit retired snapshots or delete a
store to bypass a migration error. See the
[SwiftData workflow](../../skills/merian-swiftdata-migrations/references/schema-update.md).

Missing wire fields and SQL/local null values mean legacy/unknown resolution,
not species. Preserve existing legacy display and saved observations without
granting new rank guarantees. Do not bulk-backfill rank from names or
`species_id`. A missing legacy history value cannot erase an already saved
explicit snapshot. A conflicting snapshot for the same completed generation must
surface an integrity failure; it is not a last-write-wins merge. Malformed
present data follows existing quarantine/recovery handling rather than becoming
nil.

Use separate domain decisions for a named biological taxon and species-level
eligibility. Genus/family display retains the returned label, explanation and
supported lineage, with an ordinary indication of the rank. It does not use the
unidentified placeholder merely because no species row exists. Unresolved and
non-biological subjects retain their existing presentation paths.

Keep Strong / Possible / Weak and the current explanation format. No threshold,
calibration, automatic verification or score inflation is introduced here. The
existing shipped-profile display policy stays in place. A future prompt/schema
profile requires an explicit confidence-presentation decision; being another Sol
profile does not inherit a qualified policy automatically. If a badge is shown
for a broader result, it must describe that returned rank, not an unseen
species.

## Compatibility and release order

Optional fields alone are insufficient: old clients ignore them and may treat a
genus as a species. Slice 1 reserves identification capability **5** after
confirming it was previously unrecognized. The native app stays on **4** until
Slice 2 completes all required consumer behavior. Entitlement protocol **3**
remains separate and unchanged. Do not accept arbitrary larger integers as
compatible readers.

| Stored result                                                     | Legacy reader                     | Recognized capability 4 | Proposed capability 5        |
| ----------------------------------------------------------------- | --------------------------------- | ----------------------- | ---------------------------- |
| Null/V1 provenance, no explicit result                            | Existing behavior                 | Existing behavior       | Legacy resolution behavior   |
| OpenAI V2 provenance, no explicit result                          | Existing update-required response | Existing behavior       | Existing behavior            |
| Valid explicit primary result, with its required profile metadata | Update required                   | Update required         | Explicit resolution behavior |

Capability 5 readers must also decode all currently supported results. Add
recognized-4-and-5 handling everywhere current code compares exactly to 4:
preflight, assignment minima, reservation snapshots, internal retry evidence,
Edge request validation, final/replayed response checks, Data API reads and
native header/decision parsing. A new rank-producing assignment requires 5;
existing bindings retain their existing minima. Do not use a worker's supplied
header to upgrade the original attempt's accepted capability.

This requires forward SQL migrations of the closed binding and attempt CHECK
constraints introduced by
[`20260927175708_prepare_openai_photo_routing.sql`](../../services/supabase/migrations/20260927175708_prepare_openai_photo_routing.sql).
Their current allowed minima are `0|4`, and the OpenAI tuple fixes
`openai_photo_v1`, its model and minimum 4. Preserve those original tuple
semantics and every saved v4 attempt. Add recognized capability-5 claims for new
requests to existing bindings without rewriting their minima. When a new
producer qualifies, introduce its own exact profile/binding/model tuple with
minimum 5 in a separate forward migration; never rename the old binding or relax
the checks to arbitrary OpenAI profiles or numeric versions. Keep that new tuple
unassigned until the authorized activation. Update native preflight's `[0, 4]`
allowlist and OpenAI-minimum equality rule in the same coordinated rollout.

The result reader checks today's requesting device, including stored replay and
mixed history pages, independently of the original submitter. Preserve existing
visibility checks before compatibility errors; a hidden row must not reveal its
existence through an update error. A visible explicit result fails the whole
unsupported page even if the query omits the new field. Service-role projections
need their own semantics because they bypass this RLS check.

Release order after implementation and qualification is: additive backend
read/storage support with all producers unchanged; a compatible app with tested
store upgrades; then separately authorized activation of a qualified explicit
profile. Downgrading fresh assignments does not erase explicit saved results:
retain their storage, reader gate and compatible recovery code. Do not strip the
new field to make an old app accept a semantically different answer.

Deployment and distribution remain explicit operations under the canonical
[Supabase runbook](../backend-and-data/06-supabase-deployment-runbook.md) and
[testing strategy](../development-guides/08-testing-strategy.md). This document
changes no hosted policy and grants no new paid experiment.

## Slice 1 source implementation

The executable contract, generated Swift DTO, scan/job columns, immutable
owner-bound recovery, stored/reconstructed replay and exact protocol-5 reader
gate are implemented. The new migration copies both primary and provenance in
the existing after-insert update. Recovery cannot assert a snapshot from client
JSON. Required-snapshot loss and mismatched labels/provenance fail validation;
reconstruction does not infer rank or replace saved labels from the dictionary.

The requirement marker is the reserved schema identity
`merian_identify_primary_v1`, interpreted by `identificationResultContract` and
SQL CHECK/read boundaries. It is not registered as an executable model profile.
Every existing provider output schema remains a legacy producer, and no live
handler constructs or persists this snapshot. A future qualified producer will
use this reserved schema with its own separately reviewed prompt/binding
identity.

New accepted protocol-5 claims can use today's exact minimum-4 OpenAI tuple;
original attempts retain their accepted claim and internal workers cannot
upgrade it. Binding minima remain `0|4`. Native header/preflight behavior stays
on 4. The generated DTO is not full consumer support: native
storage/presentation, public/admin/export and broader confirmation policy are
pending in Slice 2; minimum-5 producer admission and qualification are pending
in Slice 3.

Local verification completed on 2026-09-29:

- Complete Edge suite: 2,191 tests and 343 steps passed, with the disposable
  database enabled for concurrency tests. All 102 function entrypoints also
  passed recursive checks with their deployment configs.
- Database: full sorted migration replay and all 68 catalog files passed (442
  assertions). The separate out-of-order recovery gate passed its three catalogs
  (21 assertions). Both disposable projects were stopped afterward.
- Database lint: no findings. Security and performance advisors passed their
  error gates; 103 security and 79 performance warnings remain under the
  repository's existing advisory policy.
- Supabase tooling: the complete `make test-supabase-tooling` gate passed,
  including the isolated evaluator, generated DTO checks and 12 shell suites.
  Migration-contract validation passed 359 tests across 67 files. Deno
  formatting, lint and isolated dependency-graph validation passed.
- Native: `make ios-local-build` compiled all test targets and ran the complete
  iOS unit target on an existing iPhone 18 Pro Max simulator. XCResult reports
  4,543 passed, zero failed and zero skipped. The primary decoder covers all
  five states, required null round-trips and malformed metadata. XcodeGen
  produced no project diff, and `make validate-ios-project` passed. The retained
  local result bundle is
  `.artifacts/local-ios/e2dbd4264f964c17b5ba7da4de6c03f1.xcresult`.
- Independent read-only review found no remaining contract or data-integrity
  blocker after DTO regeneration. A separate regression covers the first-owner
  insert committing between job and scan reads. Required schema markers also
  protect response emission when a snapshot is absent.
- Documentation formatting, 438 local file-link targets and diff whitespace
  checks passed.

Hosted exact-SHA CI, critical UI smokes, a Release archive and external-device
release verification were not run for this dormant slice. This is local
implementation evidence, not deployment or model qualification. Native
persistence, presentation and public/admin/export support remain Slice 2, before
any producer can emit this contract. There were no paid model requests or
production mutations.

## Implementation slices and acceptance

1. **Add the dormant contract and server storage.** Implement strict types,
   normalization helpers, profile requirement metadata, forward migrations,
   immutable owner-bound backup/recovery, reconstruction and recognized-reader
   support. Generate and inspect the Swift DTO diff. Keep all existing producer
   profiles unchanged. Prove new cases using synthetic results only.
2. **Complete consumers and save/restore behavior.** Add the native domain and
   schema migration, history/queue/replay mappings, species-only operation
   gates, and reviewed public/admin/export projections. Verify that a
   genus/family result survives an app relaunch and a second-device fetch
   without gaining species enrichment. Explicitly update override/confirmation
   policy and confirmed-species history/persistence owners; existing
   observations and independently validated user/community confirmations must
   survive.
3. **Qualify a separate explicit producer.** Build a new isolated OpenAI photo
   candidate with its own prompt/schema/provenance identities and required rank
   output. Check species, broader taxa, unresolved subjects, pets, processed
   objects and geological names. First validate offline; propose a new bounded
   comparison only when the candidate and reference coverage justify it. Do not
   reuse the completed eighteen-call allowance or promote the failed candidate.
   Only a qualified producer receives a distinct closed production tuple with
   minimum capability 5, initially unassigned.

Reader and writer changes may span pull requests, but there is no activation
between incomplete slices. Code readiness, model quality and production release
are separate recorded decisions. Confidence calibration follows stable,
qualified identification behavior and adequate labeled evidence.

| Verification                     | Required evidence when implementing                                                                                                                                                                                                                                                             |
| -------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Contract and normalization       | Every resolution, contradictory flags/names, null/omitted/unknown values, size bounds, profile requirements and explicit-candidate rank rules.                                                                                                                                                  |
| Side effects                     | Spies/fixtures prove non-species primary and candidates cause zero species hydration, upserts, reference-image/lookalike work or novelty credit, on live and delayed paths.                                                                                                                     |
| Database ownership and replay    | Actual-role permission tests, immutable first completion, concurrent duplicate finalization, missing-row recovery, spoofed client data, deleted owners and damaged-required-snapshot cases.                                                                                                     |
| Readers                          | Capability matrix across fresh responses, all four replay endpoints, preflight, internal retries, direct/mixed history and service-role projections; preserved v4 tuples/attempts, exact distinct v5 tuple, unknown-version rejection and no hidden-row leak or extra provider request.         |
| iOS persistence and presentation | Generated decoder parity; disk migration from the outgoing schema and supported recent plans; relaunch/history/queue recovery; broader-rank display; typed/boolean override cannot promote rank; validated confirmation replacement/clear survives across devices with AI confidence unchanged. |
| Repository gates                 | `make validate-edge-dto-contract`, complete affected Supabase tooling/Edge checks, recursive type checks, disposable-database/catalog gates, and affected iOS build/test gates through `make ios-local-build`. Run web/admin package gates if those consumers change.                           |

Canonical API/database documentation, owning READMEs and release procedures are
updated with each implementation slice, without claiming deployment. The design
review below records the original planning evidence; implementation evidence is
recorded separately above.

The offline design received a read-only source trace and independent contract
review. Review corrections explicitly cover the closed provider-binding SQL
constraints and native confirmation/override recovery. The correction review
found no remaining concrete blocker. Changed-Markdown formatting, 249 local
file-link targets and diff whitespace checks passed; these are documentation
checks, not evidence that the proposed runtime behavior exists.

## Slice 2 native checkpoint — 2026-09-29

The native implementation now carries the reserved primary snapshot through
live/queued persistence, owner history and reopening. V52 was frozen and
compiled before adding the two optional V53 fields. The existing primary label
and rank survive typed review; a genus/family caption communicates the supported
level without adding a confidence badge. Required missing or malformed metadata
stays invalid. Duplicate explicit completion validates immutable identity and
preserves saved review/media state. Broader answers cannot gain species
hydration, alternatives, novelty credit or species statistics from legacy IDs,
boolean review or a typed override. History clears stale species taxonomy and
reference caches.

This is a native checkpoint within Slice 2, not completion of that slice.
`confirmedSpeciesIdentityData` is reserved storage with no trusted writer or
reader yet. Remaining work is the server-validated, revisioned confirmation
response/history/recovery contract (including replacement and clear), and the
reviewed public/share/export and species-only server consumer projections.
Existing independent confirmations must be preserved when implementing those
owners. No raw UUID or boolean is sufficient proof.

Protocol remains 4 and all model profiles/assignments remain unchanged. No new
producer, paid evaluation, calibration or production operation is authorized by
this checkpoint.

Local verification completed on 2026-09-29:

- The frozen V52 model compiled before the active V53 fields were added. Pinned
  XcodeGen 2.45.4 regenerated the project; source membership and
  migration-source guardrails passed, including their mutation tests.
- The complete native unit target and four critical scan UI smokes compiled and
  ran through `make ios-local-build` on the existing iPhone 18 Pro Max
  simulator. XCResult reports 4,556 passed, one failed and zero skipped. The
  sole failure was an architecture assertion that still searched for the old
  biological-result predicate. It now requires the stricter species-level
  predicate. The unchanged production code passed the new primary-identity
  cases, the V52 disk upgrade and reopen fixture, all migration tests and all
  four exact scan UI smokes.
- After that test-only correction, the complete Inference Architecture suite
  passed all 17 tests with zero failures or skips. The full-run bundle is
  `.artifacts/local-ios/5b3312db65bd400abdf949ac9e74bf49.xcresult`; the
  corrected suite's bundle is
  `.artifacts/local-ios/903065fefadc4d3385d433c932a51619.xcresult`. The full
  native suite was not repeated after changing that single assertion.
- `make test-ios-ci-tooling`, generated-project/source-membership checks,
  event-routing, privacy-manifest, transport-security, versioning and migration
  guardrails passed. `make validate-edge-dto-contract` passed generation,
  ownership and runtime decoder checks. Changed-Markdown formatting and diff
  whitespace checks passed.
- Independent read-only review found no remaining native contract or
  data-integrity blocker after duplicate-completion, provenance, taxonomy-cache
  and deterministic-encoding corrections.

Hosted exact-SHA CI, a Release archive and the genuine released-V52 install-over
and second-launch check remain release gates. This checkpoint is local
implementation evidence and does not complete Slice 2 or authorize production
activation. No paid model requests or production mutations were performed.

### Remaining consumer checkpoints

1. **Validated review authority — implemented locally.** The backend checkpoint
   below prepares this authority; deployment and native consumption remain
   separate. Use a service-owned confirmation mutation that obtains accepted
   SPECIES proof through the existing verified taxon resolver; a client-provided
   UUID, name, GBIF key or review flag is input, never proof. Preserve legacy
   review fields. Persist a bounded canonical identity plus a monotonic revision
   on the scan and its owner-bound job backup. Omission means an older
   projection; an explicit clear must carry a newer revision. Never accept this
   authority in client `recovery_scan` JSON.
2. **Native confirmation acknowledgements — implemented locally.** Return a
   typed server response from review synchronization and merge only
   authoritative non-stale revisions into history and the reserved V53 bytes.
   Encode revision and nullable identity together inside that envelope so a
   clear survives reopening without another persisted field. Keep pending local
   review separate from effective species identity. Test stale responses,
   same-revision conflicts, replacement, clear, second-device history and
   missing-row recovery while preserving the AI answer and its confidence
   metadata.
3. **Shared consumers — implemented and locally verified.** Complete rank-aware
   Share/Explore and public web projections, Field Chat context, immutable DwC-A
   exports, FieldTrip credit and reference-image promotion. A broader
   observation remains representable without acquiring species-only effects.
   Existing community consensus is a separate authority and cannot be silently
   treated as a verified species.

These checkpoints require ordinary implementation and contract review, not a new
model experiment. Only after all Slice 2 acceptance gates pass may native
capability 5 and the separate Slice 3 producer qualification advance.

## Slice 2 backend review checkpoint — 2026-09-29

The prepared `confirm-scan-species` endpoint and
`20260929170458_prepare_verified_scan_species_review.sql` provide independent
species confirmation for the reserved explicit-primary contract. The owner is
derived from authentication. A client supplies an action, scan, expected
revision and optional selected name; IDs, taxonomy and review flags are not
proof. Fresh bounded GBIF verification and the existing non-AI request counters
precede every confirmation, including dictionary hits. Clear needs no external
service. The service-only transaction materializes/reuses an accepted species
and takes its saved canonical name from the dictionary row.

Original AI rank, names, confidence, explanation and provenance remain
unchanged. A verified selected taxon is not evidence that the observation
depicts it and does not calibrate an AI score. Current Sol/Gemini assignments,
prompt profiles, explanation format and confidence labels are unchanged.

The scan stores nullable `confirmed_species_identity` and a monotonic revision;
the ingestion job stores `confirmed_species_review`, a bounded version-1
envelope including the four legacy review fields. This additional backup detail
preserves pending review intent and ensures a server clear wins over stale
client recovery JSON. Existing boolean semantics are retained: `ai_confirmed`
true, `user_overridden`/`unreviewed` false. Confirmation, replacement, clear and
legacy invalidation are ordered independently of immutable AI completion. An
exact one-revision retry returns the saved receipt; other stale or conflicting
writes return 409 and require reconciliation.

Legacy/client/community edits on explicit-primary rows clear both stale identity
and confirmed FK while preserving review intent. Broader primaries have no
original species FK, so legacy booleans cannot satisfy the existing Field Trip
effective-species lookup. Missing-row recovery restores only the exact owner
backup, including authoritative clear. Original completion remains first-write
wins. Account merge carries the backup into a compatible target job and rejects
conflicting generation metadata; deletion and owner removal clear it. This does
not promote community taxonomy into this new authority.

This is still a checkpoint within Slice 2. The native app has no new endpoint
caller or confirmation acknowledgement/history merge yet. Its V53 reserved bytes
remain unused and protocol stays 4. The versioned review envelope will supply
both revision and nullable identity to that next checkpoint. Public/share/export
and other species consumers remain to be completed before capability 5 or a new
producer is enabled. Current legacy observations continue through the old review
RPC; there is no historical backfill.

The canonical
[API](../backend-and-data/05-api-contracts.md#prepared-species-confirmation-endpoint),
[database](../backend-and-data/04-database-schema.md), and
[endpoint](../../services/supabase/functions/confirm-scan-species/README.md)
documents define this prepared contract. Source deployment coverage includes the
new route in dependency planning, the fleet inventory and the critical
unauthenticated POST/401 handler smoke. This work introduces no production
mutation, provider request or model benchmark.

Local verification for this backend checkpoint:

- Clean sorted replay with pinned Supabase CLI 2.109.1 and all 69 discovered
  database fixtures passed (454 assertions). This includes the original primary
  contract, actual-role denials, review/clear recovery, duplicate completion,
  conflicting and compatible account-merge backups, and deletion cleanup.
- The complete Edge suite passed 2,201 tests and 343 nested steps with zero
  failures and no ignored tests, using the disposable loopback database. Both
  new two-connection review races ran: identical retries collapse; different
  selections at the same revision conflict and roll back materialization.
- Recursive checks passed for all 103 deployed entrypoints using their generated
  function configs. Dependency/config isolation, complete Supabase tooling,
  executable DTO validation and migration-contract gates passed. Final updated
  deployment/documentation contracts also passed their 58-test run. No Swift
  generated block or native source changed in this checkpoint.
- The reviewed out-of-order migration recovery gate passed all three required
  fixtures (21 assertions). Database lint passed with no findings. Security and
  performance advisors passed the repository's error gate; they still report
  warnings, so this is not a claim of a warning-free database.
- Independent read-only review found no remaining blocker after review-flag,
  canonical-name, duplicate-completion, account-merge and release-smoke
  corrections. Changed Markdown was formatted, its local links checked, and diff
  whitespace verified.

These are local checks. Hosted exact-SHA CI, deployment and native/installed-app
verification of the future confirmation consumer have not run for this
checkpoint. No new paid model benchmark was needed or performed.

## Slice 2 native review checkpoint — 2026-09-29

Native explicit-primary reviews now use the prepared `confirm-scan-species`
endpoint. Legacy observations keep the existing review RPC. The request conveys
selection and expected revision only; it carries no client taxon proof. Local
intent is saved before sending and remains separate from verified authority.
Only a validated acknowledgement or owned history projection can write the V53
confirmation envelope. Replacement and clear retain their monotonic revision
across reopening. Original AI rank, names, explanation, confidence and
provenance remain unchanged.

History distinguishes omission from explicit null, rejects malformed partial
projections, ignores older revisions and fails same-revision conflicts. A 409
refreshes current owned authority once; it does not retry the action at a newer
revision. Missing local rows restore the same envelope from owner history. The
review write tail fences displaced UI actions and is drained by Auth before
account replacement. History and native review writes share a synchronous gate
and fresh ModelContexts around fetch/merge/save, preventing cross-context stale
writes. Failed preparation cannot call the server or publish pending state;
failed verification cannot manufacture a confirmation.

This checkpoint consumes the previously reserved V53 field and adds no persisted
field or schema migration. It leaves shared species-only eligibility unchanged.
Protocol remains 4 until Share/Explore, public web, Field Chat, exports,
FieldTrip credit and reference promotion complete their remaining Slice 2 work.
No new provider/model assignment, confidence threshold, paid benchmark or
production operation is part of this checkpoint.

Local verification for this native review checkpoint:

- The focused app build and eight native suites passed all 86 tests. Coverage
  includes strict request/receipt decoding, 401/409/503 no-replay behavior,
  revision conflicts, pending-intent separation, history and acknowledgement
  races, disk reopening after replacement and clear, failed local preparation,
  superseded actions and Auth draining a suspended local apply.
- The complete native unit target and four exact critical scan UI smokes ran
  through `make ios-local-build` on the existing iPhone 18 Pro simulator.
  XCResult reports 4,572 passed, two failed and zero skipped. Both failures were
  stale architecture inventories: the species-model file list and network
  session-recovery opt-out owners. Both now explicitly include the reviewed new
  owner, preserving their exact-inventory checks. No behavioral test or UI smoke
  failed. Xcode then timed out while collecting simulator diagnostics after all
  tests had finished; the completed result bundle remains readable.
- After those test-only corrections, both complete architecture suites were
  recompiled and passed all 17 tests with zero failures. The full-run evidence
  is `.artifacts/local-ios/ce74ff47dd0b41989b76fde398a4b6cb.xcresult`; the
  corrected suites' evidence is
  `.artifacts/local-ios/4bb29ca542c54bd9a2397c8565b43a30.xcresult`. The full
  suite was not repeated after these two inventory-only corrections; production
  source did not change between these runs.
- Executable Edge DTO validation and complete Supabase tooling passed; the
  tooling uses local fixtures and made no paid model requests. iOS project,
  event-routing, privacy, transport, versioning and migration guardrails passed,
  as did the complete portable iOS tooling suite.
- Independent read-only review found no remaining blocker after the shared
  fresh-context transaction gate was added. Pinned XcodeGen regenerated the
  seven new Swift files' project membership without changing project settings.
  Changed Markdown formatting, the exact Edge/scripts formatting gate, local
  documentation links and diff whitespace checks passed.

Hosted exact-SHA CI, a Release archive and installed-app deployment/upgrade
verification remain release gates. The native protocol stays 4 while shared
consumers are completed.

### Shared-consumer checkpoint — 2026-09-29

The consumer audit found service projections using the legacy
`COALESCE(confirmed_species_id, species_id)` convention. The following
coordinated scope is implemented locally. Protocol 4 and current producers
remain unchanged after the local acceptance gates below; production release
gates remain separate:

1. Define one server-owned effective-identity policy for explicit results. Reuse
   the stored primary/provenance validators and full verified-review validator.
   Preserve original AI rank and labels separately from a current verified
   species selection. A bare ID, optimistic flag, typed name or community genus
   outcome cannot supply verified species authority. Legacy observations retain
   their existing behavior.
2. Apply that policy to Share admission, Explore cards/detail and public web
   projections. Valid broader observations must remain shareable and retain
   their group labels without acquiring a species association or species
   reference gallery. Update the corresponding native/web DTO and presentation
   contracts together; expose only the public labels and rank needed by those
   readers.
3. Apply the same distinction to Field Chat context and new DwC-A snapshots.
   Chat must distinguish the original AI answer, a verified selection and
   pending or community review. Exports must retain the supported primary rank
   without inventing a species ID. Previously materialized export rows remain
   immutable.
4. Update Field Trip evidence and reference-image promotion with the same
   eligibility policy. Field Trip receipt revision inputs and update-trigger
   columns must include the new authority and revision so replacement and clear
   withdraw or recompute cached credit. Complete native confirmed-identity
   presentation and enrichment without relabeling the original AI score or
   alternative candidates.

The current owners are `share-scan-to-explore/db.ts`,
`explore_projected_post_cards`, `get_explore_post_detail`, the
`get_public_web_explore_*` RPCs, `insight-chat` selection/eligibility/prompt,
`internal.dwca_export_snapshot_source`, `field_trip_scan_evidence_is_eligible`
and its progress receipt/trigger, and `refresh_merian_reference_images`. Public
web currently maps the projected labels; active admin dispatch uses named admin
RPCs and has no independent direct scan projection to widen.

Acceptance covers valid species/genus/family/unresolved results; verified
selection, replacement and clear; pending and community review; legacy rows;
malformed present authority; missing-row recovery; and unchanged existing export
jobs. Run actual-role database fixtures, the affected Edge/DTO/native/web gates
and the complete required surface gates before advertising capability 5. This
checkpoint needs no new paid model benchmark.

## Shared-consumer implementation decisions

Migration `20260929192008_apply_primary_identity_to_shared_consumers.sql` and
`_shared/identify/effectiveIdentity.ts` evaluate saved primary/provenance and
full revisioned review authority. Explicit malformed authority fails closed;
legacy observations keep their historical behavior. The original AI rank,
labels, score, explanation and candidates remain immutable.

Public card queries retain their existing invoker and row-policy boundary. They
derive source and labels from stored fields covered by validated provenance,
primary shape/subject and review CHECKs; private policy helpers remain
service-only. No schema access, table grant or definer authority is added.
Actual-role fixtures preserve anonymous denial and owner-only direct reads,
while service projections retain viewer blocking and privacy filters.

Explore cards add only the optional public `identification` label projection:
version, current rank/source and original rank/names. No review envelope, model
configuration, score or private context is added. Feed, map, detail and web
labels distinguish broader groups, observer selection and community labels.
Broader/community projections do not borrow species name preferences or species
reference imagery. Share and Field Chat support valid unresolved biological
observations as well as named taxa, without inventing a species association.

Native Insight shows a separate **Your selected species** section. **View
species details** opens the existing dictionary route and its enrichment owner.
It does not overwrite the original scan's taxonomy, hazard, imagery or AI
confidence. Native species totals accept the verified identity; their cache
fingerprint observes in-place confirmation, replacement and clear.
Taxonomy-based native achievement evidence remains tied to the original
qualified result.

Field Trip receipts include primary/provenance, full review/revision and the
effective species ID. Replacement first withdraws mismatched completed regular
and Event contributions before recomputing, preserving saved goal preferences.
Clear cannot retain the old credit. Reference-image promotion still requires
qualified original AI metrics; explicit rows must have original species rank and
that original species must match the effective association. Taxonomy
verification alone does not establish that a photograph depicts that species.

New immutable DwC-A snapshots include rank/name/selection source. Existing
snapshot rows are never rewritten. The archive retains its existing 20-column
format, including resumed jobs with previously uploaded chunks. New explicit
rows preserve broader names in the scientific-name and genus/family fields and
rank/selection wording in `identificationVerificationStatus`; historical rows
retain their original numeric/blank status. A dedicated `taxonRank` column is
deferred until an independently versioned archive format exists. No export is
activated by this change.

No paid provider calls are needed for these contract checks. This checkpoint
does not qualify a new producer, change the current Sol/Gemini assignments,
advertise protocol 5, or authorize deployment.

### Shared-consumer verification — 2026-09-29

- Rebuilt the dedicated disposable PostgreSQL 17 database from the complete
  migration history with pinned Supabase CLI 2.109.1. All 70 pgTAP catalogs
  passed: 463 assertions. Database lint found no schema errors; the privileged
  routine audit found zero violations across 270 definers.
- Complete Edge suite: 2,211 tests and 343 steps passed, with the disposable
  database explicitly configured so integration tests could not silently skip.
  Actual-role tests preserve anonymous `42501` denial, owner-only direct reads,
  cross-owner denial and service viewer-blocking. They cover explicit ranks,
  legacy confirmations, Human/placeholders, community species equality/mismatch
  and genus labels, selected identity and clear. Regular and Event Field Trip
  tests confirm replacement and clear withdraw completed credit.
- Recursive checks passed for all 103 Edge entry points. Complete Supabase
  tooling, 360 migration-contract tests, dependency/deployment identity and
  generated Edge/captured-media DTO gates passed. Backend formatting and lint
  passed.
- Native focused integration tests passed 72 cases. The complete unit target and
  all four required scan UI smokes then passed 4,578 tests with zero failures or
  skips in `.artifacts/local-ios/a3f208c3524144c8a139dc90bcb88102.xcresult`. A
  final review aligned iOS unknown-key rejection with the web decoder; the
  rebuilt decoder and ownership suites passed all five tests in
  `.artifacts/local-ios/7c5622487e3e4ea4b23bead882641656.xcresult`.
  Generated-project changes were regenerated with pinned XcodeGen and reviewed.
  Native project, event-routing, privacy, transport-security, versioning,
  migration and portable CI-tooling gates passed.
- Public web passed all 76 tests, type checking and the production build on
  Node 24. Dependency audit found zero vulnerabilities. Read-only native/web and
  database contract reviews were completed and their actionable findings
  resolved.

This completes the shared-consumer source checkpoint. Keep native protocol 4 and
the current Sol/Gemini assignments and confidence policy. The signed
archive/distribution and install-over verification remain release gates; local
simulator evidence does not replace them. Capability-5 readiness and the
separate explicit-producer qualification remain the next planned work. No hosted
mutation, push, paid model evaluation or export activation was performed for
this checkpoint.

## Capability-5 reader preparation — 2026-09-29

The native reader now advertises identification protocol 5. This supersedes the
protocol-4 holds in the earlier implementation checkpoints above. Preflight,
prepared/live requests, auth and transport retries, and SDK history/recovery
reads use the same capability owner. Entitlement protocol remains 3.

Native preflight accepts exact known minima 0, 4 and 5; OpenAI requires 4 or 5.
Current minimum-4 OpenAI and minimum-0 Gemini assignments remain compatible.
Unknown ready minima still fail closed, and server permission/update decisions
retain their existing behavior. There is no arbitrary greater-version fallback.
No binding minimum, profile, model, prompt, confidence policy or consent rule is
changed by this reader checkpoint.

The existing additive backend already preserves accepted capability 5 in new
attempts and derives internal retry capability from the original saved attempt.
Its current-reader gates require exactly 5 for explicit-primary results,
including stored replay and mixed history, after visibility checks. Old attempts
are not upgraded by worker headers. The added disposable regression covers
Gemini text, audio, mixed photo/audio and sampled-video assignments with readers
4 and 5 and verifies headerless retries retain accepted capability 5. Existing
OpenAI, unknown-version, immutable replay and legacy-reader tests remain active.

Deploy the additive backend migrations and Edge bundle before distributing a
capability-5 app. A backend limited to protocol 4 can reject its preflight or
inference requests. The signed archive/distribution and installation over the
previous released build remain separate release gates, including preservation of
saved observations and successful launch.

The next source milestone is Slice 3's isolated explicit-primary OpenAI
candidate and offline checks. The reserved schema still has no admitted
producer. A new paid comparison needs its own bounded plan and authorization;
the completed eighteen-call experiment cannot be reused. Qualification and a
separate exact minimum-5 production tuple must precede any new assignment.

### Reader-readiness verification

- Native focused compatibility/recovery suites passed all 60 tests in
  `.artifacts/local-ios/be8e73f2e3e24899bc1367e87de86c36.xcresult`. The complete
  native unit target and all four required scan UI smokes then passed **4,578
  tests**, with zero failures or skips, in
  `.artifacts/local-ios/4f51317a7cf8447f8f57d38a1f92f2ed.xcresult`.
- Complete Edge suite: **2,211 tests and 343 steps passed**, with the disposable
  database explicitly enabled. All 103 Edge entry points passed recursive type
  checks. Generated DTO checks, all 360 migration-contract tests, complete
  Supabase tooling, backend formatting and lint passed.
- The first catalog run encountered an existing Field Chat activation fixture in
  the reused local database. Rebuilding that dedicated disposable database from
  the full migration history restored the required fresh baseline; all **70
  catalogs and 463 assertions passed**, and database lint found no schema
  errors. No production database was used or changed.
- XcodeGen regeneration produced no project diff. Native project, event-routing,
  privacy-manifest, transport-security, versioning and migration-source
  guardrails passed. Changed Markdown was formatted, 685 local documentation
  targets resolved, and diff whitespace checks passed.
- Independent read-only native and backend/release-contract reviews completed
  with no remaining blockers. Current provider binding minima remain 0 and 4;
  native recognition of future minimum 5 grants no assignment authority.

This completes Slice 2's local reader and consumer preparation. Hosted exact-SHA
CI, a signed archive and the previous-release install-over check remain release
evidence to collect through the canonical procedure. No push, deployment,
provider activation or paid model request was performed for this checkpoint.

## Isolated explicit-primary candidate — 2026-09-29

Slice 3 now prepares a new `openai_photo_sol_primary_low_v1` experiment. It uses
`gpt-6-sol`, low reasoning, high image detail, 8,192 output tokens and the
existing photo moderation request. Current production, Gemini and historical
experimental profiles retain their original definitions. In particular,
`openai_photo_sol_rank_limits_low_v1` remains the completed, unqualified
experiment; its results and budget do not apply to this new candidate.

### Implemented offline boundary

- `openaiSolPrimary.ts` owns the exact evaluation snapshot and pure photo
  request projection. Its binding is `openai_sol_primary_evaluation_v1`, its
  prompt is `openai_identify_vision_primary_v1`, and its private provider schema
  is `merian_openai_primary_evaluation_v1`. This schema is deliberately distinct
  from the reserved durable `merian_identify_primary_v1`. Neither a production
  registry entry nor a live evaluation runner admits this profile.
- `openaiSolPrimaryContract.ts` derives a separate strict model contract from
  the unchanged common contract. It requires a resolution and explicit nullable
  names. Species alternatives require `taxon_rank: "species"` and contain zero
  to two entries; other resolutions require null alternatives and pet details.
  Unknown/missing keys and contradictory subject/name states fail validation.
  OpenAI schema generation and strict decoding consume the same executable
  contract. The generic decoder export does not expand any binding allowlist.
- `openaiSolPrimaryInstructions.ts` replaces exact baseline directions that
  previously forced a species and two alternatives. It asks for the most
  specific visually supported rank, a matching group common name and observed
  support. It distinguishes an unseen feature from an absent feature, preserves
  supported species answers and keeps the existing 1–3 sentence explanation
  format.
- `openaiSolPrimaryNormalization.ts` applies the existing pure normalization,
  then constructs the versioned primary snapshot. Processed-material demotion
  changes resolution to non-biological and clears species-only details. Other
  contradictions fail. Eligible dog/cat canonicalization remains confined to
  species answers, and minerals preserve their non-biological names. The helper
  produces only an in-memory evaluation result: no durable provenance,
  dictionary lookup, species association, network request or retry.

The candidate rejects explicit hybrid, cultivar, infraspecific and uncertainty
markers (`sp.`, `spp.`, `cf.`, `aff.`) in primary and alternative names rather
than turning them into a species claim. This syntax check cannot prove rank or
identify an unmarked infraspecific name. The declared resolution is never
inferred from name length; a reviewed taxonomy and diagnostic evidence remain
necessary for quality assessment and, later, accepted-species linking. Existing
canonical domestic dog/cat aliases have deterministic compatibility fixtures,
not new biological accuracy claims.

The schema follows OpenAI's requirement for a closed object with required keys
and nullable values. Structured output constrains format, not biological truth;
the candidate still needs visual and taxonomic evaluation. See the official
[Structured Outputs guidance](https://developers.openai.com/api/docs/guides/structured-outputs),
reviewed on 29 September 2026.

### Preparation identity and remaining qualification

The offline tests lock these content-free SHA-256 values:

| Value                  | Digest                                                             |
| ---------------------- | ------------------------------------------------------------------ |
| Instructions           | `f3800507909d5a9087092956690e2f75cc104fd79f07b399d5227f086f5bb5d8` |
| Provider format/schema | `bb764f5a97c4d6a21e67aeeaae71d0cd73c9e54e69135ceebf92996c7960a9fb` |
| Evaluation snapshot    | `490e03841632b7209833ca2676c89e60d66a2b2b7fa5e83f37222611763999a3` |

The next step is an offline comparison plan with reviewed reference coverage for
all five resolution states, species lookalikes, mineral/object controls and pet
naming. Freeze candidate/control request identities, interpretation rules and
assistant explanation review criteria before a new bounded spending approval. Do
not reuse the completed eighteen-call plan or relabel old model output as this
profile. The future live decoder must retain exact-model, native moderation,
timeout, output-size and one-invocation controls before releasing this different
draft type. Its new durable runner must retain claim/restart and content-free
record rules.

No quality improvement, confidence threshold or Free/Pro model split is
qualified by these synthetic tests. The current Sol profile remains selected for
both tiers. Production admission would require its own exact minimum-5 tuple
after qualification, followed by the existing authorized deployment/activation
path.

### Offline candidate verification

- All **21 focused candidate tests passed** with network and environment access
  denied. They cover the five resolutions, required/unknown fields, species
  alternatives, contradictory flags, processed material, mineral/preserved
  specimens, domestic pet aliases, unsupported name markers and the final wire
  contract. The new profile is rejected by production assignment/result policy
  and historical request builders. Configuration hashes are locked.
- The existing and new OpenAI adapter tests plus the historical Sol rank tests
  passed together with network and environment denied. Historical rank prompt
  and schema fingerprints still match the completed experiment.
- The final complete Edge suite passed **2,232 tests and 343 steps**, including
  the dedicated disposable database after a fresh migration reset. All **103
  Edge entrypoints** passed recursive type checks; dependency/configuration
  validation and all **360 migration contract tests** passed.
- Independent read-only review found an uncertainty-qualifier gap; the decoder
  now rejects leading, internal and trailing `sp.`, `spp.`, `cf.` and `aff.`
  tokens before normalization, with regression coverage. The reviewer confirmed
  closure and found no remaining blockers.
- The identification bundle fingerprint was regenerated with its checked-in
  generator because the shared strict-decoder export changes that source graph.
  The generated diff contains only the digest; it changes no provider selection.
- Complete Supabase tooling passed: 470 standard tests, 103 isolated evaluator
  tests, generated Edge/captured-media DTO validation and all 12 shell suites.
  Backend formatting and lint passed. All changed Markdown was formatted and its
  80 local documentation targets resolved. Diff whitespace checks passed.

No native client, SQL migration, production model assignment or current
confidence presentation changed. No paid request, hosted mutation or deployment
ran. These checks establish the offline candidate's implementation, not model
quality or release qualification.

## Explicit-primary comparison packet — 2026-09-29

The
[preparation checkpoint](identification-sol-primary-comparison-preparation-2026-09-29.md)
now freezes twelve no-description photos and both candidate/control request
projections. Nine cases are retained from the completed experiment; new reviewed
public images cover domestic dog, domestic cat and a provisional unresolved
biological subject. All six earlier challenges remain. The schedule proposes six
candidate screens and six alternating pairs, with no paid requests run.

Coverage includes all five resolution states. Four references are limited, and
family/unresolved biological have no usable provisional identity reference
beyond those limits. Those cases can exercise uncertainty and explanation
behavior; their identity mismatches remain unassessable without further
evidence. The lookalike review binds a distinct comparison species without
adding it to the accepted answers. The current explanation rubric and format are
preserved.

The new offline builder uses separate plan/review contracts, immutable private
copies and a completion receipt written last. Its report records no dispatch,
live readiness or quality qualification. Prior source inputs, paid journals and
historical profiles remain unchanged. Next is the separate live adapter and
durable evaluation/scoring path, followed by current pricing and a bounded
execution authorization. Confidence calibration remains later work.

## Explicit-primary comparison runner — 2026-09-29

The
[bounded runner checkpoint](identification-sol-primary-comparison-preparation-2026-09-29.md#bounded-runner-implementation--2026-09-29)
now implements the separate strict decoder transport, explicit-resolution
records and eighteen-call controller. The candidate records its normalized
explicit rank; the baseline gets rank only from a finite catalog mapping.
Cross-rank mappings fail, while unknown names stay unassessable. Predeclared
limited references may allow screening to continue but receive no quality-pass
credit. Unsupported visual explanations remain failures.

Current pricing, a new bounded plan and fresh exact-source authorization are
still required for execution. No new model calls, production assignment changes
or confidence thresholds are part of this implementation checkpoint. The
original explanation format and current Sol Free/Pro assignments remain intact.
