# ISQ-1 result: stopped at tool selection preflight

October 15 local / October 16, 2026 UTC. The human approved the
[ISQ-1 packet](client-prepared-media-isolated-qualification-proposal-2026-10-15.md)
for 03:07:08–07:07:08 UTC, with 16 GiB additional working allocation and 2 GiB
retained evidence. **The run stopped at its first qualification prerequisite.**
No source-isolation pass, P1 acceptance or alpha completion is claimed.
Activation disabled, ordinary P1 access nil, AWS unapproved and all existing
product/runtime limits unchanged. Automatic continuation remains stopped.

## Exact candidate and pre-execution review

The new managed worktree is
`/Users/emreerdener/.codex/worktrees/isq1-qualification/merian`, pinned to
commit `ca5a30f76e48acb157ed8d013186d0b3ca79fe6f`, tree
`d0ae0ce25a7016aef9dfbb73b0a5e080e51ca00f`. It was clean before qualification
and remains clean afterward. No baseline files, credentials or build caches were
copied from the primary checkout.

Independent reviewer `gac_path_trace` and IC-1 concurred before execution with
manifest SHA-256
`8aade2e74fa8dc8785da9313dea321ddc157ba3c454fba9febb081d52e757e7e`. IC-1 turn:
`01a142af-b362-75b1-93fc-f1dceea99a91`. The manifest pins the project, source
manifest, package lock, managed runner, 43 acceptance selectors, 27 UI selectors
and ten performance selectors. No selector or runtime phase ran. Performance
remained report-only in the reviewed scope.

The execution inventory protects 106 primary-checkout paths: the 102 unrelated
baseline paths plus four ISQ-1 proposal/status documents. Every one was
unchanged by worktree construction and the failed qualification attempt. Later
updates to the owned status documents report this result; unrelated edits remain
intact. The package lock is tracked under the lowercase `merian.xcodeproj` Git
path; an uppercase-path lookup during review was not evidence of an untracked
lock.

## Demonstrated blocker

`make xcodegen` in the clean worktree selected `/usr/local/bin/xcodegen`,
version **2.45.2**. `project.yml` requires **2.45.4**. XcodeGen rejected the
specification before generation, and Make reported failure. The earlier tool
inventory had been executed from the primary checkout, where command lookup
selected `/opt/homebrew/bin/xcodegen`, version **2.45.4**. That inventory was
therefore not sufficient to establish the clean worktree's tool selection.
Read-only path/version comparisons confirm this discrepancy; its underlying
shell environment configuration was not changed or broadly investigated.

The committed project remains SHA-256
`437a4131adea049e7718e75bdd4ae55b9651d7e5f38ba05c7fab0084d9801e12` and the
retained generated-project diff is empty. No source or project correction was
made. The command wrapper also attempted to assign the read-only zsh variable
`status` after Make failed; that receipt error did not cause the XcodeGen
failure and did not launch another generation attempt. Both facts are preserved
in the result record rather than relabeling the failed invocation as passing.

The proposal explicitly stops after a prerequisite failure and excludes repair
or retry loops. Accordingly, project/migration/CI-tooling/source-membership
gates, locked dependency downloads, managed audit, full-unit tests and unsigned
Release compilation were **not run**. There was no build to cancel or duplicate.

## Evidence and disposition

Evidence is retained in `.artifacts/local-ios/isq1-20261015/`, including the
window, primary identities, execution manifest and reviews, generator log, empty
project diff, tool-selection comparison and `result.json`. At stop the new
worktree occupied approximately **110.2 MiB**, preliminary evidence was under
**0.1 MiB**, and free disk space was approximately **43.5 GiB**. Final
accounting includes this result and review receipts; no XCResults, dependency
cache or new simulator fixture was produced. Keep the worktree and all failed
evidence for the next reviewed attempt; no cleanup of older evidence or user
state occurred.

The isolated-source gate remains open. BI-1's prior passing shared-checkout
results remain historical evidence with their original applicability. Common
allocation/photo device acceptance, audio/video preparation, server admission,
integrated history, external/CI gates and later deletion/export/redesign remain
open in the approved dependency order. No external operation, push, merge,
deployment, device installation, hosted test, AWS action or limit change
occurred.

## Recommended next bounded correction

Use the already installed **2.45.4** executable by explicitly selecting
`/opt/homebrew/bin` ahead of `/usr/local/bin` for the qualification process,
then inventory every prerequisite from the actual clean worktree before
regenerating. This needs no tool installation or product-source change. Preserve
the pinned source/package lock, managed runner and all approved resource limits.
Update the execution manifest with the effective executable paths/versions and
obtain exact independent/IC-1 concurrence before any retry.

This recommendation is not executed by this stopped run. A resumed window should
authorize this environment-selection correction and one new generation attempt,
followed only by the original conditional qualification sequence if it passes.
Do not widen the work into source repairs, repeated diagnostic campaigns or
product activation.
