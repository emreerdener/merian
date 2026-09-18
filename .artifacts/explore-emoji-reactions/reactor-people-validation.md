# Detail reactor people validation — 2026-09-18

Implemented a detail-only unique-person reaction summary and medium/large
Reactions sheet. Each row shows public identity and all canonical emoji, with
likes represented as ❤️. The new authenticated read and service-only RPC filter
post/actor visibility before totals, previews, and 32-person UUID pagination. No
deployment or distribution occurred.

## Passed

- Native app compilation through `make ios-local-build`; 48 focused tests passed
  (29 XCTest plus 19 Swift Testing), followed by 11 route/retry tests. All seven
  new people-state tests passed. Results:
  `.artifacts/local-ios/86d56eeb72004cfcb98221b9559bcec4.xcresult` and
  `.artifacts/local-ios/c0aa6ed87cfb4cf7a5da181d9ec1792d.xcresult`.
- Fresh disposable migration replay, full database catalog suite (50 files, 341
  assertions, including privileged routine guards), and database lint.
- Full Edge suite: 1,983 passed. The four focused route tests also passed after
  adding three adapter tests for trusted identity, public 403 mapping, and safe
  internal-error handling.
- Migration contracts: 339 passed. DTO contracts: 20 passed. Complete Supabase
  tooling gate, all Edge entrypoint type checks, and Deno lint passed.
- XcodeGen/project validation, scoped SwiftLint, Markdown and exact backend
  formatting, local reaction documentation links, and diff whitespace passed.

The tooling gate's read allowlist now includes the maintained `resources`
documentation; the configured Function inventory includes the new endpoint. The
independent read-only review's adapter-test and documentation-inventory findings
were addressed. The disposable database and fixtures were removed. Unrelated
workspace edits and the other task's runtime benchmark were preserved.

## Remaining runtime checks

Physical-device layout, gestures, VoiceOver, Dynamic Type, haptic feel, and
playback pause/resume are not verified by these automated results. Hosted API
and deployed-app behavior remain unverified. Apply the additive migration and
release the new Edge route before distributing the native client, through the
existing separately authorized deployment procedure.
