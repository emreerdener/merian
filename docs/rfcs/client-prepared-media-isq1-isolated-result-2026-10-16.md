# ISQ-1: isolated native qualification result

October 15 local / October 16, 2026 UTC. All planned execution passed on the
clean committed NCO/BI candidate. This closes its isolated local source gap
subject to final independent and IC-1 concurrence recorded in
`.artifacts/local-ios/isq1-20261015/result-review-02.json`. It does not close
P1, the alpha, PR #116 readiness, or later version-actions/redesign acceptance.
Activation remains disabled, ordinary P1 access nil, AWS unapproved, and all
existing product/runtime limits unchanged.

## Candidate and authorized execution

The human approved the
[ISQ-1 scope](client-prepared-media-isolated-qualification-proposal-2026-10-15.md)
for **03:07:08–07:07:08 UTC**, with 16 GiB additional working allocation, 2 GiB
additional retained evidence and a 20 GiB free-space floor. The later
instruction to continue to a meaningful checkpoint removed routine approval
prompts; it did not expand source ownership, external authority, or limits.

Candidate: `ca5a30f76e48acb157ed8d013186d0b3ca79fe6f`, tree
`d0ae0ce25a7016aef9dfbb73b0a5e080e51ca00f`, in
`/Users/emreerdener/.codex/worktrees/isq1-qualification/merian`. The clean
worktree contains only committed source and retains its own managed build and
package caches. No source correction or unrelated-file import was made.

The first XcodeGen attempt failed before generation because command lookup
selected installed version 2.45.2. Its
[original stopped result](client-prepared-media-isq1-qualification-result-2026-10-15.md),
logs and reviews remain historical evidence. The human then approved selecting
installed **2.45.4** without extending the deadline. The resumed process used
`/opt/homebrew/bin` before `/usr/local/bin`, rechecked tools in the clean
worktree, and received exact independent/IC-1 concurrence on manifest SHA-256
`079e2f9647581a4577c383217ed358e874d825c4b37638c542a164423cb22194`. IC-1
execution review: `01a142ba-2748-7b12-964c-9c59a524cf37`.

Environment: MacBookPro18,1, macOS 26.6.2 arm64, Xcode 27.0 (`27A266a`), iPhone
18 Pro simulator, iOS 27.0 (`24A434`). XcodeGen 2.45.4, Deno 2.9.4, and Ruby
xcodeproj 1.27.0 were selected explicitly. The tracked package lock remained
unchanged; no dependency upgrade or tool installation occurred.

## Results and applicability

| Check                                                                 | Isolated candidate result                                                                       |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| XcodeGen and generated project identity                               | Passed; generated project exactly matches committed bytes                                       |
| Project, migration guardrails, full iOS CI tooling, source membership | Passed; seven target source inventories checked                                                 |
| Managed Debug build                                                   | Passed                                                                                          |
| Runtime acceptance                                                    | 561 tests passed; zero failures or skips                                                        |
| Runtime UI                                                            | All 27 required cases passed; zero failures or skips                                            |
| Performance workload execution                                        | All ten selected workloads passed, with three invocations each; report-only                     |
| Complete `merianTests`                                                | 5,923 tests passed; zero failures or skips                                                      |
| Actual critical-test validator                                        | Passed on extracted full-unit summary and test tree                                             |
| Generic unsigned Release compilation                                  | Passed; no archive, installation or distribution                                                |
| Source and primary preservation                                       | Clean worktree and pinned hashes unchanged; all 102 unrelated primary file identities unchanged |

The complete-unit XCResult separately reports **9,363 per-device executions**;
that is not the top-level test count. BI-1's earlier **5,945** total belongs to
the dirty shared checkout and remains historical evidence. No selector was
removed to reconcile these counts. The checked-in critical validator passed
against this clean candidate's actual result tree.

The audit exports 55 metric series, each with 30 samples. There is no reviewed
matching baseline. High-variance observations remain visible, and the requested
repeated-Insight hitch metric is **unmeasured**, not zero. These samples do not
qualify sustained device memory, capture fidelity, audio identification quality,
thermal behavior, real background transfers, hosted execution, or product-wide
storage accounting. No new threshold is adopted.

