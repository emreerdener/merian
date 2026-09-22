# Supabase Functions organization

Date: 21 September 2026\
Status: O1–O3 complete locally; O3 exact-commit candidate validation remains
pending\
Audited source: `7cb12cce16bd736ea1dc725663cacd10471cac46`

## Purpose and boundaries

Make endpoint discovery and shared ownership easier to understand, then move one
cohesive group at a time with behavioral parity. The current
[directory guide](../../services/supabase/functions/README.md) is the navigation
index. The [Edge architecture](../system-architecture/06-edge-modularization.md)
and
[refactoring policy](../development-guides/19-code-ownership-and-refactoring.md)
remain the normative owners of module boundaries and extraction rules.

O1 adds documentation and records dependencies. It changes no runtime source,
endpoint name, generated artifact, dependency pin, database object, or API
payload. Later slices preserve the top-level `functions/<endpoint>/index.ts`
layout. The navigation groups are not deployment directories, authorization
classes, or a commitment to create a folder for every category.

## Preserve the AI work

This worktree starts at the source commit above. At audit time, its
`services/supabase/functions` and `services/supabase/scripts` contents match the
cached AI branch tip `ed5c36485` even though the commit histories differ. That
comparison is local source evidence, not a fresh GitHub workflow/status check.
Before a later code-moving slice, refresh the intended integration base and
repeat the dependency inventory if source changed.

The [provider-flexibility PRD](../product/03-identification-foundation-prd.md),
[SRD](./identification-foundation-srd.md), and
[AI verification record](./identification-foundation-verification.md) retain the
Gemini-only scope, completed local slices, and outstanding candidate, hosted,
and device acceptance. In particular, video identification still uses sampled
images and any included audio; file organization does not change that contract
or add a provider.

All 29 source hashes and both result-artifact hashes in the original
[benchmark manifest](../release-evidence/provider-flexibility-local-2026-09-21/source-fingerprints.json)
match this checkout. Preserve that record as evidence for its original bytes. A
later move of a fingerprinted input needs a separately identified record if
claiming equivalent measurements for the new layout. Passing organization tests
does not clear pending AI acceptance or authorize deployment.

## O1 measured inventory

| Measurement                                       | O1 baseline                                                    |
| ------------------------------------------------- | -------------------------------------------------------------- |
| Discoverable endpoint entrypoints                 | 101                                                            |
| Endpoint directories with a local README          | 78; the directory guide links the other 23 to their entrypoint |
| Shared root runtime TypeScript modules            | 60                                                             |
| Existing shared subdirectories                    | `ai/`, `identify/`                                             |
| Distinct files in the union of deployment graphs  | 364, including the generated JSON asset                        |
| Non-test TypeScript files under Functions         | 368 / 71,556 lines, including type-only source files           |
| Direct shared-to-endpoint import edges            | 5                                                              |
| Direct imports between different endpoint folders | 33                                                             |

The directory guide maps all 101 endpoints once across 13 navigation groups and
all 60 root shared TypeScript modules once across 13 purpose groups. Those group
counts are documentation organization, not additional runtime owners.

Runtime reachability uses the repository's
[`buildAllFunctionGraphs`](../../services/supabase/scripts/function_dependency_tools.ts)
and `importedSpecifiers` rules: follow static relative imports and literal-path
dynamic imports; omit explicit `import type`/`export type` edges. It is the
deployment planner's syntactic graph, not a runtime trace or an exhaustive
type-consumer inventory. Tests, generators, scripts, assets, and path assertions
need separate searches before any move. Source-line counts exclude `_tests/`,
`*_test.ts`, and `*.test.ts`; they are review aids, not size limits or a reason
by themselves to split a module.

Largest current owners include `identify-multimodal/index.ts` (2,264 lines),
`species-dictionary/db.ts` (1,631), `_shared/identify/contract.ts` (1,417),
`identify/index.ts` (1,371), and `field-trips/db.ts` (1,325). The executable
Identify descriptor is a cohesive schema owner; do not split it merely to reduce
its line count. Handler extraction requires a separate lifecycle and
success-boundary audit.

## O1 dependency findings

Every root shared runtime TypeScript module is reached by at least one
deployment graph. This audit found no basis for deleting one as unused. Selected
transitive consumer counts explain where to start:

