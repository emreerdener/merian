# ISQ-1: isolated-source qualification and acceptance closure plan

October 15 local / October 16, 2026 UTC. **Proposal only. Execution requires
human approval after independent and IC-1 review.** Activation disabled,
ordinary P1 access nil, AWS unapproved, existing product and runtime limits
unchanged. Automatic continuation remains stopped.

## Recommendation and exact boundary

Approve one fresh **four-hour local qualification window**, including setup,
reviews and reporting. Qualify the committed NCO/BI source in one clean managed
worktree, then return an evidence-backed disposition of the remaining gates.
This packet authorizes no implementation correction and does not declare P1, the
alpha, or the later version-actions/redesign complete.

Pin source to `ca5a30f76e48acb157ed8d013186d0b3ca79fe6f`, tree
`d0ae0ce25a7016aef9dfbb73b0a5e080e51ca00f`. The
[BI-1 result](client-prepared-media-bi1-integration-result-2026-10-15.md) and
`.artifacts/local-ios/bi1-20261015/completion.json` record its local commit.
Shared-checkout evidence passed 96 focused tests, 5,945 unit tests, six critical
UI smokes, Debug and unsigned generic Release compilation. It does not prove
that this committed tree builds without the 102 unrelated dirty paths.

Source isolation is the reason for this new validation, not a reason to rerun
unchanged checks in the dirty checkout. History primary is the sole writer;
independent and IC-1 reviewers remain read-only. No new implementation writer,
capture visual handoff, engine-hardening assignment or Field Trip ownership is
created.

## Source, packages and storage authorization requested

Create one managed worktree pinned to that exact commit, after checking attached
worktrees for a suitable clean one. Never stash, reset, overwrite or transfer
unrelated primary-checkout changes. Record tracked/untracked primary file
identities before and after work. The worktree must contain only committed
source; local credentials and environment files must not be copied into it.
Disable any optional project setup actions that would exceed this packet; if
managed setup cannot be bounded, stop before creation.

All Xcode build/test invocations use `make ios-local-build` and its
checkout-local caches. Its `--isolated` option isolates DerivedData, not source.
For this sequence use the normal managed simulator/device caches inside the
clean worktree so compiled products can be reused. Do not symlink, clone or
share the dirty checkout's build caches. Explicitly allow the existing audit
runner's locked package resolution/download from the pinned `Package.resolved`;
no dependency upgrade, new tool installation, new simulator runtime download or
alternate build runner. If existing Xcode, XcodeGen, Ruby `xcodeproj`, Deno or
simulator prerequisites are unavailable, report the concrete blocker.

Request **16 GiB maximum additional checkout/package/build-cache allocation**
and **2 GiB maximum additional retained evidence**, separately accounted. The
latter includes logs, XCResults, extracted reports and all new retained
simulator/SQLite fixtures, wherever written. Count physical duplicates. These
are proposed work allowances, not changes to media/package/storage limits or
verifier thresholds. Before construction require at least **38 GiB free** (20
GiB floor plus both allowances); before each new command measure actual usage
and remaining headroom. Current read-only inventory is approximately 43.6 GiB
free; the existing checkout has 1.42 GiB package clones, 6.73 GiB simulator
products and 2.06 GiB device products. Those observations inform the budget but
do not guarantee the new build's peak.

Monitor space during long commands. If a bound or deadline is reached, launch
nothing further. Preserve evidence, let an already-running managed invocation
finish, and report any overrun rather than cancelling it or deleting evidence.
Do not edit sources during compilation. Do not remove dependencies, previous
results or user data to make room. Leave the worktree and package cache retained
at handoff; no automatic archive may discard ignored dependencies/evidence. This
is an admission/stop policy, not a hard filesystem quota guarantee.

## Proposed execution order

1. Record start and four-hour deadline, available space, existing active builds,
   exact source and package-lock hashes. Resolve any lock conflict by waiting
   within the window, never deleting locks, cancelling or duplicating builds.
   Verify clean worktree status and primary preservation inventory. Record exact
   independent/IC-1 concurrence on this source and execution manifest before
   running qualification.
