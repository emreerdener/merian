# AI provider flexibility — Slice 1 baseline

Date: 21 September 2026\
Source baseline: `bb3d4ce1484b159312276fb60d95d3acd0a53f49`\
Status: Slice 1 complete locally; runtime migration and release remain pending\
Implementation tracker:
[Provider Flexibility SRD](./identification-foundation-srd.md#implementation-slices)

This is a dated source/test baseline for the Gemini-preserving refactor. Current
behavior remains owned by the
[AI engineering contract](../system-architecture/04-ai-engineering.md),
[API contract](../backend-and-data/05-api-contracts.md#ai-authorization-and-idempotency),
and executable code. Later slices should record differences from this baseline
without rewriting it as evidence that their new boundary already existed.

## 1. Implemented boundaries and scope

The installed dependency is `@google/genai` 2.23.0, pinned by
[`deno.json`](../../services/supabase/functions/deno.json) and the shared frozen
lockfile. [`gemini.ts`](../../services/supabase/functions/_shared/gemini.ts)
constructs the lazy paid-service client, applies the 90-second HTTP timeout,
exposes native `models.generateContent`, and supplies `createFlashModel` and
`extractJson`. The proposed `_shared/ai/` registry, adapter, normalized outcome,
and `gemini_baseline_v1` configuration do not yet exist.

The scoped dispatch owners are four identification handlers and three biological
content helpers. Reuse their current contracts, not their Google SDK types, at
the future provider-neutral boundary.

| Caller/task            | Current owner and input                                                                                                                                                                                           | Admission/model authority                                                                                                                                                                                                        | Result, cache, and usage owner                                                                                                                                                 |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Primary identification | [`identify-multimodal`](../../services/supabase/functions/identify-multimodal/index.ts), `handleIdentifyMultimodalRequest`: prepared images, WAV audio, observation/context text, or their accepted combinations. | `scan_identification`; exact model and effective tier from the quota reservation, including existing fallback/replay rules.                                                                                                      | Handler plus `_shared/identify` validation, moderation, canonical species resolution, media promotion, owner scan persistence, completion replay, and Gemini usage extraction. |
| Visual compatibility   | [`identify`](../../services/supabase/functions/identify/index.ts): prepared visual evidence and context.                                                                                                          | `scan_identification`; reservation-selected model.                                                                                                                                                                               | Existing shared contract, legacy configuration, compatibility ledger, owner persistence, and usage attribution.                                                                |
| Text compatibility     | [`identify-describe`](../../services/supabase/functions/identify-describe/index.ts): one description and bounded context via `buildObservationPrompt`.                                                            | `scan_identification`; reservation-selected model.                                                                                                                                                                               | `getDescribeResponseSchema`, describe parsing, compatibility ledger, durable owner result, and native usage. Its replay intent is consumed by the primary multimodal endpoint. |
| Audio compatibility    | [`audio-spec`](../../services/supabase/functions/audio-spec/index.ts): bounded WAV audio and context.                                                                                                             | `scan_audio_identification`; reservation-selected model, with current policy selecting Flash.                                                                                                                                    | Shared audio subject policy, compatibility ledger, promoted audio/owner result, and usage.                                                                                     |
| Species overview       | [`biology.ts`](../../services/supabase/functions/_shared/biology.ts), `fetchStaticEncyclopedicData`: scientific name and locale.                                                                                  | The caller supplies its admitted model. User calls use `scan_overview_enrichment`; the maintenance worker supplies its approved Flash model.                                                                                     | Returns parsed taxonomy/habitat/hazard/color fields and optional usage; the caller owns cache writes and ledger attribution.                                                   |
| Lookalikes             | `biology.ts`, `fetchSimilarSpecies`: scientific name plus normalized taxonomy.                                                                                                                                    | User calls use `scan_lookalike_enrichment`; service jobs supply their approved Flash model.                                                                                                                                      | Helper normalizes reason/traits/confidence and returns usage. Foreground/worker owners verify taxonomy, persist relations, and classify retryable failures.                    |
| Group tags             | `biology.ts`, `fetchGroupTags`: scientific name.                                                                                                                                                                  | [`groupTagQuota.ts`](../../services/supabase/functions/_shared/groupTagQuota.ts), `fetchQuotaGuardedGroupTags`, uses an independently derived `scan_group_tag_enrichment` reservation; service jobs supply their approved model. | Optional primary-scan enrichment must not discard the primary result. When given a database client, the helper records usage; service labels produce null user attribution.    |

### Dependent content paths

[`enrich-scan`](../../services/supabase/functions/enrich-scan/index.ts) runs
overview and lookalike tasks separately. Each scope checks its cache, coalesces
same-species work on the warm isolate, and reserves/commits its own operation on
a miss. It awaits the relevant cache write before releasing waiting callers.
Keep these cache and quota lifecycles separate during migration.

[`refresh-species-model-content`](../../services/supabase/functions/refresh-species-model-content/db.ts)
uses the same helpers for `habitat`, `lookalikes`, and `group_tags`. The
[HTTP handler](../../services/supabase/functions/refresh-species-model-content/index.ts)
authenticates a service caller. The worker claims durable jobs through
`claim_species_model_enrichment_jobs`, uses explicit `gemini-2.5-flash`, and
completes/fails jobs through the existing job RPC. Current controls include
default batch 12, maximum 50, concurrency 2, and stored attempt limits. Preview
does not invoke a provider. Public content usage is recorded under existing
operation names without reserving user scan quota.

The similarly named
[`refresh-species-content`](../../services/supabase/functions/refresh-species-content/index.ts)
is an external-reference refresh path, not an additional Gemini content adapter.
Likewise, the dictionary's local `fetchSimilarSpecies` reads persisted
relations; its name does not make it a provider dispatch site.

## 2. Request/configuration baseline

All scoped calls use JSON response mode. These profiles differ today; extraction
must preserve the actual caller's settings rather than apply one shared default.
The numbers below are source settings, not measured latency, cost, or quality.

| Dispatch profile                   | Output token limit | Thinking configuration    | Other settings and schema                                                                                                                                                             |
| ---------------------------------- | ------------------ | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `identify-multimodal`              | 8192               | Pro: 5000; Flash: omitted | Temperature 0.1, seed 42; no explicit `topK` or compatibility-route safety array. Instruction depends on evidence; audio-only uses the audio schema, other modes use the main schema. |
| `identify` Flash / Pro             | 4096 / 8192        | 2048 / 5000               | Temperature 0.1, seed 42, `topK` 40, biological safety settings, visual instruction and schema.                                                                                       |
| `identify-describe` Flash / Pro    | 2048 / 4096        | 1024 / 3000               | Temperature 0.15, seed 42, `topK` 40; dedicated text-only instruction and schema.                                                                                                     |
| `audio-spec`                       | 2048               | 2048                      | Temperature 0.1, seed 42; shared bioacoustic instruction and audio schema.                                                                                                            |
| Overview / lookalikes / group tags | 1500 / 300 / 100   | 0                         | `createFlashModel` applies temperature 0.1 and the caller-supplied model; each helper supplies its own schema and input text.                                                         |

The primary source anchors are the handlers above,
[`identify/schema.ts`](../../services/supabase/functions/_shared/identify/schema.ts),
[`identify-describe/schema.ts`](../../services/supabase/functions/identify-describe/schema.ts),
and
[`audioSubjectPolicy.ts`](../../services/supabase/functions/_shared/identify/audioSubjectPolicy.ts).
The existing executable
[`contract.ts`](../../services/supabase/functions/_shared/identify/contract.ts)
and
[`googleSchema.ts`](../../services/supabase/functions/_shared/identify/googleSchema.ts)
already provide the schema separation to reuse.

### Evidence and recovery invariants

- Video capture supplies normally five ordered images from a five-second clip,
  with accepted partial sampling and optional companion audio. Playback video
  keys are retained for storage/finalization, not sent as native video input.
  Preserve all included evidence and current prepared bytes.
- Active-app description requests use `identify-multimodal`; the legacy
  `identify-describe` schema has different text-only constraints. Its first
  extraction must preserve that distinction and its replay through the primary
  route.
- [`aiQuota.ts`](../../services/supabase/functions/_shared/aiQuota.ts) keeps
  database consent, exact model, entitlement, idempotency, and fencing
  authoritative. Commit precedes provider invocation. Pre-provider no-ops may
  refund; failed provider attempts remain charged and use the existing failed
  attempt path. A permitted new attempt may receive the current model/policy.
- Model parsing, audio/processed-material normalization, confidence thresholds,
  moderation, canonical species identities, and complete owner persistence
  remain with their current owners. A returned model draft is not a completed
  scan.
- [`completedResponse.ts`](../../services/supabase/functions/_shared/identify/completedResponse.ts)
  handles stored/reconstructed completion and duplicate polling without another
  inference. Preserve account/deletion fences and recovery of uncertain results.
- Timing boundaries remain independent: queue-backed foreground 15 seconds,
  queue-less client request 90 seconds, Gemini HTTP call 90 seconds from
  invocation, and duplicate-result polling window 70 seconds. Preparation,
  finalization, quota RPCs, and database reads retain their own existing bounds;
  there is no shared 90-second server deadline.
- [`aiUsage.ts`](../../services/supabase/functions/_shared/aiUsage.ts) retains
  Gemini units and nullable usage facts. Service content does not gain a user
  allowance. Missing provider usage and historical ledger gaps are not zero cost
  or complete accounting.

## 3. Deferred provider dispatches to preserve

These callers remain outside S2–S5. Shared-client changes must keep them
working; the final direct-dispatch check must distinguish this list from missed
scoped migrations.

| Deferred owner                                                                                                   | Boundary to preserve                                                                                                                   |
| ---------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- |
| [`insight-chat/index.ts`](../../services/supabase/functions/insight-chat/index.ts)                               | Existing Field/Insight Chat generation, including its separate dispatch stages and contracts.                                          |
| [`explore-post-chat/index.ts`](../../services/supabase/functions/explore-post-chat/index.ts)                     | Existing Explore-post Chat provider call.                                                                                              |
| [`species-dictionary-chat/index.ts`](../../services/supabase/functions/species-dictionary-chat/index.ts)         | Existing Dictionary Chat provider call.                                                                                                |
| [`audioModeration.ts`](../../services/supabase/functions/_shared/audioModeration.ts)                             | Independent public-audio moderation, including its fail-closed outcome and operation.                                                  |
| [`species-discovery-search/provider.ts`](../../services/supabase/functions/species-discovery-search/provider.ts) | Search interpretation, its 20-second call-specific timeout, cancellation, schema, and usage. This newer caller is explicitly deferred. |

## 4. Test coverage and extraction gaps

| Boundary                   | Existing evidence                                                                                                                                                                                                                                                                                                                                                                                                                                                                       | What it does not yet prove                                                                                       |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Installed Gemini SDK       | [`gemini_test.ts`](../../services/supabase/functions/_shared/gemini_test.ts): intercepted HTTP executes the installed SDK; covers serialization, usage/safety decoding, timeout, and no hidden retries.                                                                                                                                                                                                                                                                                 | Actual request construction and complete lifecycle of every scoped handler.                                      |
| Biological content helpers | New [`biology_test.ts`](../../services/supabase/functions/_shared/biology_test.ts): calls all three real helpers through intercepted HTTP; covers selected model, task schema/options/input, overview locale, lookalike normalization, usage, null user service attribution, missing usage, and failed/unusable responses without retry.                                                                                                                                                | Service authentication/claim fencing, cache persistence, or live model quality.                                  |
| Quota and usage            | [`aiQuota_test.ts`](../../services/supabase/functions/_shared/aiQuota_test.ts) executes request-key, consent-error, fencing, and commit/fail behavior with RPC doubles. [`aiUsage_test.ts`](../../services/supabase/functions/_shared/aiUsage_test.ts) exercises modality normalization.                                                                                                                                                                                                | Live database concurrency or full ledger coverage for every failed/uncertain call.                               |
| Identification routes      | [`identify-describe/index.test.ts`](../../services/supabase/functions/identify-describe/index.test.ts), [`identify/index.test.ts`](../../services/supabase/functions/identify/index.test.ts), [`audio-spec/index.test.ts`](../../services/supabase/functions/audio-spec/index.test.ts), and [`identify-multimodal/index.test.ts`](../../services/supabase/functions/identify-multimodal/index.test.ts) cover shared helpers plus source-order assertions and some mirrored local logic. | These are not full behavioral proofs of actual handler request/options parity or post-dispatch settlement order. |
| Common result/recovery     | [`contract_test.ts`](../../services/supabase/functions/_shared/identify/contract_test.ts), [`audioSubjectPolicy_test.ts`](../../services/supabase/functions/_shared/identify/audioSubjectPolicy_test.ts), and [`completedResponse_test.ts`](../../services/supabase/functions/_shared/identify/completedResponse_test.ts) execute real schema, subject-policy, and reconstruction/recovery logic with bounded doubles.                                                                  | Complete client-to-provider-to-persistence execution and physical-device handoff.                                |
| Content workers            | [`db.test.ts`](../../services/supabase/functions/refresh-species-model-content/db.test.ts) and [`lookalikeCandidates.test.ts`](../../services/supabase/functions/refresh-species-model-content/lookalikeCandidates.test.ts) execute injected generation, candidate verification, retries, persistence, and preview.                                                                                                                                                                     | Live job-claim concurrency and the actual Gemini generation path, now characterized separately above.            |
| Consent/database contracts | [`legalConsentConcurrencyDb.test.ts`](../../services/supabase/functions/_tests/legalConsentConcurrencyDb.test.ts) and the candidate database suite.                                                                                                                                                                                                                                                                                                                                     | An unconfigured/self-skipped database test is not successful database evidence.                                  |

### Required coverage with the first extraction

S2 must test the actual describe request builder/executor rather than copy its
logic into a test. Assert the admitted model, full options/schema, instruction,
and sole text part. Exercise commit-before-invoke, one invocation, provider
failure/abort handling, and retained recovery ownership for uncertain outcomes.
Completed replay must perform no inference. Keep these checks with the
extraction because no provider-neutral request/executor seam exists yet.

S3–S5 add the corresponding real-caller coverage for media combinations,
compatibility routes, cache hits, and user/service admission. S6 checks the
whole scoped graph and the deferred-call list; it does not postpone these
per-slice tests until the end.

### Measurement boundary

The source exposes client benchmark markers, `Server-Timing`, provider timing,
usage fields, and documented latency limits. This slice does not call a live
provider or claim a measured quality, cost, or latency baseline. S2/S3 must
compare introduced adapter overhead using equivalent fixtures; representative
runtime measurements remain required before rollout under the existing
[timing contract](../system-architecture/04-ai-engineering.md#benchmark-timing).

## 5. Local verification record

Run on 21 September 2026 with repository-pinned Deno 2.9.4:

| Check                                                                    | Result                                                                                                                                                            |
| ------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Focused baseline suite, with runtime network permission omitted          | 279 tests and 17 steps passed; no failures or database skips. Covers the 14 files listed in the command below.                                                    |
| New biological helper suite                                              | 10 behavioral steps passed, alongside the existing SDK's 7 steps. No live provider or user data.                                                                  |
| `deno fmt --check services/supabase/functions services/supabase/scripts` | Passed, 915 files.                                                                                                                                                |
| Complete Edge/script lint                                                | Passed, 727 files.                                                                                                                                                |
| `make test-supabase-tooling`                                             | Passed: 312 tooling tests plus 19 Identify DTO and 20 Captured Media DTO tests; shell fixtures passed.                                                            |
| Function config and dependency validators                                | Passed: 101 function configs and 101 isolated graphs across 352 runtime files.                                                                                    |
| Broad Edge task with local database access denied                        | Exited successfully: 2035 reported passes, 17 steps, 6 ignored. Also emitted 114 database-fixture skip messages; those early returns are not database validation. |
| Planning-document links and requirement coverage                         | Passed: 71 local links/anchors; all 10 PRD and 13 SRD requirements represented in the acceptance matrix.                                                          |
| Independent read-only review                                             | No material findings in the test isolation, coverage claims, or slice sequencing.                                                                                 |

The focused suite is reproducible from the repository root without runtime
network access:

```bash
deno test --frozen --config services/supabase/functions/deno.json \
  --allow-env --allow-read=. \
  services/supabase/functions/_shared/biology_test.ts \
  services/supabase/functions/_shared/gemini_test.ts \
  services/supabase/functions/_shared/aiQuota_test.ts \
  services/supabase/functions/_shared/aiUsage_test.ts \
  services/supabase/functions/_shared/identify/contract_test.ts \
  services/supabase/functions/_shared/identify/audioSubjectPolicy_test.ts \
  services/supabase/functions/_shared/identify/completedResponse_test.ts \
  services/supabase/functions/identify-describe/index.test.ts \
  services/supabase/functions/identify/index.test.ts \
  services/supabase/functions/identify-multimodal/index.test.ts \
  services/supabase/functions/audio-spec/index.test.ts \
  services/supabase/functions/enrich-scan/index.test.ts \
  services/supabase/functions/refresh-species-model-content/db.test.ts \
  services/supabase/functions/refresh-species-model-content/lookalikeCandidates.test.ts
```

For the broader task, run from `services/supabase/functions`:

```bash
deno task test --deny-net=127.0.0.1:54322,localhost:54322
```

No disposable database was configured for this slice. The deny rule prevents the
legacy tests from falling back to an unverified local database. The complete
fresh-catalog/concurrency candidate gate remains unrun; a successful local task
exit does not replace it. No iOS build, physical-device check, hosted candidate,
or runtime benchmark was performed. These remain implementation/release gates
where applicable.

Production code, prompts, models, routing, public payloads, and database schema
are unchanged by this slice. No live provider request, deployment, or hosted
mutation was performed. S2 is the next implementation slice.