| Current owner                                                                                                            | Endpoint graphs containing it | Consequence                                                                      |
| ------------------------------------------------------------------------------------------------------------------------ | ----------------------------- | -------------------------------------------------------------------------------- |
| Each `fieldChat*` root module                                                                                            | 3                             | Clear product boundary; generated bundle identities still apply                  |
| `exploreFeedFilters.ts`                                                                                                  | 2                             | Bounded feed/map policy, separate from publication and media                     |
| `exploreComposerMedia.ts`                                                                                                | 4                             | Includes both Explore and Community publishing                                   |
| `scanMediaAssets.ts`                                                                                                     | 8                             | Crosses ingestion, recovery, and publication                                     |
| `aiQuota.ts`                                                                                                             | 12                            | Shared authority across identification, content, chat, discovery, and moderation |
| `gemini.ts`                                                                                                              | 14                            | Broader than the newly extracted identification boundary                         |
| `explore.ts`                                                                                                             | 54                            | Name alone understates its shared privacy/read dependencies                      |
| `auth.ts`, `edgeHandler.ts`, `http.ts`, `outbound.ts`, `publishableKey.ts`, `serviceRoleAuth.ts`, `serviceRoleClient.ts` | 101 each                      | Fleet-wide infrastructure; defer broad moves                                     |

The five shared-to-endpoint edges are explicit ownership review candidates:

| Importing shared file          | Current endpoint-owned dependency     |
| ------------------------------ | ------------------------------------- |
| `_shared/ai/gemini.ts`         | `identify-describe/schema.ts`         |
| `_shared/ai/gemini.ts`         | `identify-multimodal/instructions.ts` |
| `_shared/ai/gemini.ts`         | `audio-spec/instructions.ts`          |
| `_shared/audioProcessing.ts`   | `audio-spec/wav.ts`                   |
| `_shared/fieldChatResponse.ts` | `insight-chat/types.ts`               |

These are working dependencies, not findings of incorrect behavior. Keep the AI
prompt/schema/WAV owners stable during AI acceptance. Any later ownership change
must preserve their distinct compatibility profiles and account for all
importing graphs.

The 33 endpoint-to-endpoint edges include shared username validation; DwC-A
grant/storage helpers; Field Chat guards/types and public-post reads; report and
mention helpers; Field trip profile reads; Identify sanitization; purchase
subscriber and reconciliation helpers; account/scan deletion workers; content
enrichment persistence; Community/Explore restored-media publication; and
notification-count reads. Some intentionally reuse one durable owner. Do not
turn every cross-folder import into a new abstraction without checking that
owner's semantics.

## Tooling constraints on later moves

1. `discoverFunctionEntrypoints` scans one directory level and ignores
   underscore-prefixed directories. `sync_function_deno_configs.ts` generates
   endpoint-local configs with a relative shared lockfile. Keep endpoint paths
   and identifiers stable; nested shared subdirectories already work.
2. `planAffectedFunctions` uses each current graph, but a deleted shared runtime
   path absent from that graph conservatively selects the entire fleet. A
   mechanical rename may therefore plan all 101 Functions. Three actual
   consumers does not mean a three-Function rollout. Preserve this safety rule
   and inspect the planner output before any authorized deployment.
3. `generate_field_chat_deployment_identity.ts` hashes both repository-relative
   paths and file bytes. Relocating either prompt/request helper changes all
   three Field Chat bundle hashes. Regenerate
   `_shared/fieldChatDeploymentIdentity.ts` using the checked-in generator; keep
   that generated file at its current path.
4. DTO generators, workflow path filters, static source tests, and documentation
   tests name exact paths. Examples include `_shared/identify/contract.ts`,
   `_shared/capturedMediaContract.ts`, `_shared/biology.ts`, and
   `_shared/fieldChatReservation.ts`. Search the whole repository, including
   scripts and workflows, before updating any path. Preserve the checks'
   semantics rather than weakening them to make a move pass.
5. Historical RFC, incident, and release-evidence references remain historical.
   Update current ownership guides with a move; add a dated pointer where needed
   instead of rewriting old test or benchmark evidence.

## Organization slices