2. Run `make xcodegen`; require generated output to match committed project
   bytes. A mismatch is a source-closure failure, not permission to fix or
   import the dirty project's output. Run `make validate-ios-project`,
   `make validate-ios-migration-guardrails`, `make test-ios-ci-tooling`, and
   `bash scripts/check-ios-project-source-membership.sh`. This checks the clean
   source/manifest graph and applicable tooling; no historical schema rewrite.
3. Run the existing managed runtime audit once on an already installed concrete
   simulator. The audit owns locked dependency resolution, one Debug build and
   its ordered acceptance, UI and performance phases from
   `scripts/config/ios-runtime-audit.json`. Record the config hash and expanded
   selectors at execution review; do not invent another selector list. Its
   performance phase runs the checked-in three iterations and remains
   **report-only** without a matching reviewed baseline. No resource threshold
   is adopted and no performance-qualified claim follows merely from exit zero.
4. Only after successful audit, reuse its products for the complete
   `merianTests` target, then run the actual critical-result validator on its
   result/tree, extracted with the existing `xcresulttool` procedure below.
   Those JSON files count against the 2 GiB evidence budget. Do not add a
   separate 96-test or six-smoke rerun: audit/full-unit coverage supersedes
   those repeats. After those pass, compile generic unsigned Release once. No
   archive, real-device installation or distribution.
5. Record final hashes, counts, environment, skipped/missing selectors,
   performance limitations, full evidence accounting and preserved primary
   state. Obtain exact independent and IC-1 result review. Update the acceptance
   ledger with narrowly scoped passes and concrete remaining blockers; stop.

Managed command forms (destination and environment label resolved from existing
local inventory before execution):

```sh
make ios-local-build ARGS='audit --destination "platform=iOS Simulator,id=<existing-UDID>" --environment-label "<actual host/model/runtime>"'
make ios-local-build ARGS='simulator -- test-without-building -configuration Debug -destination "platform=iOS Simulator,id=<same-UDID>" -parallel-testing-enabled NO -only-testing:merianTests'
make ios-local-build ARGS='device -- build -configuration Release -destination "generic/platform=iOS"'
```

For the full-unit bundle reported by the wrapper, use the same extraction and
validator as `.github/workflows/ios-build-and-test.yml`. Paths below identify
new files within this run's retained evidence root; no production data is read:

```sh
xcrun xcresulttool get test-results summary --path <full-unit.xcresult> > <full-unit-summary.json>
xcrun xcresulttool get test-results tests --path <full-unit.xcresult> > <full-unit-tree.json>
bash scripts/validate-ios-critical-test-results.sh <full-unit-summary.json> <full-unit-tree.json>
```

No new campaign, repair/retry loop or optional profiling follows a failure. The
existing audit can finish its internally scheduled phases after a test failure;
retain all of them and launch no subsequent full-unit/Release command. A source
closure defect requires a separate bounded fix proposal with exact ownership,
not an automatic expansion into unrelated pending edits. At window expiry stop
starting commands, drain the current managed invocation and report incomplete.

## What closes, and what remains

