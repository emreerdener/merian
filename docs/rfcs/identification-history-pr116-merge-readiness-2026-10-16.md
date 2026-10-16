# PR116: frozen inactive integration and merge-readiness proposal

Status: October 16, 2026. **Feature scope frozen locally by human instruction;
merge readiness remains open.** This record prepares the exact review and
authorization boundary. It authorizes no push, merge, workflow dispatch,
deployment, hosted test, activation or device installation. AWS remains
unapproved; all product, storage and runtime limits remain unchanged.

## Frozen source and publication boundary

- Repository: `emreerdener/merian`;
  [PR #116](https://github.com/emreerdener/merian/pull/116), branch
  `codex/publication-delivery`, base `main`.
- Frozen implementation: `ca5a30f76e48acb157ed8d013186d0b3ca79fe6f`, tree
  `d0ae0ce25a7016aef9dfbb73b0a5e080e51ca00f`.
- Frozen local documentation checkpoint:
  `fdddf66198f0fbfd568534c62fa4b3a7e18e3254`. This proposal and synchronized
  status notices are a documentation-only addition to that checkpoint.
- Read-only GitHub inspection on October 16 still reports remote PR head
  `87893226850031506eb008fcd26752701c5dd456`, base
  `167dbacb03b5fc3b0cc70cc9d04d3c74b21552fe`, open/draft/unmerged. The remote
  head has 266 commits and 1,071 changed files. The local checkpoint is 101
  commits ahead and changes 1,448 paths against that observed base. These are
  distinct candidates; the remote PR description and green checks do not qualify
  the newer local tree. GitHub's mergeable flag is not readiness.
- Retain the full committed foundation through the frozen implementation,
  including prepared history/reanalysis, initial admission/media contracts,
  local verifier characterization, native ownership/schema and BI-1 integration.
  This is a cumulative foundation review, not just a review of BI-1's last diff.
- Exclude all 102 pre-existing dirty/untracked paths. In particular, the dirty
  deployment workflow, migration planner, capture UI and history UI changes are
  not part of this candidate. Read committed files when assessing it.
- Add no further product features to PR116. Common-allocation/original-photo
  integration and remaining CPM runtime work belong to the next PR after this
  integration boundary. Later individual-version deletion/source export and
  Identification/History/insight-menu redesign retain their approved order.
  Capture-tools/Add details remains separately owned. No task is canceled or
  accepted merely by moving it beyond this PR boundary.
- Only a demonstrated merge blocker may justify a follow-up source correction;
  name its files, owner, changed contracts and invalidated evidence before a
  separately reviewed implementation scope. The present request does not
  authorize such corrections, a rebase, cherry-pick, split or history rewrite.

The earlier October 13 `70b75279f` proposed cut is historical. This explicit
freeze supersedes that cut and the summaries' recommendation to begin new
common-allocation work immediately. It does not supersede their safety or
acceptance requirements. Once reporting is committed, record the final local
proposal commit separately. A publish candidate and prospective merged SHA must
be pinned later; neither is invented here.

Local audit evidence: `.artifacts/pr116-merge-readiness-20261016/`, including
`frozen-manifest.json` (base/head/tree and Git blob identities for every changed
path), `scope-files.txt`, `local-commits.txt`, and preservation receipts. The
manifest is an inventory, not a claim of full code review or qualification.

## Evidence that can be reused

[ISQ-1](client-prepared-media-isq1-isolated-result-2026-10-16.md) qualifies the
isolated local NCO/BI part of A19 at the implementation SHA above: reproducible
XcodeGen 2.45.4 output, project/migration/CI tooling, Debug compilation, 561
acceptance tests, 27 UI cases, ten performance workloads, 5,923 unit tests,
critical-result validation and unsigned Release compilation. Its 9,363
per-device executions are a separate count. Performance remains report-only,
with no adopted baseline and missing hitch samples. Preserve failed earlier
attempts and exact independent/IC-1 receipts.

Do not repeat unchanged local native suites just to prepare this proposal. Reuse
requires unchanged relevant blobs, toolchain, configuration and test selection,
recorded explicitly. This evidence does not replace required CI on the final
PR/merge candidate, full backend qualification, ordinary-path review, hosted
acceptance or user-run device qualification. Existing remote successful checks
and Vercel statuses apply to the old remote head only.

## What a push or merge can do

The committed `.github/workflows/deploy.yml` runs on every main push and manual
dispatch. Candidate Validation and production-scope/hold jobs precede an
automatic `Production` job targeting Supabase `qlarqavoqhkuwzmevrmf`. The source
policy expects no environment reviewer gate. Live settings have not been
verified by this proposal. Never rely on a future human approval screen to stop
that workflow.

Production scope uses the complete undeployed range against the last actual
successful deployment, not just this PR's diff. Configuration/workflow changes
can select the entire function fleet. If permitted, the job can predeploy
compatibility functions, push pending database migrations, enforce privileges,
synchronize secrets, deploy functions, conditionally perform the existing Field
Chat cutover/activation and run production smoke/reconciliation calls. Disabled
history flags do not prevent those operations. An exact future deployment plan
also requires the real deployed baseline and migration ledger; this proposal
does not claim to know either.

The frozen source includes active `identification_history_integration_hold` in
`services/supabase/release-holds.json`. The pre-Production hold must return
`held` / `deploy_allowed=false`, preventing entry into Production, migration
push, secret synchronization, function deployment and smokes. The in-job
automatic-release verifier separately rejects active holds. Preserve the
inactive Field Chat exception unchanged. Preserve the hold on both automatic and
manual paths; never dispatch deploy.yml as a validation shortcut.

This hold is local source, not protection already installed on remote main or
older jobs. It stops the **entire Supabase production job**, including unrelated
backend releases, after a separately authorized integration. That tradeoff was
approved in the October 13 plan and is retained. Clearing it requires a separate
exact-SHA/target backend release decision and complete undeployed release plan.
Feature activation remains a later separate decision. Its three recorded exit
criteria remain `history_exact_target_release_approval`,
`history_full_undeployed_plan` and `history_live_controls_and_jobs`; this
proposal closes none of them.

The hold does not govern external Vercel deployments, already running jobs,
other scheduled/manual workflows or app distribution. The old PR has successful
`Vercel – naturebook` and `Vercel – naturebook-admin` statuses, so external
hosting is a concrete pre-push concern even though the changed web/admin source
is limited to dependency/security files and READMEs. Verify both preview and
main production behavior. Unknown behavior blocks a zero-deployment push/merge
claim. Any control change, job cancellation or deployment needs its own named
authorization; do not perform it as incidental readiness work. Leave schedules
unchanged. In particular, the committed taxonomy import can mutate production on
a schedule and its separate checklist job can push source; scheduled health
monitors also access Production. The history hold is not a repository-wide
production freeze. The committed iOS workflow creates an unsigned validation
archive, not a TestFlight release; dashboard-side automation remains unverified.

## Merge gates and ownership

| Gate                      | Required evidence before merge authorization                                                                                                                                                                                                                                                                                                                                                                                               | Current disposition / owner                                                                                                                                        |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| M1 exact scope            | Frozen base/head/tree and complete changed-path/commit inventory; clean selected source excludes all unrelated paths; final merge result has no unreviewed changes. Reconcile current main before choosing merge strategy.                                                                                                                                                                                                                 | Inventory retained; final publish and merge identities pending. History primary owns preparation.                                                                  |
| M2 cumulative safety      | Independent review of the full candidate across native persistence/Auth/capture, backend admission/funding/unknown recovery, migrations/RLS, DTOs, web/admin dependencies and CI. Default-off checks plus ordinary startup, migration, existing initial submission, deletion and account-switch compatibility. Existing admitted operations retain meaning.                                                                                | ISQ is partial evidence; whole-PR signoff remains open. Independent reviewer plus IC-1 for its interface boundary; history primary sole writer.                    |
| M3 affected gates         | Complete non-skipped Supabase Candidate Validation (recursive type/format/lint, tooling, disposable migration/catalog/privilege/concurrency/contract/advisor gates); iOS Build and Test and Startup Safety/Project Guardrails; Web/Admin Quality, Markdown Quality and Agent Quality as selected by their full-diff detectors. Record actual workflow checkout SHA, source head, base and merged tree, required job results and artifacts. | Old remote green checks do not transfer. Reuse qualified local native evidence where identities match; final hosted CI awaits separately approved push/validation. |
| M4 inactive isolation     | Inventory effective default-off gates and nil ordinary DI access, no new schedules/automatic dispatch, verifier experiment excluded from ordinary function discovery, unchanged provider/funding semantics. Review migrations and code that execute despite flags; default-off cannot waive their regressions.                                                                                                                             | Requires exact cumulative audit. A defect reachable on an existing ordinary path is a merge blocker, not deferred feature acceptance.                              |
| M5 deployment containment | Exact manifest digest and workflow/job graph; fail-closed malformed/active hold coverage for automatic/manual paths; no production credentials before denial; inspect live branch/environment controls, older queued/running mutation jobs, external Vercel hooks and distribution automation before push and again before merge.                                                                                                          | Source hold exists; live containment unverified. Unknown or unsafe effects block. No controls changed by this record.                                              |
| M6 review and approval    | Independent and IC-1 concurrence on the final candidate and disposition of findings, re-review after corrections; separate human exact push and merge approvals, with explicit expected CI/publication effects.                                                                                                                                                                                                                            | This request authorizes proposal/freeze/review only. Neither approval exists for the frozen candidate.                                                             |

If a required check cannot run, retain the reason as a blocker. Do not replace
it with an old success, skip, mergeable status or reduced suite. If a
merge-queue or synthetic merge commit is tested, bind it to the approved
head/base/tree; base drift or conflict resolution invalidates that binding and
requires review and affected requalification. No automatic “merge when green.”

Device/provider/storage qualification may remain open only for paths proven
unreachable in this inactive integration. A native schema migration executes
outside a history feature gate; its compatibility must be evaluated explicitly.
Do not relabel missing evidence for an existing reachable path as
activation-only. Distribution and hosted schema application remain prohibited
even after source integration. Full A19, CPM G1–G4, original retention, audio
signal/quality, video, shared references/release/late cleanup, integrated
history and external/device gates remain open. Broader engine hardening and
Field Trip reconciliation retain their separate ownership and acceptance
requirements.

Fresh initial/reanalysis requests require photo/audio/video; optional supporting
descriptions remain immutable. Existing originals suffice; missing media blocks
or requires explicit replacement. Historical text-only records and exact
server-admitted recovery remain supported; locally queued text-only drafts are
not accepted replays. Unknown AI execution permits original-operation recovery,
not another invocation or refund. No acceptance requirement is relaxed here.

## Proposed next checkpoint and subsequent approvals

Recommend **one two-hour read-only readiness audit**, at most 128 MiB new
retained evidence, maintaining the 20 GiB free-space floor. No builds, tests,
checkout creation, downloads, source edits, hosted data queries or deployment.
Use the frozen Git objects and existing evidence. Inventory exact coverage/gaps
for M1–M5, current GitHub controls/jobs and accessible Vercel integration
settings; if permissions are missing, report the precise unavailable read
without changing access. Review only configuration metadata, never secret values
or user data. History primary produces one consolidated blocker list with named
owners and the smallest justified correction/qualification scope; independent
and IC-1 review it. Stop at completion or a genuine external blocker. Do not
start an open-ended test loop or resume the old automation.

This audit is proposed for approval, not executed by preparing this document.
The current read-only PR metadata/source review is evidence for the proposal,
not a claim that live controls have already been audited. If missing gates need
new local execution, return one bounded qualification packet with commands,
candidate/tool identities, disk/evidence budgets and review before execution. Do
not repeat the completed ISQ suites without an identified invalidation.

After readiness gaps are resolved, the **push packet** must name the exact local
SHA, expected remote old SHA, branch and PR; include a fast-forward proof,
frozen diff/manifest, independent/IC-1 receipts, allowed CI and explicitly
approved external effects or verified containment. It must exclude PR115 and all
unrelated work. Publication of a new SHA and updating PR116's title/body require
that later authorization. Proposed final title: “Prepare inactive identification
history and media ownership foundation”; description must describe the final
cumulative scope and evidence, not only the old video checkpoint.

After authorized publication and exact CI, the **merge packet** must name the
remote head, current main base, proposed merge strategy/result tree, required
checks and review receipts, deployment-control observation time, no unsafe
queued/running job, and preview/production hosting disposition. The
recommendation is merge only while backend hold remains active and all
publication effects are separately authorized or demonstrably contained. If
containment cannot be established, keep PR116 draft/unmerged. Do not bypass a
failing gate to force a checkpoint.

After any later authorized merge, read-only verification must confirm the
expected main SHA, candidate checks and held/skipped production mutation job,
and absence of unapproved external deployment. A surprise mutation is an
incident requiring its own authorized response, not permission to perform a
rollback. Start the next feature PR from the integrated main only after this
boundary is complete. No new PR or branch is created now.

## Review record

Exact independent and IC-1 review receipts, document digests and preservation
checks are retained under `.artifacts/pr116-merge-readiness-20261016/`. Review
concurrence on this proposal must not be presented as M2/M3/M5/M6 completion or
merge/deployment approval. No runtime gate is changed by this document.
