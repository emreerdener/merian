# Identification history: final integrated review plan

Date: 7 October 2026 (UTC)\
Status: Planned; review execution has not started\
Initial candidate: `eb0d4e7c1d211d7cba26f8b0f3ffb7b3de9e41ed`\
Scope: The complete reversible-reanalysis feature, including merged PR #115 and
follow-up PR #116, plus explicitly identified interactions with local changes

## Objective and boundaries

Determine whether the completed feature is coherent, maintainable and safe to
advance to end-to-end device and nonproduction qualification. Review complete
user journeys and shared invariants across native persistence, UI, backend,
media, funding, publication and deletion. Passing isolated slices is supporting
evidence, not proof that their composition is correct.

Scheduled follow-ups are paused at the user's request. This document plans the
review; it does not start reviewers, builds, implementation or external
operations. Resume work explicitly in this thread. Keep every activation gate
false and ordinary live access disabled throughout review. No merge, deployment,
hosted scheduling, activation, installation or TestFlight action is authorized
by this plan.

Do not introduce speculative capabilities or broad cleanup projects. Fix a
verified defect with the smallest coherent change. Record low-risk stylistic
improvements separately unless they obscure correctness or violate an existing
architecture contract. Preserve all unrelated user edits.

## 1. Establish the exact review baseline

The primary agent records the committed candidate SHA, PR #115's merged feature
range, PR #116's current diff and the full set of feature-owned source paths.
Reviewing only the latest PR would miss foundational storage and safety code.
Identify the pre-feature baseline from Git history rather than guessing it from
current main.

Keep three evidence scopes separate:

1. Committed feature implementation and its exact-SHA CI evidence.
2. Uncommitted workspace changes, identifying feature overlaps and integration
   risks without absorbing or reverting user work.
3. The precise working-tree fingerprint used by any local test or build.

Record current CI conclusions by SHA, toolchain, relevant flags and test counts.
A queued, cancelled or still-running workflow is not a pass. A dirty-tree build
cannot qualify a different clean commit. Reuse valid existing evidence; do not
rerun suites merely because this review has a new name. Do not duplicate active
builds or change sources during a build that pins source identity.

Deliverable: a scope manifest, source-owner map and evidence ledger. For each
critical invariant, record source symbols, callers, persistence boundary,
negative-path tests and any unqualified environment requirement.

## 2. Review in three independent streams

Use read-only project agents for independent review. The primary agent owns all
edits and integrates findings. With the current four-slot limit, run at most
three reviewers alongside the primary. Load the applicable iOS, migration,
Supabase/SQL, API and documentation skills before reviewing their surfaces.

| Stream                                       | Reviewer                  | Required coverage                                                                                                                                                        |
| -------------------------------------------- | ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Native lifecycle and presentation            | `merian_reviewer`         | SwiftData migration, queue classification, file preparation, admission/delivery, Auth teardown, immutable UI tickets, every protected entry point and legacy bypass      |
| Backend authority and privacy                | `merian_reviewer`         | SQL lock order, RLS/grants, durable identities, revisions, funding, provider dispatch, publication, private/public erasure, expiry and account merge/deletion            |
| Cross-surface contracts and release evidence | `merian_contract_auditor` | Wire/DTO parity, documentation drift, public projections, Field Trip ordering, architecture boundaries, feature gates, generated artifacts, CI scope and evidence limits |

Use `merian_explorer` only for a specific unresolved ownership or execution-path
question. Do not launch duplicate exploratory sweeps or parallel writing agents.
Each reviewer returns actionable findings with exact file/symbol evidence,
trigger, impact, violated invariant and a proposed proving test. A suspicion
without a reachable path stays an investigation item rather than a confirmed
bug. Report areas examined even when no finding results; “no findings” must have
a stated scope and limitations.

## 3. Trace the complete workflows

Trace each workflow from the actual user action through durable state, server
mutation, reconciliation and visible outcome. Examine cancellation, lost
responses and re-entry at every external-I/O boundary.

