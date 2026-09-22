# AI provider flexibility — local verification and release preparation

Date: 21 September 2026\
Status: Slice 6 local record; no deployment or alternate provider enabled\
Baseline commit: `bb3d4ce1484b159312276fb60d95d3acd0a53f49`\
Source state: uncommitted working tree; not immutable candidate-CI evidence

**Later status — 21 September 2026:** The
[deployment and verification record](../release-evidence/provider-flexibility-deployment-2026-09-21.md)
adds the merged candidate, successful production deployment, and owner-reported
manual verification. The local evidence and remaining boundaries below describe
the earlier Slice 6 checkpoint and are preserved as historical facts.

The [SRD tracker](./identification-foundation-srd.md#implementation-slices) owns
implementation status. Current behavior is described by the
[provider guide](../../services/supabase/functions/_shared/ai/README.md),
[AI architecture](../system-architecture/04-ai-engineering.md), and
[API contracts](../backend-and-data/05-api-contracts.md). This record
distinguishes local evidence from remaining candidate, hosted, and device
acceptance.

## Final dispatch and SDK boundary

The four identification routes and the three biological content tasks now
dispatch through `_shared/ai/gemini.ts`. User enrichment and claimed public jobs
retain their admission, quota, cache, validation, and persistence owners. The
unused `createFlashModel` wrapper was removed; `_shared/gemini.ts` still owns
the lazy paid client, 90-second native timeout, and JSON extraction. The
checked-in Field Chat bundle identities were regenerated because their source
graphs include that shared helper; the deterministic identity gate passes.

The executable allowlist in
[`aiQuotaCoverage.test.ts`](../../services/supabase/functions/_tests/aiQuotaCoverage.test.ts)
checks both `generateContent(request)` and object-literal dispatches across
Functions and scripts, plus exact SDK import owners. Deferred live dispatches
are:

| Owner                                    | Preserved purpose                                                                 |
| ---------------------------------------- | --------------------------------------------------------------------------------- |
| `_shared/audioModeration.ts`             | Public-audio moderation, independent and fail-closed                              |
| `insight-chat/index.ts`                  | Insight replies, prompt suggestions, summaries                                    |
| `explore-post-chat/index.ts`             | Explore Field Chat                                                                |
| `species-dictionary-chat/index.ts`       | Dictionary Field Chat                                                             |
| `species-discovery-search/provider.ts`   | Species discovery suggestions                                                     |
| `scripts/evaluate_field_chat_answers.ts` | Synthetic Field Chat evaluation, explicitly gated by `--live` and a paid test key |

The local benchmark is a separate tooling-only dispatch owner. It requires
denied runtime networking and intercepts every SDK request. The inventory also
locks the two tooling guards; listing a file alone does not authorize live
execution. The SDK import owners are the native adapter/content projection,
shared Gemini client, existing Identify/Describe Google schema projections,
Field Chat request projection, and Insight Chat. Common contracts, registry,
executor, and migrated HTTP callers contain no Google SDK imports.

## Acceptance evidence and remaining boundaries

| Group        | Executed local evidence                                                                                                                                                                                                                                                                 | Remaining acceptance boundary                                                                                                        |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| T-ADAPTER    | `ai/ai_test.ts`, `biology_test.ts`, and actual handler suites preserve Gemini requests, settings, decoding, content normalization, and side effects. S5 also compared ten old/new serialized content requests.                                                                          | Hosted smoke and real model behavior; deterministic fixtures do not measure identification quality.                                  |
| T-ROUTING    | Registry tests reject unknown models, wrong task/operation/permission, service identification, and exhausted public claims. Snapshots remain fixed; separately admitted retries can select new approved policy/model versions. Production composition is fixed to Gemini.               | Exact deployed configuration and approved candidate SHA.                                                                             |
| T-MEDIA      | Primary and compatibility SDK/handler cases cover stills, text, WAV, ordered five-frame and partial sets, companion audio, and lineage; playback video stays out of inference.                                                                                                          | Device capture/upload and full client-to-hosted recovery.                                                                            |
| T-CONSENT    | Actual handlers reject admission before preparation; public jobs retain service claims. Full disposable catalog and `legalConsentConcurrencyDb.test.ts` execute consent allow/deny/race rules.                                                                                          | Device account-switch, queued delivery, and revocation across a real authenticated session.                                          |
| T-CONFIDENCE | Existing Identify contract, threshold, subject-policy, and final-wire suites run unchanged. Generated DTOs remain unchanged.                                                                                                                                                            | Hosted parity; no new calibration or quality improvement is claimed.                                                                 |
| T-RECOVERY   | Actual handlers cover saved replay, uncertain writes, charged failures, cancellation followed by backend completion, and post-commit identity retirement before saving. Disposable account-deletion and quota concurrency suites execute existing database fences.                      | Hosted lost-response/replay, account transitions, and physical-device timing; local tests do not prove all production interleavings. |
| T-USAGE      | User/public-job attribution, one group-tag write, nullable usage, cached/tool/modality counts, native duration, and public-response exclusion are covered.                                                                                                                              | Existing best-effort/failed-attempt accounting gaps and operational cost comparison remain.                                          |
| T-EXTENSION  | Deterministic adapters exercise actual callers without a production selector. The [provider onboarding procedure](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md) names the required code, admission, permission, confidence, cache, evaluation, and activation work. | A real second provider is neither integrated nor qualified.                                                                          |

The new retirement test holds an already committed provider call, retires the
identity in the DB double, then releases its result. The existing profile
recheck returns `503 scan_persistence_failed` with no inserted scan or
completion. The single call stays charged; the existing retry/dead-letter
behavior is preserved. This is not retroactive cancellation of disclosed
evidence.

## Local overhead methodology

[`benchmark_ai_boundary.ts`](../../services/supabase/scripts/benchmark_ai_boundary.ts)
uses the installed SDK with synthetic request/response data and runtime network
permission denied. Ten profiles on both admitted models cover legacy
description, primary text/still/audio/five-frames-plus-audio, legacy
image/audio, and the three content tasks. Inputs are byte-shaped transport
fixtures, not biological examples or a media-decoding benchmark. Largest
serialized requests are about 1.41 MB.

Each case asserts identical serialized native request bodies and parsed drafts,
exactly one intercepted request per invocation, and zero dispatch during
preparation. After 25 warm-up pairs, 250 measured pairs alternate execution
order. Nearest-rank p50/p95 values use milliseconds; signed paired differences
retain noise rather than clamping negative values.

The control uses a cached native request, the real SDK, and JSON extraction. The
shared path adds request preparation, registry, executor, and normalized
outcomes. Consequently the comparison includes some request construction that
existed before extraction. It is a conservative local comparison, not a
reconstructed before/after production baseline. Preparation is measured
separately.

```sh
deno run --frozen --config services/supabase/functions/deno.json \
  --allow-env --deny-net services/supabase/scripts/benchmark_ai_boundary.ts 250
```

Two independent runs used Deno 2.9.4 on macOS ARM64. The table reports the
largest per-case p95 in each run, not a pooled percentile; the maxima can come
from different cases. The largest serialized request was 1,409,744 bytes.

| Retained run                                                                        | Cases / measured pairs per case | Maximum preparation p95 | Maximum paired difference p95 |
| ----------------------------------------------------------------------------------- | ------------------------------- | ----------------------- | ----------------------------- |
| [Run 1](../release-evidence/provider-flexibility-local-2026-09-21/benchmark-1.json) | 20 / 250                        | 0.1057 ms               | 0.2330 ms                     |
| [Run 2](../release-evidence/provider-flexibility-local-2026-09-21/benchmark-2.json) | 20 / 250                        | 0.0798 ms               | 0.2212 ms                     |

The retained
[source fingerprints](../release-evidence/provider-flexibility-local-2026-09-21/source-fingerprints.json)
bind these local results to the benchmark's source graph, common contract,
dependency configuration, and lockfile. They are not immutable candidate-CI
evidence. These measurements exclude cold start, caller/media preparation, HTTP
admission, database, network/provider duration, and client rendering. They do
not establish the production non-provider p50 ≤300 ms / p95 ≤1 second or
response-to-first-render p95 ≤300 ms gates in the canonical
[timing contract](../system-architecture/04-ai-engineering.md#benchmark-timing).

## Disposable database evidence

The normal `merian` local stack already existed and was preserved. A temporary
copy of the checked-in/current Supabase source used a unique project ID and
ports 56122/56120, with no copied local environment files or linked-project
state. Those three local configuration values were the only configuration
differences. The pinned CLI's database-only start replayed the full migration
history into new volumes. The existing catalog script then ran against that
copy. The complete Edge task used an explicit loopback `SUPABASE_DB_TEST_URL`
for the temporary DB and denied both default localhost database destinations on
port 54322.

Results: **52 catalog files / 388 assertions passed**; the complete Edge suite
reported **2,048 tests / 190 steps, zero failures, zero ignored tests, and zero
database skip messages**. Database lint reported no schema errors. The existing
advisor `--fail-on error` gates passed with **105 security warnings** (103
mutable function search paths, two public-schema extensions) and **80
performance warnings** (59 auth RLS initialization plans, 20 multiple permissive
policies, one duplicate index). No SQL was changed; this record does not treat
those warnings as fixed. The temporary project's containers and volumes were
removed and their absence verified.

This is local disposable-database evidence for the working tree. It does not
replace the exact clean-checkout Candidate Validation workflow, which also
checks source identity, deployment controls, and the complete candidate's
inputs.

## Other local gates

The following additional local gates passed:

- `deno fmt --check services/supabase/functions services/supabase/scripts`: 936
  files. Recursive Deno lint: 746 files.
- Recursive Deno type checking of all 101 Edge entrypoints, plus the tooling
  gate's discovery-based script checks, including the new benchmark.
- `make test-supabase-tooling`: 312 tooling tests and its 19-test isolated
  Identify contract suite; shell/source-detection checks also passed. Field Chat
  bundle identities were generated and verified against the current graph.
- `make validate-edge-dto-contract`: 19 Identify and 20 captured-media tests,
  with generated Swift contracts unchanged.
- `make validate-supabase-migrations`: 346 tests across 59 discovered contract
  files. No migration or SQL fixture changed.
- Function configuration and dependency checks: 101 configurations and 101
  isolated graphs covering 364 runtime files.
- The final dispatch/authority and Field Chat header guard suites: 18 tests,
  including both tooling execution guards and the refreshed bundle identity. The
  SDK/primary-handler focused pass included 14 tests and 28 steps, including the
  new identity-retirement case.
- `make validate-markdown-format`: all 36 changed Markdown files, plus a clean
  `git diff --check`. All 29 benchmark source fingerprints, both artifact
  digests, and 16 local links in the new guides were verified.

The database/full Edge run preceded the final source-inventory guard assertions
and generated bundle-identity refresh; those changes passed their focused and
tooling gates afterward. This record does not imply a clean committed candidate
was tested.

## Release and return preparation

Public Identify/enrichment payloads, generated DTOs, SQL migrations, quota
operation names, consent receipts, and durable replay records are unchanged by
this refactor. Added content execution facts use the existing metadata object;
old callers ignore those optional keys. There is no database migration or cache
rewrite to undo for this change. Completed results remain readable/replayable
without another model call.

Before production:

1. Commit only reviewed changes into an immutable candidate and run the existing
   **Supabase Candidate Validation / Candidate readiness** workflow on that
   exact clean SHA. Current local evidence cannot claim that gate. Preserve
   unrelated work in this checkout and review the complete eventual candidate
   scope.
2. Collect hosted/device acceptance from the matrix above, including one primary
   call, refusal/invalid output, permission denial, sampled frames with included
   audio, replay after a lost response, public job usage, and account/deletion
   fences. Record segmented latency, failure/quality/recovery deltas, and usage
   against the existing baseline. Local microbenchmarks cannot clear this step.
3. Use the canonical
   [deployment runbook](../backend-and-data/06-supabase-deployment-runbook.md),
   protected-main, release-hold, exact-SHA, and Production controls. Explicit
   authorization must name the operation and target. Use dependency-graph
   selection for the complete change, including content callers; never publish
   only an edited handler when shared helpers changed. This refactor adds no
   percentage-routing control or alternate-provider switch.
4. Prepare a reviewed revert or forward fix limited to the provider-boundary
   change, preserving current security, owner-persistence, quota, deletion,
   replay, and unrelated fixes. Revalidate the complete selected bundles before
   an authorized return to the prior Gemini-backed path. Do not roll back data,
   remove media, reset allowances, or repeat an uncertain provider call. Verify
   saved-result reads and new Gemini attempts independently after any authorized
   return. That deployed return remains unperformed.

The
[future-provider procedure](../../services/supabase/functions/_shared/ai/ADDING_PROVIDERS.md)
is separate from releasing this Gemini-only infrastructure. BioCLIP, training,
family plans, routing cascades, and automatic provider failover remain deferred.
