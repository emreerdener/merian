# Explore emoji reactions validation

## Scope

Shared Unicode 17.0 picker and action row for observation posts, comments and
replies; post/comment state reconciliation; paginated summaries; capability-safe
notifications and opt-in pushes. Share remains fixed in feed and detail. Backend
deployment and app distribution have not been performed.

## Verified

- Full disposable database migration replay, isolated from the existing local
  project.
- Complete Edge/database suite: 1,977 passing tests.
- Additional focused Unicode/catalog parity, reaction concurrency, visibility,
  aggregation, legacy unread count, removal and ghost-merge checks: 10 passing
  tests.
- Complete SQL security catalogs: 49 files, 314 passing assertions.
- Migration contracts: 54 files, 338 tests.
- DTO contract validation: 20 tests.
- Complete Supabase tooling suite.
- Recursive deploy-config type checks: 98 Edge entrypoints.
- Database lint: no errors or warnings.
- Security and performance advisors: no errors; existing advisory warnings
  remain.
- Deno lint and exact recursive formatting gate.
- Unicode source generator drift check.
- XcodeGen, iOS project/resource validation, changed-Markdown formatting and
  diff whitespace check.
- Independent read-only review; reported reaction state, picker and hashtag gaps
  addressed.

## iOS validation

App and test targets compiled through `make ios-local-build`. The focused run
passed on iOS 27 with 34 XCTest tests and 49 Swift Testing test functions
(including their parameterized cases). It covers reaction state, account
changes, refresh fencing, serialized mutations, idempotent heart selection,
rollback, notification reply copies, request payloads, pagination, routing, and
transport. The retained `ios-tests-summary.json` contains Xcode's full test-case
totals.

The iOS 26.5 test host stalled in location-service initialization before tests
started. That task-owned run was stopped and the compiled test bundle passed on
iOS 27. Other active tasks also used this checkout's build cache during
validation. Two pre-existing test macro compilation issues were addressed by
preserving the same boolean assertions and moving throwing fixture reads outside
macros.

Manual device checks for VoiceOver, Dynamic Type, sheet gestures, Share hit
testing, and media playback transitions have not been completed. No hosted
mutation, push delivery, deployment, or distribution was performed. The isolated
Supabase validation containers and fixture data were removed after validation.