| Workflow                                | Invariants and boundaries to prove                                                                                                                                                                                                                                                                                                       |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Existing scan → enrollment              | Preserve the displayed correction, selection, confirmation, rejection and community state. Earliest history ordering must never select an older result during migration. Enrollment is explicit; opening History/status does not enroll.                                                                                                 |
| Reanalyze → prepare → upload → complete | Freeze the exact source and user-selected evidence before suspension. Persist identities and consent before I/O. Preserve bytes, order, digests and fixed expiry. Append one result; never replace the parent or automatically change selection.                                                                                         |
| Interrupted/restarted work              | Recover the exact child/result before fresh execution or file access where required. Distinguish local claim generations from provider attempts. Unknown execution cannot gain an automatic successor, refund or legacy funding path.                                                                                                    |
| History → preview → restore → Undo      | Preview has no selection side effect. Restore and Undo use expected revisions and receipts. History remains readable without inference consent. A delayed callback cannot overwrite a newer device's choice.                                                                                                                             |
| Confirm/reject/Undo/community authority | Authority belongs to the exact analysis. Review changes advance observation revision. Reconcile target and selected state atomically; confirmation of A cannot authorize B. Verify broader taxa, non-biological, withdrawn and imported results.                                                                                         |
| Community help → public publication     | Begin with no selected photos; retain explicit ordered consent and exact note policy. Prevent competing operation UUIDs. Source-bound moderation precedes copying. Binding uses the approved cohort, original keys and expiry; historical admission does not assert current visibility.                                                  |
| Public authority changes                | Evaluate the published analysis independently of private selection. Revocation makes identification unresolved and removes species-dependent eligibility while preserving eligible discussion. Privacy/moderation may hide the post. Explicit shared-identification updates are distinct operations.                                     |
| Field Chat → retry → refresh            | Persist the actual displayed ticket and original message IDs/text. Save immutable context before dispatch; recovery uses it verbatim. Only the original fresh grant authorizes execution. Proven no-admission receipts alone release held occupancy; refresh never automatically sends.                                                  |
| Deletion, expiry and account transition | Observation deletion wins over child insertion, upload, replay, selection and publication. Private/public cleanup survives cascades. Full account purge and Auth drains complete in order; stale tasks cannot write into another account. Scientific retention materializes only allowed scalar facts before private history is removed. |
| Legacy and rollout coexistence          | Old queued replacement deletion cannot erase enrolled history. Non-biological expiry cannot erase valid retained history. Protected nil/stale access never falls through to legacy actions. Default-off installation and backend gates remain coordinated.                                                                               |

Review names, ownership and component structure while tracing these paths:
explicit dependencies instead of hidden globals, one owner per durable
transition, small closed transports, bounded memory/paging, coherent error
classification, and teardown tied to actual task exit. Flag duplicated
invariants, unreachable compatibility code, swallowed errors and fixtures that
bypass the production boundary they claim to test. Avoid refactoring only to
reduce line count or rename stable components.

## 4. Challenge the integration with adversarial cases

Map every case to an existing executable test or add a focused reproducer when
coverage is missing. Do not count source-string assertions as proof of runtime
concurrency or database behavior.

- Lost response after quota admission, result commit, review receipt, public
  binding or chat completion: exact replay recovers one outcome without a second
  charge or provider call.
- Observation/account deletion during inference, upload, public copy and
  reconciliation; delayed writes after cleanup cannot recreate private state.
- A → B → A selection with out-of-order authority/Field Trip reconciliation;
  revision 10 must not restore credit removed by revision 11.
- Review, selection and community withdrawal racing across devices; revision
  exhaustion, stale Undo and paired-state mismatch fail closed.
- Restart at files-pending, admission, claimed dispatch, receipt-save and
  cleanup boundaries; account switching at every await and after token refresh.
- Two devices submitting different operation IDs for the same observation; held
  local loser and remote winner remain separate without inferred consent.
- Partial/malformed history or status pages, unknown job kinds, damaged queue
  metadata and expired evidence; no silent fallback, timer spin or new identity.
- Migration with an existing correction and pending legacy deletion; first and
  second launch preserve the intended selected identification and queued fences.
- Photo digest/length mismatch, unsupported container, cancellation, transport
  uncertainty, fixed staging expiry and failed cleanup; only conclusive policy
  rejection becomes terminal remediation.
- Authority revocation after publication and real cache retention; private
  selection must neither republish nor restore a revoked public identification.
- Native form dismissal/reopening, delayed child-sheet callbacks, stale engine
  generations, absent prepared access and repeated taps; one exact saved intent
  survives uncertainty without duplicate submission.
- Account merge/deletion collisions across chat messages, execution fences and
  no-admission seals; preserve whole-transaction rollback and restricted
  scientific retention without private payload leakage.

## 5. Triage, repair and re-review

Keep one findings ledger with these fields:

| Field                 | Required content                                                                                          |
| --------------------- | --------------------------------------------------------------------------------------------------------- |
| Identity and severity | Stable finding ID; critical/high/medium/low with user-visible or operational impact                       |
| Evidence              | Candidate/fingerprint, exact symbol or line, reachable trigger, observed behavior and violated contract   |
| Verification          | Existing test gap, minimal reproducer and expected assertion; environment limitations                     |
| Resolution            | Smallest fix, affected surfaces, owner, commit and documentation updates                                  |
| Closure               | Passing evidence plus independent confirmation, or explicit unresolved/deferred disposition and rationale |

Triage findings once across streams to remove duplicates. Fix confirmed
security, data-loss, incorrect authority, billing, deletion and execution-replay
bugs first. A failed test is investigated before being labelled flaky. Retain
original failures and reproduction evidence; never weaken an assertion solely to
obtain green CI.

