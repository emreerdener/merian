# BI-1 native integration result

October 15, 2026 local / October 16 UTC. All planned local validation gates
passed. The human-approved BI-1 window is 01:56:04–03:56:04 UTC with at most 1
GiB of additional retained evidence. Activation remains disabled, ordinary P1
access nil, AWS unapproved and existing limits unchanged.

## Scope and candidate

The
[approved proposal](client-prepared-media-bounded-integration-proposal-2026-10-15.md)
defines the boundary. BI-1 consolidates existing private Auth helpers without
moving security fences or increasing line caps. On the shared checkout,
SupabaseManager has 3,787 physical lines (3,788 under the architecture guard's
final-newline convention), below the unchanged 3,792 cap. Notification order and
separate timestamps remain unchanged. Anonymous-session matching delegates
synchronously to the existing published-session owner after retaining its
anonymous and UUID guards.

The replacement critical test exercises pending video hardware startup without
admission: interruption cancels, a late result is removed, and a newer draft
survives. Separate coverage preserves stop-and-complete for started recording.
The required selector and its positive and missing-selector negative fixtures
change together. BI-1 makes no production capture lifecycle change.

The selected checkpoint also includes the prior NCO-1 implementation and the
specifically approved baseline account/capture prerequisites. Generated project
membership comes from `make xcodegen`; the selected patch retains only approved
members and the existing schema lint configuration. Unrelated cached-session,
viewfinder, photo-library, map, presentation and backend changes remain outside
the selected checkpoint. The P1 Auth pre-drain seam remains included.

Execution candidate 02 describes 67 shared-checkout source/configuration paths:
manifest SHA-256
`56e4c29e7f44d4e6dabbff44816ba924e2ba43b1630d054c5dbe76ad20cce62e`. Independent
and IC-1 review concurred before execution. Candidate 01 was rejected before
execution because an architecture-test lookup omitted `private`; the corrected
lookup is the only candidate-02 change. Both receipts are retained.

## Validation provenance

Evidence root: `.artifacts/local-ios/bi1-20261015/`. Runtime results describe
the preserved shared checkout, not an isolated build of the selected commit. The
selected source is separately inventoried and dependency-reviewed; it has not
been compiled independently. No passing shared-checkout suite establishes clean
source qualification or closes P1/integrated acceptance.

| Check                                                               | Result                                                                                         |
| ------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Managed Debug simulator build-for-testing                           | Passed                                                                                         |
| Focused Auth, capture/account, P1 drain and bootstrap/handoff tests | 96 passed, zero failed or skipped                                                              |
| Complete iOS CI-tooling gate                                        | Passed, including required-selector positive/negative fixtures                                 |
| iOS project validation                                              | Passed                                                                                         |
| Complete unit target                                                | 5,945 passed, zero failed or skipped                                                           |
| Six critical UI smokes                                              | 6 passed, zero failed or skipped                                                               |
| Managed generic unsigned Release compilation                        | Passed; compile only, no installation or distribution                                          |
| Final selected diff and evidence review                             | Exact independent and IC-1 concurrence required before commit; receipts in `final-review.json` |

Previous NCO failed aggregates remain retained in the
[NCO-1 result](client-prepared-media-nco1-local-result-2026-10-15.md). No
unchanged completed suite is relabeled as a new run. Final evidence accounting
includes new XCResults and retained simulator fixtures; reusable managed build
caches are excluded. The 20 GiB disk floor and fixed deadline remain enforced.

## Remaining acceptance

This is a bounded inactive integration checkpoint. P1 installed/mixed-allocator
acceptance, audio/video preparation, server admission, integrated history,
individual deletion/source export and redesign remain separate open gates.
Missing media still blocks fresh submission. Unknown AI execution permits only
original-operation recovery and reconciliation, never another invocation or
refund. No hosted action, push, merge, deployment, device installation or
distribution is authorized by this result.

XCResult aggregate counts above remain separate from its per-device field, which
reports 9,390 passed and zero failed or skipped. Both raw forms are retained in
`candidate-02-full-unit-summary.json`. The actual complete-unit result/tree also
passed `validate-ios-critical-test-results.sh`.

## Selected checkpoint and preservation

Initial independent and IC-1 source-selection review concurred on all 59
selected source/configuration/project files, including exact patch
reconstruction from `fbf1145d038f6ba167e0f08384ce8cb60978a737`. The
selected-source manifest SHA is
`d5a251320fb133e61812ca9cae3bf6f7e4b28844ed13690deca618d10d463be4`; its patch
SHA is `017168ddacd286d32dcc9fdd9546cb987d19007dd93b02fcb34c6f9e8ddbedaf`. Two
retained README passages were corrected after independent review to describe
pending video hardware startup and late recording results, instead of
nonexistent pre-recording admission. Re-review found no remaining mismatch.

The final combined source/document patch, final review receipts, preservation
inventory and local commit identity are retained under the evidence root. Local
commit requires exact independent and IC-1 concurrence on that combined patch.
The primary stages only this patch; excluded working-tree hunks stay intact. No
second checkout or source-isolation workaround was used.

All five build/test result bundles, logs, raw count forms and new simulator
fixtures are retained. Retained evidence remains below the 1 GiB allowance, with
more than 43 GiB free at validation completion. The canonical total, including
final review artifacts, is recorded in `evidence-budget.json`. BI-1 automatic
continuation ends with this checkpoint; broader work is not automatically
resumed.

## Final staged-diff audit

The first staged whitespace check, which also covers newly added files, found
one inherited whitespace-only line in the frozen V58 snapshot and an extra
terminal blank line in the new photo-preparation test file. The failed check is
retained in `staged-whitespace-failure.log`; the earlier unstaged check did not
cover those new files. No commit was made at that point.

The V58 snapshot remains byte-for-byte unchanged at SHA-256
`5acc8cba9f1ffa6b6a64c8695d5be8282899372bcdad8a9e9294780e8e0fe855`. Its line 107
blank-line spaces are retained to preserve the retired snapshot. The final
staged audit permits only that exact inherited diagnostic and checks all other
selected files normally. This changes no schema declaration, runtime limit,
architecture threshold or repository validator.

Candidate 03 removes exactly one terminal newline from
`PhotoOriginalPreparationTests.swift`; its token sequence is unchanged. Manifest
SHA-256: `7c5a8a688880cd5406817dc266cd935c986ca3df5096c6ebd1a066c49a691d63`. All
runtime results above remain evidence for candidate 02. Reuse for this
formatting-only difference and the narrow frozen-file diagnostic require exact
independent and IC-1 concurrence before commit; no unchanged runtime suite is
rerun. `whitespace-correction.json` and the final combined manifest preserve the
before/after identities and the reviewed final selection.