## Evidence and storage reconciliation

Primary evidence: `.artifacts/local-ios/isq1-20261015/`. Clean-worktree audit:
`.artifacts/local-ios/audit-3b3d9c6e7d2644cbb086788fa2a2df00/`. The audit owns
raw samples, completeness checks, environment and source fingerprints. Its
source fingerprint is
`994f7dbea6e0fade6fc212dd02385238ef996432cb621091ab11a72d37ecfb7a`; its
dirty-source flag is false.

Retained clean-worktree XCResults:

- Debug build: `b1141baefe8349939dd6294c87364257.xcresult`.
- Acceptance: `ed62bbb34b43455b9154c989364d336b.xcresult`.
- UI: `a2d2b8d8b56f4f54899b99f2dc210a98.xcresult`.
- Performance: `b6ad57a328cc474d8191820b3f354abc.xcresult`.
- Complete unit: `b378a663fd71490eac9edcb55fdd7409.xcresult`.
- Unsigned Release: `0214151fc47f4d7888dced5095b4faf9.xcresult`.

Initial absolute-path accounting falsely counted pre-existing simulator data as
new after installation changed the app-container UUID. All 69 unique retained
NCO fixture names established the same complete container relocation while the
old container was absent. Independent and IC-1 review concurred on normalizing
that namespace, crediting only the prior size at an exact reconstructed baseline
path. Unknown paths, additional fixtures and growth remain fully charged;
normalized-key collisions fail. The mapping and old-root absence are checked
before and after each post-run inventory. The full-unit run retained 23 new
fixture roots, which are charged rather than excluded.

Raw alarms and both corrected method versions remain retained. This is
incremental storage accounting, not content equality or continuous peak-usage
proof. Physical free-space changes were never used to waive logical evidence
usage. Final measured bounds are in `final-storage.json` and
`result-resumed.json`; retain the worktree, dependencies and evidence at
handoff.

The first full-unit summary extraction encountered a local sandbox permission
error while xcresulttool indexed its result bundle. That failed extraction is
retained in `extraction-attempt-01.json`; extraction with the required worktree
access succeeded. No test rerun was needed. An optional process-status lookup
also timed out in automatic permission review; build monitoring continued via
the existing managed session and logs. Neither event changed the tested source.

## Acceptance disposition and next checkpoint

This result establishes the isolated local NCO/BI qualification portion of A19.
The full alpha/final-PR candidate gate remains open. The approved order remains:

1. Common allocation and original-photo closure: all concurrent allocators need
   one authority or an explicit reviewed exclusion. Exact originals, AI inputs
   and previews remain distinct; drafts survive refusal and interruption. Real
   camera/PhotoKit/file-protection acceptance remains user-run device work.
2. Audio/video preparation and immutable cohorts, including recipe compatibility
   and measured signal/identification quality; then server admission, shared
   references, erasure and contention under the recorded IC-1 ownership.
3. Integrated native/history journeys, external/resource/CI gates and separately
   authorized release operations; then individual-version deletion/source export
   and the approved Identification/History/menu redesign.

The next bounded recommendation is a common-allocation/original-photo ownership
and integration proposal using this isolated evidence, not another unchanged
qualification run. No later implementation is authorized by this result. The
capture-tools visual refactor, broader engine hardening and Field Trip closure
remain separately owned. A separate Supabase project is not required by this
record; use of the existing shared alpha target still needs named authorization.

Fresh initial and reanalysis submissions require photo/audio/video; retained
originals suffice. Missing media blocks submission, supporting descriptions
remain immutable, historical text-only records and exact admitted recovery
retain their meaning, and unadmitted text-only drafts require explicit
remediation. Unknown execution permits original-operation recovery and
reconciliation only, never another AI invocation or refund.

No push, merge, CI dispatch, deployment, hosted test, secret operation, device
installation, AWS action or limit change occurred. Disabled flags do not prevent
backend deployment on a future merge; exact CI/workflow and publish approval
remain necessary. Automatic scheduling remains stopped. Stop at this reviewed
local qualification checkpoint.