These O-prefixed slices are separate from the completed AI S1–S6 slices.

| Slice                                  | Scope                                                                                                                                    | Completion boundary                                              |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| O1 — Inventory and navigation          | Current endpoint/shared-owner index, dependency audit, AI handoff, and bounded next-slice proposal                                       | Complete locally; documentation-only                             |
| O2 — Field Chat prompt/request helpers | Move the two helpers and their colocated unit test as listed below; update consumers, source guards, docs, and generated identities      | Complete locally, 21 September 2026; no behavioral change        |
| O3 — Remaining Field Chat helpers      | Move daily usage, reservation/recovery, response/replay helpers and colocated tests into `fieldChat/`; preserve all lifecycle boundaries | Complete locally; 21 September 2026                              |
| O4 — Large handler responsibilities    | Extract independently testable stages only after admission, timeout, quota, persistence, and replay ordering are mapped                  | Deferred until the AI validation work has a stable accepted base |

Stop a slice when the remaining owner is cohesive or the move would require
unplanned behavior changes. Directory uniformity alone is insufficient reason to
widen the scope. Domain-neutral infrastructure and generated wire contracts are
not early candidates.

### O2 implementation scope

`_shared/fieldChat/` now owns this shared domain. Exported names and
implementations are preserved; the shorter basenames rely on their directory
owner. The move map retains the original locations for audit purposes.

| Original path under `_shared/` | Implemented path                |
| ------------------------------ | ------------------------------- |
| `fieldChatSpeciesKnowledge.ts` | `fieldChat/speciesKnowledge.ts` |
| `fieldChatReply.ts`            | `fieldChat/reply.ts`            |
| `fieldChatReply_test.ts`       | `fieldChat/reply_test.ts`       |

The two production files currently total 64 lines. Their declarations are
`FIELD_CHAT_SPECIES_KNOWLEDGE_RULES`,
`buildFieldChatReplyRequest(systemInstruction, userPrompt, model)`,
`extractFieldChatReplyJson<T>(text)`, and the private `ResponseSchema` type.
They have no direct I/O; the request builder has a type-only Google SDK
dependency. The move preserves that native Gemini projection and does not
migrate deferred Field Chat dispatch into `_shared/ai`.

The complete audited consumer/update set was:

- `explore-post-chat`, `insight-chat`, and `species-dictionary-chat`: each
  `prompt.ts` imports the knowledge rules and each `index.ts` imports the reply
  builder/parser. Their prompt and handler suites cover the callers.
- `_shared/fieldChat/reply_test.ts` and `_shared/gemini_test.ts`: imports
  updated while preserving helper and actual-SDK request/response assertions.
- `scripts/field_chat_answer_cases.ts` and
  `scripts/evaluate_field_chat_answers.ts`: update tooling imports. Preserve the
  evaluator's explicit `--live` and paid-key guards; do not run live calls for a
  path-only refactor.
- `_tests/aiQuotaCoverage.test.ts`: update the exact SDK-import owner path;
  retain the dispatch allowlist and tooling execution guards.
- Current docs: `_shared/README.md`, this directory index, all three Field Chat
  READMEs, the Edge architecture, and the Field Chat section of the API
  contract. Update the Insight README's focused test command as well.
- Regenerate and verify all three Field Chat bundle hashes; run the deployment
  planner on the complete rename diff. No endpoint config or dependency-pin
  change is expected.

Quota, daily usage, response/persistence helpers, generated-identity path,
`gemini.ts`, `_shared/ai/`, and `_shared/identify/` remain in place. Neither
moved helper is in the AI benchmark fingerprint set. Local test results are
recorded below; exact-commit candidate checks remain pending. Unchanged
benchmark inputs are not proof of the rest of the application.

O2 verification uses focused helper/SDK/prompt/handler and source-guard tests,
then the existing complete affected-surface gates from the
[Supabase skill](../../skills/merian-supabase/references/edge-functions-and-clients.md)
and [testing strategy](../development-guides/08-testing-strategy.md). Verify
recursive types, formatting/lint, tooling, DTOs, configs, graph discovery,
generated identities, and stale-path searches. Keep disposable-database
candidate evidence separate from local mocked tests and hosted/device proof.

## O1 verification and handoff

