# Runtime audit closure

Validation is in progress. Do not interpret this draft as a passing full-target
claim. Final result exports and source identities will determine the verdict.

## Implementation and independent review

The three previously confirmed architecture failures were corrected without
raising size ceilings or weakening owner assertions:

- Added the existing reaction endpoint and reaction model files to their exact
  ownership inventories; added representative reaction DTO declarations.
- Reconciled the replay-policy inventory for the two existing read-only reaction
  endpoints after the focused run exposed that additional drift.
- Moved the unpublish confirmation renderer beside the detail sheet renderer.
  The route host retains selected-post state and its unshare action. Text,
  cancellation, destructive role and visibility binding are unchanged. The host
  is now 597 lines, down from 610.

A scoped Auth lease dependency now exposes the existing live begin/current/
finish operations to terminal routing. The result processor accepts its existing
finalization service and a publication callback whose live default is the moved,
unchanged publication implementation. Production URLSession callers keep the
live defaults. No process-wide Auth override, public payload or persisted schema
was added.

The new `CaptureTerminalAcceptanceTests` stages JPEG media in the real Capture
workspace, submits it into a private SQLite queue, supplies a response file to
the real terminal router, and suspends decoding before persistence. Duplicate
result/error callbacks cannot release the owner's lease. The real Auth runtime
drain holds sign-out until completion; real response preparation, persistence,
queue deletion and saved media precede Insight binding. Notification/milestone
publication is a counter, while the SDK sign-out operation is an injected flag.

`runtime_contract_review` found no production correctness issue in the lease
ownership/dependency extraction or confirmation renderer. Its replay-inventory
finding was fixed and the failing suite rerun successfully. The final acceptance
case passed. Camera hardware, OS URLSession delegate/tracker delivery, live SDK
Auth mutation, engine-recovery publication, actual notifications/milestones and
OS process death remain outside this composition.

## Focused verification

- `make xcodegen validate-ios-project`: passed using the pinned XcodeGen 2.45.4.
- Strict SwiftLint on affected production/test files: passed.
- `make test-ios-ci-tooling`: passed.
- Changed Markdown was formatted with `deno fmt`.
- First focused compilation found a Boolean quota fixture assignment error;
  second found a throwing call inside `#require`. Both were fixed; diagnostic
  logs are retained.
- The next focused run executed 38 tests across seven suites: the new composed
  acceptance case and all three original architecture failures passed; the
  replay-policy inventory failed. After its correction, both the Core Network
  suite and composed acceptance test passed: 14 tests, zero failures.
- An extra requested selector initially used the filename rather than its Swift
  suite name (`ExplorePostFieldChatPresentationPolicyTests` versus
  `ExplorePostFieldChatPolicyTests`); no focused pass is claimed for that
  missing selector. The full target includes the actual suite.

## Provenance

`before/` preserves pre-edit versions of the changed owners, including
concurrent work already present. `owned.patch` is the incremental change from
those bytes; `reviewed-sources/` and `owned-hashes.json` retain the reviewed
files. The new test and runtime selector are explicitly in `owned-files.json`.
Generated Xcode project output was regenerated, not edited manually.
`production-inventory.json` records the line delta: five existing production
owners changed, net +49 lines, zero production files added or removed; the
largest affected owner is 597 lines.

The shared checkout contains unrelated concurrent changes. The final managed
audit and full unit run retain before/after source identities. Historical
snapshots under `runtime-audit-next` and `runtime-audit-verification` remain
unchanged and do not establish this newer source state.
