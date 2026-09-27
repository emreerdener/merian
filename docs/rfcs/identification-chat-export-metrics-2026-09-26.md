# Identification metrics in Field Chat and exports — 26 September 2026

Status: implemented and locally verified. Production assignment remains Gemini.

## Behavior

Private scan Field Chat fetches the saved inference tier and immutable result
provenance behind the existing owner check. A pure shared compatibility policy
matches the SQL/native qualified Gemini configurations, including policy version
1 and exact keys. Historical SQL-null provenance keeps its existing meaning;
missing or unknown present metadata cannot qualify.

Answers, prompt suggestions, and field-note summaries omit unfamiliar primary,
candidate, sex and invasive confidence values and provider image-quality scores.
Descriptive candidate names/features, stored observations, reasoning, review and
confirmation remain available. Candidate projection is bounded and allowlisted;
it does not pass unknown nested fields or scores. Local blur/zoom measurements
retain their existing meaning. Full provider configuration is not added to the
prompt. Field Chat itself continues using Gemini.

New Darwin Core export jobs freeze a private `ai_confidence_qualified` boolean
beside the original score in their creation-time occurrence DTO. The worker
requires a boolean when present, retains legacy behavior for old immutable
snapshots without the field, and leaves `identificationVerificationStatus` empty
for unqualified scores. This preserves the existing export column contract; it
does not claim the retained Gemini score is a calibrated verification status.
Both personal and global exports use the same rule. Existing snapshots and
source scores are not rewritten; later scan edits cannot alter a job's frozen
meaning. Full execution metadata is not projected into the archive.

## Rollout

Apply the forward export-view migration and deploy the updated worker together
before any alternative results can exist. The worker tolerates pre-migration
snapshots, while an old worker would ignore the new qualification field. All
current results remain Gemini. The existing snapshot bounds, owner/lease fences,
privacy invalidation and download controls remain in force.

This implementation performs no paid inference or hosted mutation. Benchmarks
are unchanged. Provider-aware accounting and explicit unknown-price coverage are
implemented in the
[following slice](./identification-provider-usage-attribution-2026-09-26.md).
Shared content-cache qualification remains before assigning a different
provider; actual alternative-provider activation still needs a matched qualified
benchmark, appropriate disclosures, supported clients, and an explicitly
authorized release.

## Verification

- All 44 focused deterministic prompt/export tests passed. Four real database
  tests passed for SQL/TypeScript parity, registered and altered profiles, and
  frozen export creation followed by later score edits and authorized page
  reads.
- Fresh complete migration replay passed. All 61 database catalogs passed (397
  assertions); database lint returned no warnings. Security/performance advisor
  error gates passed with the existing warning reports.
- Complete Edge suite passed with the disposable database connected: 2,126 tests
  and 265 steps. All 101 deploy-config entry points passed recursive type
  checks, as did whole-tree format/lint, isolated dependency graphs, generated
  Identify contracts and migration contracts. Field Chat identity was
  regenerated, its three changed hashes reviewed, and independently recomputed.
- Complete tooling passed after updating the additional strongly typed synthetic
  Field Chat evaluator fixture for SQL-null provenance: 438 standard tests/32
  steps, 58 isolated evaluation tests/29 steps, 19 DTO tests, 21 contract tests,
  and all ten shell suites. No native or public web source changed in this
  slice.
- Independent read-only review found no runtime, privacy or immutability
  blocker; its verification-record and shared ownership-map documentation
  findings were corrected before handoff. No live model request or hosted
  operation ran.