Production delta: **zero files and zero lines added, removed, or moved**; no
dependencies narrowed or declarations removed. O1's deliverables are the
navigation guide, this audit, and links from existing ownership documents.

Local verification passed:

- Exact catalog coverage: 101 endpoint links and 60 shared root module links,
  with no duplicates or omissions; 182 local links in the two new guides
  resolve.
- `validate_function_dependencies.ts`: 101 isolated graphs / 364 runtime files;
  `sync_function_deno_configs.ts --check`: 101 configurations.
- `function_dependency_tools_test.ts`: 11 tests, zero failures, including
  shared-consumer selection and conservative deployment fallback.
- All 29 original AI source fingerprints and both benchmark artifact digests
  match. The modified/untracked file inventory contains only Markdown.
- `make validate-markdown-format`: seven changed Markdown files;
  `deno fmt --check services/supabase/functions services/supabase/scripts`: 937
  files; `git diff --check`: clean.

Checks used Deno 2.9.4 and the Supabase CLI 2.109.1 version guard. The complete
runtime and database suites were not re-run for these documentation-only
changes; the AI verification record remains the authority for its earlier runs.
No GitHub workflow, hosted service, device flow, or production action was
executed by this audit.

The user-level skill-link check reports links to the original checkout rather
than this worktree. Both reviewed packages were compared recursively and are
byte-identical to the worktree copies. This audit used the checked-in packages
and did not redirect the user's global installation.

## O2 verification and handoff

Implemented locally on 21 September 2026, based on the same source commit as O1.
The two runtime helpers are byte-identical to their originals; their unit test
changes only its relative import. Six route import sites, the shared SDK test,
two tooling consumers, the SDK-owner source assertion, and current ownership
documentation now use the new paths. The generator refreshed all three Field
Chat bundle identities; those hashes are expected to change for file moves even
when behavior is identical.

Production delta: **two runtime files / 64 lines relocated, zero net runtime
files or lines added**, no new declarations, wrappers, dependencies, or public
contracts. Shared-root runtime modules decrease from 60 to 58; the two helpers
are now grouped under `fieldChat/`. Admission, database, response, and replay
owners are unchanged. The larger owners and broader dependencies recorded in O1
are intentionally retained for later scoped review.

Local checks passed:

- Focused helper, SDK, Field Chat route, deployment-header, and source-guard
  suites: **82 tests / 6 steps**, with networking denied.
- Complete Edge suite on a fresh disposable database: **2,048 tests / 190
  steps**, zero failures and zero database skip messages.
- Complete catalog gate: **52 files / 388 assertions**. Database lint found no
  schema errors. The advisor error-level gates passed with the same 105 security
  and 80 performance warnings recorded during AI verification; no SQL was
  changed or warning claimed fixed.
- `make test-supabase-tooling`: **312 tooling tests**, the **19 Identify / 20
  captured-media DTO tests**, and shell/secret-literal checks. Discovery covered
  69 standard TypeScript sources and 32 standard test files.
- Recursive type checks of all **101 entrypoints**, recursive lint (**746
  files**), and formatting of Functions/scripts (**938 files**).
- **101** generated endpoint configurations and isolated graphs covering **364**
  runtime files. Each relocated helper still reaches exactly the same three
  Field Chat endpoints. Generated bundle-identity verification passes.
- The planner evaluated the complete tracked/untracked change, including the
  deleted shared paths, and conservatively selected **all 101 Functions**. No
  deployment was executed or authorized by this check.
- All **29 original AI source hashes and two benchmark artifact hashes** still
  match. The retained benchmark was not rerun or rewritten for unrelated source
  moves.

The database run used a uniquely named temporary project and a copy of current
Supabase source, without local environment files or linked-project state. Only
the temporary project ID and database/shadow ports (56232/56230) differed from
the checked-in configuration. The Edge suite used an explicit loopback test
database and denied default port 54322. The existing local stack was preserved;
the temporary containers and volumes were removed and their absence verified.

These are uncommitted working-tree checks, not clean exact-SHA Candidate
Validation or hosted/device evidence. The independent path/contract review found
no runtime issue; its stale O2-status finding was corrected here. Future work
should begin with the O3 inventory refresh and preserve the separate AI
acceptance checklist.