The
[alpha matrix](identification-history-alpha-readiness-2026-10-11.md#capability-and-evidence-matrix)
remains the product acceptance authority. This table is the current dependency
plan; none of its later rows is implementation authorization in ISQ-1.

| Gate / sequence                                                          | Required evidence and completion condition                                                                                                                                                                                                                                                                                                                            | Owner and disposition after ISQ-1                                                                                                                                                                                       |
| ------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Exact NCO/BI source qualification; local part of A19                     | Clean pinned tree, reproducible generated membership, passing managed audit correctness phases/full unit/critical validation/Release; no missing required tests; exact review and preservation receipts. Performance baseline limits explicit.                                                                                                                        | History primary; independent/IC-1 review. Only this bounded local source gap can close here.                                                                                                                            |
| P1 common allocation and installed original-photo acceptance; A9/A11/A17 | Native allocation authority or explicit product-wide exclusion covers every concurrent allocator; actual originals/AI/previews remain distinct, writer completion and reservations survive interruption/restart; physical max-cohort accounting and missing/oversize refusal preserve drafts. Real camera/PhotoKit/file protection requires user-run device evidence. | History primary prepares next specific owner/integration proposal; user owns device testing. Existing exclusive P1 test composition is not mixed-allocator evidence.                                                    |
| Audio/video preparation and immutable cohort; A5–A8/A10/A12              | Finish processing before freeze; versioned recipes; measured audio signal and identification-quality equivalence; exact retained video plus submitted frame/audio cohort; bounded restart recovery, storage and cleanup. Client frames remain submitted evidence, not proof of faithful video derivation.                                                             | History primary under separately reviewed preparation boundaries; IC-1 interface review. Existing fixtures do not close quality/hardware gates.                                                                         |
| Server admission, references, erasure and contention; A2–A6/A14/A15      | Freeze owned ordered byte identities/actual AI cohort, backend-only funding/dispatch/results; authoritative shared references and release/late-upload closure; both-order races, exact accepted replay and atomic completion/privacy; no reinvocation/refund after unknown execution.                                                                                 | History primary only within recorded IC-1 handoff. Broader initial-engine hardening remains separately owned. Prepare a bounded implementation/validation packet after prerequisite closure; no backend work in ISQ-1.  |
| Integrated native/history actions; A4–A13                                | Photo/audio/video initial→saved history→reanalysis→restart→selection/Undo and deletion races on exact source/context; missing media blocks, immutable descriptions preserved; historical text records and accepted recovery preserved, unadmitted no-media drafts held for explicit remediation.                                                                      | History primary; independent/IC-1 review. Real installed journeys remain user-owned and separately authorized.                                                                                                          |
| External/resource/CI and release handoff; A9–A12/A16–A21                 | Exact authorized target/artifact and hosted privacy/storage/recovery evidence; device evidence; final required CI; named Field Trip consumer closure or explicit scope decision.                                                                                                                                                                                      | User/operator authorizes external actions; primary assembles evidence. No new Supabase project is required by this proposal. Existing shared alpha project is a possible later named target, not present authorization. |
| Version deletion/export, then Identification/History/menu redesign       | Descendant-safe individual deletion; current/last-version refusal, shared-media retention, exact photo/audio/video source export and cleanup; then historical action routing/accessibility/menu and preserved alternatives layout.                                                                                                                                    | History primary after current-scope acceptance, following the approved follow-up RFC. Capture-tools visual refactor remains separately owned; it is not a prerequisite for functional qualification.                    |

The remaining product acceptance work cannot honestly fit in a single source
qualification run. After its result, the next recommendation is a narrowly
specified common-allocation/photo closure proposal, followed by preparation,
admission and integrated acceptance in dependency order. Do not invent extra
tests to bypass an external-only blocker or reinterpret a passing seam as a
completed product gate. Previously passing verifier evidence is reused within
its exact applicability; no new verifier/hosted campaign is justified here.

## Integration and publication boundary

ISQ-1 does not close all PR #116 gates. Supabase-backed Auth changes may select
the repository's backend candidate-validation workflow; local iOS success is not
a substitute for its disposable-database/contracts/Deno gates. Final CI,
unsigned archive requirements and exact publish approval remain open and need
the actual eventual PR head's evidence. Before any future merge recommendation,
review the exact workflow diff and main-branch deployment triggers again:
disabled feature flags do not prevent backend deployment. No CI dispatch, push,
merge, deployment, secret use, upload, hosted test, AWS action, device
installation or automation resumption is requested here.

Current media-required scope supersedes historical text-only roadmap wording.
All fresh initial/reanalysis requests need photo/audio/video; existing originals
suffice, and unavailable media requires replacement or refusal. Historical
nonproduction-only target wording does not require a separate Supabase project:
the user's later shared-alpha-project decision stands, with each operation still
requiring its own named authorization. No target is used in ISQ-1.

## Approval requested

Approve ISQ-1's four-hour local window, one clean managed worktree, locked
package downloads, existing-simulator audit/full-unit validation and unsigned
Release compilation, with 16 GiB additional working allocation and 2 GiB
retained evidence, preserving the 20 GiB floor. Exact independent/IC-1
concurrence is required before execution and on results. Stop at this checkpoint
or a genuine blocker; no runtime fixes or later acceptance work are implicitly
approved. Activation stays disabled, AWS unapproved, all existing product and
runtime limits unchanged.