Run one initial integrated review, one repair pass and an independent review of
the fixes and affected boundaries. Expand only for a concrete newly discovered
risk or shared root cause. If a substantial redesign is required, present the
finding and a bounded revised plan instead of silently beginning another series
of implementation slices. No open finding disappears because the review time or
context window ends.

## 6. Validate the final reviewed candidate

Use focused checks during repair, then the complete affected-surface gates for
one final candidate. Resolve exact commands/selectors from current canonical
owners and executable manifests at execution time.

- Native: managed local build cache, full unit gate, startup/migration tests,
  exact required UI smokes and affected broader UI cases, strict source/lint
  guards and generated-project membership. A new migration needs disk-backed
  old-store fixtures; never edit retired snapshots.
- Backend: freshly reset disposable database with all new migrations copied,
  catalogs before real concurrency tests, full backend/tooling gates, strict
  schema lint, privileges/advisors, generated DTO parity and each endpoint's own
  deployment configuration. Never substitute root-only type checks.
- Contracts/docs: cross-language payload and error semantics, byte/deadline
  bounds, all changed ownership READMEs, current normative contracts and rollout
  controls. Historical RFC slice summaries must not be mistaken for current
  completion status. Preserve dated evidence; add status links where needed.
- Candidate: inspect exact-SHA CI and archive results, record actual suite/case
  counts and skips, and verify no unrelated workspace hunks entered commits.
  Record any check that could not run and its reason.

Do not repeat unaffected web/admin gates merely because the feature touches
multiple platforms; use current dependency/surface scope and exact-SHA CI.
Conversely, changed public projections or shared API semantics require their
actual consumers to be reviewed and tested.

## 7. Separate review closure from external qualification

The user can perform the
[guided device interface review](../development-guides/24-identification-history-device-review.md)
while code review proceeds. Those Debug fixtures are synthetic, in-memory and
reset on launch. They do not establish live reanalysis or restart durability.

After integrated review, remaining acceptance still includes real V57-to-V58
install-over and second launch, sustained on-device heap/lifecycle evidence,
hosted CPU/memory/provider deadlines, actual private-storage and CDN revocation,
service-auth denials, independently scheduled private/public erasure and backlog
monitoring. The prepared detailed matrix remains in the local
`.artifacts/identification-history-remaining-acceptance.md`; migrate approved
external results into candidate-specific evidence records, not this plan.

The user owns device execution. Nonproduction backend/storage/CDN target input
was requested once and remains pending; do not repeatedly ask the same question.
Before external mutation, prepare the named environment, exact operations/SHA,
spend/call ceiling, evidence collection, cleanup and rollback for explicit
approval. No production defaults may stand in for an unspecified test target.

## Completion criteria and final report

Integrated review is complete only when:

1. Every workflow and critical invariant above has an explicit reviewed owner
   and evidence disposition; unreviewed areas are not described as safe.
2. No unresolved critical/high issue remains. Any medium issue affecting a core
   invariant blocks closure; other deferred issues have a written reason and
   explicit disposition rather than silent omission.
3. Fixes receive independent review and required tests pass for the final
   candidate. Evidence accurately distinguishes dirty-tree, clean-CI, simulator,
   unsigned archive and physical-device results.
4. Documentation and executable contracts agree, and all activation gates remain
   disabled.
5. External qualification gaps have named next steps and remain visible.

Produce one final report containing candidate identity, reviewed coverage,
findings and resolutions, actual validation, residual risks and the remaining
acceptance matrix. State separately: **integrated code review complete**,
**ready for end-to-end qualification**, and **production readiness**. The first
two do not imply the third. Do not call the feature production-ready while
required device, storage, operational or deployment evidence is missing.

## Contract entry points

- [Original feature RFC](reversible-reanalysis-and-identification-history-2026-10-02.md)
- [Database schema](../backend-and-data/04-database-schema.md),
  [API contracts](../backend-and-data/05-api-contracts.md) and
  [startup/store recovery](../backend-and-data/08-startup-store-recovery.md)
- [Funding settlement](../backend-and-data/18-complimentary-pro-scans.md) and
  [scientific retention](../backend-and-data/17-scientific-observation-retention.md)
- [Insight presentation](../features-and-hardware/05-insight-sheet.md),
  [native History ownership](../../apps/ios/Merian/Features/Insights/History/README.md)
  and
  [backend history ownership](../../services/supabase/functions/_shared/analysisHistory/README.md)
- [Testing strategy](../development-guides/08-testing-strategy.md),
  [runtime qualification](../development-guides/18-ios-runtime-quality-and-benchmarking.md)
  and [release evidence rules](../release-evidence/README.md)

This is a candidate review plan, not a replacement for those normative
contracts. No review findings or new readiness claims are asserted by its
creation.