## O3 implementation and verification

O3 starts from `5a4da4b2b`, after fast-forwarding the pushed organization
branch. Its tree is identical to the O1–O2 checkpoint `f34814e70`; the
additional commits merge the existing AI work and main history.

| Original path under `_shared/` | O3 path                    |
| ------------------------------ | -------------------------- |
| `fieldChatDailyUsage.ts`       | `fieldChat/dailyUsage.ts`  |
| `fieldChatReservation.ts`      | `fieldChat/reservation.ts` |
| `fieldChatResponse.ts`         | `fieldChat/response.ts`    |

Their three colocated unit tests move with them. Each runtime helper reaches
only Insight, Explore-post, and Species Dictionary chat. The path audit also
covers route database modules, handlers and handler tests, migration/source
contract tests, the documentation contract test, and the two explicit
helper-test paths in `.github/workflows/deploy.yml`. Current ownership and test
commands follow the new paths; O1/O2 measurements and evidence above remain
historical.

The move changes only relative imports in runtime helpers and consumers.
PostgreSQL retains atomic admission and daily caps; RPC timeouts, fail-closed
result validation, stable errors, quota recovery, request pairing, deterministic
assistant IDs, replay delays, and route persistence order remain unchanged.
`response.ts` retains its existing `insight-chat/types.ts` dependency. Generated
deployment identity remains at the shared root and is regenerated with the
existing tool. No AI adapter, model setting, schema, dependency pin, endpoint
name, or public payload changes.

Production delta: **three runtime files / 506 lines relocated**, zero net
runtime files or lines added, and no new declarations or wrappers. All three
helpers and their colocated tests match the prior source after only the required
relative-import substitutions. Functions still contain **368 non-test TypeScript
files / 71,556 lines**; root shared modules decrease from 58 to 55.

Local verification passed:

- Focused helper, actual-SDK, route, source-guard, and migration-contract tests:
  **98 tests / 6 steps**, with networking denied.
- Complete Edge suite against a fresh disposable database: **2,048 tests / 190
  steps**, zero failures and no database skips.
- Complete catalog gate: **52 files / 388 assertions**. Database lint found no
  schema errors. Advisor error-level gates passed, retaining the same **105
  security / 80 performance warnings** recorded in O2; no SQL changed.
- `make test-supabase-tooling`: **312 tooling tests**, plus the **19 DTO tooling
  tests / 20 executable wire-contract tests** and shell checks.
  `make validate-edge-dto-contract` also passed.
- Recursive type checks of all **101 entrypoints**, lint (**746 files**), and
  Functions/scripts formatting (**938 files**).
- Generated bundle identities and all **101 endpoint configurations** verify;
  **101 isolated graphs / 364 runtime files** validate. Each moved helper has
  exactly the same three endpoint consumers.
- The complete diff selects **all 101 Functions** in the deployment planner: the
  changed workflow is a fleet-wide control path; deleted shared paths also
  independently select the full fleet. This result does not authorize
  deployment.
- All **29 AI source fingerprints and two benchmark artifact digests** remain
  unchanged. Historical AI evidence was neither rerun nor rewritten.
- The directory guide covers **101 endpoints and 55 shared-root runtime
  modules** exactly once; **182 local links** across the directory guide, Field
  Chat README, and this RFC resolve. Old source paths remain only in historical
  RFC records and the old-to-new map. Changed Markdown and `git diff --check`
  pass.

The database gate used a new isolated temporary project reconstructed from
current source, with database/shadow ports **56332/56330**. The existing local
stack was preserved; the Edge run explicitly denied default port 54322. The
repository config remained unchanged. The gate replayed migrations, ran catalog
and Edge tests, linted the database, and ran advisors using pinned CLI 2.109.1.
Its temporary database container and volume were removed and their absence
verified. Deno was 2.9.4. The user skill-link check still points to the original
checkout; both reviewed package trees are byte-identical to this worktree.

The independent concurrency and contract review found two stale workflow test
paths; both were corrected before the gates, and the final review found no
remaining issue. These are local working-tree checks, not exact-SHA Candidate
Validation, hosted/device verification, or deployment evidence. Checkpoint O3
separately and preserve the original AI acceptance checklist before selecting
further organization work.
