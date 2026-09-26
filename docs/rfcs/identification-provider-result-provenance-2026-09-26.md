# Durable identification result provenance

Date: 26 September 2026\
Scope: Production-integration sub-slice, server-side result configuration\
Status: Implemented and verified locally. Not deployed.

Every new successful identification records which admitted provider/model and
configuration produced it. This follows
[independent consent infrastructure](./identification-provider-openai-consent-2026-09-26.md).
Production routing remains Gemini-only and OpenAI consent collection remains
disabled. This work adds no model call and requires no repeat paid benchmark.

## Durable boundary

The four Identify producers project `result.execution`, which the shared
executor attaches from the registry's immutable admitted snapshot. They never
read provenance from model JSON, request JSON or current configuration after the
call. `provenance.ts` explicitly selects each field rather than spreading an
arbitrary object.

The version-1 value contains provider, binding, requested model, modality
variant, quota operation and policy version, prompt/schema/confidence reference,
both diagnostic thresholds where applicable, safety profile, timeout and
configured generation values. Explicit null means a setting was left to provider
defaults. It does not promise reproducible inference: provider internals and
aliases can change. Returned model strings, prompts, response content, evidence,
coordinates, account/attempt IDs, durations and usage are excluded.

`scans.identification_provenance` is nullable and bounded to 2 KiB with exact
keys, bounded identifiers and numeric types/ranges. It intentionally has the
same visibility as the scan through the existing Data API, including publicly
readable live open scans. These configuration facts are suitable for that
visibility. It is not a place for private operational metadata. Curated public
Explore/web projections remain unchanged.

The scan insert and its exact owner/scan ingestion-job backup commit together.
Missing or conflicting backup jobs reject a new provenance-bearing insert. Both
copies reject subsequent changes. Duplicate scan insertion leaves the winning
result/configuration intact. Independently admitted retries still resolve a new
snapshot; the system does not pin a logical scan to a configuration before it
has a durable result.

## Recovery and historical compatibility

The existing client recovery payload and RPC remain unchanged. Before inserting
a scan with absent provenance, the database can restore only an exact server job
backup. Client-supplied provenance is not parsed by the recovery RPC. Existing
recovery authorization, deletion tombstones and completion fences still apply. A
result that never reached the scan-insert transaction has no durable provenance
receipt; recovery preserves null rather than inferring a provider.

Legacy scans and jobs remain null. A provenance value cannot be retroactively
added to an existing scan. Completed response replay and reconstruction perform
no inference and do not rewrite either record. The ordinary replay worker's
newly authorized execution gets a fresh snapshot from its current admission.
Quota-record expiry cannot remove the durable configuration.

Owner merges preserve configuration while reparenting existing rows. Account
removal cascades the job with its Auth owner; retained scientific scan
tombstones retain content-free configuration under their existing visibility. No
new user identifier or separate retention store is introduced.

## Release order and rollback

Apply `20260926160249_persist_identification_result_provenance.sql` before
publishing the four updated Edge Functions. Old producers remain compatible with
nullable columns and omit the field. New producers require the new schema;
publishing them first would fail scan insertion. No app update is required.

Rollback to the previous Edge code preserves recorded values. Keep the additive
migration and evidence; do not clear provenance or rewrite historical rows.
Deployment still requires the canonical exact-SHA release controls and explicit
operation/target authorization. Nothing was deployed or published for this work.

## Verification

Validation used Deno 2.9.4 and Supabase CLI 2.109.1. Final checks passed:

| Check                                         | Result                                                                                                          |
| --------------------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Clean migration replay                        | All migrations applied in a task-owned disposable database                                                      |
| Database security catalogs                    | 56 files, 392 assertions passed                                                                                 |
| Complete Edge suite with database integration | 2,102 tests and 245 steps passed                                                                                |
| Focused provider and provenance checks        | All four producers, generation projection, bounded fields and completed replay passed                           |
| Migration contracts                           | 350 tests across 62 discovered files passed                                                                     |
| Complete Supabase tooling                     | 438 standard tests, 58 isolated evaluation tests, both DTO suites and all 10 shell suites passed                |
| Recursive Edge type/config/dependency checks  | 101 entrypoints and isolated graphs passed                                                                      |
| Privileged routine audit                      | 260 public definer routines, zero violations                                                                    |
| Database lint                                 | No schema errors or warnings                                                                                    |
| Security/performance advisors                 | No errors; unchanged 105 security and 80 performance warnings on existing objects, none on this slice's objects |
| Formatting, lint and generated identities     | Functions/scripts checks, changed Markdown, DTO validation and generated deployment identity checks passed      |

The new database catalog exercises real role privileges, atomic backup and
rollback, duplicate preservation, immutable scan/job values, forged recovery
metadata, legacy null recovery, existing authenticated metadata updates, public
scan visibility, scientific tombstones and Auth-owner cleanup. Independent
read-only review found no remaining implementation blocker; its documentation
drift finding was corrected in the same change.

No Swift or app wire changes were made, so no iOS build or device test was run
for this slice. No hosted mutation, paid provider request or benchmark rerun was
performed. Validation used the reviewed checked-in skills; the previously noted
user-level Supabase skill-link drift was left unchanged. The task-owned database
and test volume are removed after verification, preserving unrelated local
containers.

## Next slice

Add recipient-aware runtime admission and inference/reapproval behavior, then
wire qualified confidence interpretation into the owner/client consumers with an
appropriate SwiftData migration. This slice deliberately does not add an
Identify DTO field, local-store field, new confidence scale, provider-price
mapping, model selection or automatic failover. OpenAI activation still needs
those consumer/accounting contracts, held-out qualification and the published
recipient disclosure. The existing benchmarks remain the comparison foundation.
