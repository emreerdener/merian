# Explore emoji reactions: follow-up review

## Fixes

- Detail responses now update the shared reaction store with request, account,
  and mutation-revision checks.
- Author, hashtag, and reply loads preserve newer reaction selections. Mutation
  settlement also invalidates reads started during that mutation.
- Removed posts invalidate queued emoji/heart writes and stale feed pages.
- Post refreshes and lightweight Map hydration serialize with reaction writes.
- Notification reply reaction pagination shares the mutation queue.
- The detail picker uses the existing presentation-conflict guard.
- Reaction overflow uses explicit More/retry; Dynamic Type scales strip height.
  Pagination no longer jumps back to a previously selected emoji.
- Legacy unread-count RPC execution is restricted to the service role, matching
  both capability paths. Added actual caller probes for six notification RPCs.
- Documented post-reaction notification routing and immutable catalog upgrades.

## Validation

- First follow-up native run: 97 tests passed (48 XCTest, 49 Swift Testing),
  using `make ios-local-build` on the existing iOS 27 simulator.
- Final native run with Map hydration and Dynamic Type changes: 101 tests passed
  (50 XCTest and 51 Swift Testing), including all 20 reaction-state tests.
  Result: `.artifacts/local-ios/5ea644519d2b44b2b8e26a0cec324de4.xcresult`;
  machine-readable summary: `review-ios-tests-summary.json`. The preceding run
  exposed a refresh-test fixture that also performed Map hydration; the fixture
  now seeds an already-loaded post and the full focused rerun passed.
- Full backend suite: 1,978 passed, zero failures.
- Full database catalog suite: 49 files, 335 assertions passed.
- Fresh disposable migration replay, 338 migration-contract tests, 20 DTO tests,
  complete Supabase tooling, and database lint passed.
- Catalog generation drift check, XcodeGen/project validation, scoped SwiftLint
  (warnings only), changed-Markdown formatting, exact Edge formatting, and
  diff-whitespace checks passed.

Manual device/VoiceOver/gesture/Share-hit-area and media-lifecycle checks remain
unverified. No deployment or distribution occurred. Disposable database
containers and fixture data were removed. Unrelated workspace edits were
preserved.
