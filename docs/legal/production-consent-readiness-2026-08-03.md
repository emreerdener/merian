# Production Consent Readiness — 2026-08-03

## Status

**Blocked.** The repository contains the intended final onboarding surface,
versioned consent evidence, server-side Gemini admission guard, optional
analytics control, and legal copy. The two P1 consent-lifecycle defects from the
second-pass review, the adjacent stale-sync/unit-fixture defects, and the three
account-restoration lifecycle findings are complete in source. Hosted exact-SHA
execution and the external operator controls below must still close before this
candidate is nominated for production.

For internal test builds, the App Store, billing/DPA, and counsel approvals are
explicitly deferred. That deferral permits continued engineering and internal
beta validation; it does not authorize production submission or public release.

The shorter disclosure, analytics label, and Analytics → Age → Terms ordering
currently in the app are an explicit product-owner choice. They now carry fresh
Gemini and analytics disclosure versions so immutable receipts do not mix
different text under one version. Counsel approval of that retained copy remains
an external production requirement.

This record is the canonical status source for the adult, Terms, Google Gemini,
and PostHog consent release. Architecture documents describe the required end
state; they do not override the release hold recorded here.

## Required Product Contract

The onboarding order remains Welcome → Camera → Location → Powered by AI. The
final screen must show this disclosure before its controls:

> Naturebook sends observation data to Google Gemini for AI-powered
> identification.

It presents three initially-off, left-aligned switches:

1. **Optional:** “Share usage and diagnostics to help improve Naturebook.”
2. **Required:** “I confirm I am 18 or older.”
3. **Required:** “I accept the terms and allow this data sharing.” The word
   “terms” links to the full Terms of Service.

Only the two required switches gate **Start scanning**. Withholding or withdrawing
analytics permission must never block core functionality. Existing beta users
without current required evidence return directly to Powered by AI without
repeating Camera or Location.

## Evidence and Enforcement Contract

- Adult eligibility uses self-attestation on every supported iOS version. Do
  not collect a birth date or exact age.
- Current adult policy and Terms versions are `2026-08-03`; the current Google
  Gemini disclosure version is `2026-08-04.1`, and the current analytics
  disclosure version is `2026-08-04`.
- Adult, Terms, Gemini, and PostHog actions use immutable, versioned evidence
  containing the exact displayed text, device action time, platform, app
  version/build, and a server-controlled timestamp.
- Absence of a current PostHog grant means analytics is off.
- Local required evidence closes the UI gate, but Gemini remains unauthorized
  until current adult, Terms, and Gemini evidence exists on the active Supabase
  account and the service-only quota boundary accepts it.
- Public consent tables require explicit privileges and owner-only RLS. This is
  deliberate rather than relying on changing Data API defaults; see the
  [Supabase Data API exposure change](https://supabase.com/changelog/45329-breaking-change-tables-not-exposed-to-data-and-graphql-api-automatically).
- Reauthentication, account change, withdrawal, offline retry, and
  ghost-to-existing-account merging must preserve the latest user action and
  must never infer or fabricate consent.

## Primary Policy Basis

Checked against the official sources on August 3, 2026:

- [Apple App Review Guideline 5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/)
  requires clear disclosure of where personal data is shared with third
  parties—including third-party AI—and explicit permission before sharing.
- The [Gemini API Additional Terms](https://ai.google.dev/gemini-api/terms)
  require API users to be 18+ and prohibit API clients directed toward or
  likely accessed by people under 18.
- The same [Gemini paid-services terms](https://ai.google.dev/gemini-api/terms)
  classify Gemini API use as paid only through a Cloud project with active
  billing and state that paid prompts/responses are processed under Google's
  Data Processing Addendum rather than used to improve Google products.

This repository record translates those platform/provider requirements into
engineering release controls; it is not a legal opinion.

## Internal Release Blockers

| ID | Priority | Finding | Required exit evidence |
| --- | --- | --- | --- |
| `CONSENT-001` | P1 | **Complete in source — 2026-08-04.** A closed-by-default, host-scoped `URLProtocol` transport gate is installed on PostHog's dedicated session. Every setup receives a unique transport ID, so opening a new grant cannot admit a delayed old-session request. Withdrawal disables app capture and closes the gate before preserving `reset → optOut → close`; permission generations reject stale overlapping setup/activation work. SDK calls use an injectable adapter. | Regression coverage verifies shutdown order, gate state at reset, no downstream connection while closed, old-session denial after a new transport opens, configure/withdraw and configure/account-switch races, repeated withdrawal, and subsequent opt-in/identity. Hosted exact-SHA execution remains rollout evidence. |
| `CONSENT-002` | P1 | **Complete in source — 2026-08-04.** Confirmed server handoff is followed by one verified local-ledger rebind across adult, Terms, Gemini, and analytics evidence, permanent-account synchronization/refetch, and only then throwing verified queue removal. Throwing Keychain reads preserve failure status; unreadable evidence is retained and keeps analytics fail-closed. Durable pending handoffs suppress analytics across restart. | Regression coverage preserves immutable fields, distinguishes synchronized from pending rows, proves idempotent server → local → removal sequencing/failure retention, and covers permanent grant → offline ghost revocation → merge/restart/second-device state. Hosted exact-SHA execution remains rollout evidence. |
| `CONSENT-003` | P1 | **Complete in source — 2026-08-04.** The Terms-link test now declares `throws`. | Hosted iOS run 183 at `1559e3f646952a10752526560684d9afbf4bb78b` compiled and passed 1,333 unit tests. The current candidate SHA must repeat that result. |
| `CONSENT-004` | P2 | **Complete in source — 2026-08-04.** Consent synchronization now invalidates stale work by generation and checks cancellation plus the SDK's synchronous active session after every network await and immediately before mutation/persistence. | Parser, strict lint, whole-module frontend type-check, and complete test-source type-check passed locally. A hosted deterministic account-switch runtime regression remains candidate evidence. |
| `CONSENT-005` | P2 | **Complete in source — 2026-08-04.** Every account synchronization now activates the target ledger, keeps analytics closed, pushes all target-owned pending adult, Terms, Gemini, and analytics rows, and only then refetches, merges, and applies authoritative state. An empty remote account still becomes active. | Unit coverage proves activation is idempotent and preserves pending/historical evidence. A source-order contract locks activate → push → fetch → merge and fail-closed activation. Hosted offline revoke → switch away → switch back execution remains candidate evidence. |
| `CONSENT-006` | P2 | **Complete in source — 2026-08-04.** Analytics-consent Realtime tracks channel owner and confirmed subscribed owner independently of `currentSessionUserId`, generation-fences stale listeners, and assigns an explicit account-owned bounded retry. Session observation and foreground/session adoption both ensure or repair the channel. | Unit coverage locks bounded retry timing; source contracts verify unconditional session/foreground ensure, independent owner fields, generation fencing, and retry ownership. Hosted cross-device grant/withdrawal and reconnect execution remains candidate evidence. |
| `CONSENT-007` | P2 | **Complete in source — 2026-08-04.** Every OAuth path that can replace an account synchronously suppresses the analytics facade, closes consent Realtime and invalidates stale synchronization before asking Supabase Auth to install the target session. Success and failure reconcile the SDK's actual current session; transition generations prevent an older overlapping login from reopening capture or replacing observable account state. | Unit coverage proves suspend → install → reconcile ordering, failure reconciliation, and newest-generation-only reopening. A source contract locks the production helper to the OAuth replacement path. Hosted account-replacement execution remains candidate evidence. |
| `CONSENT-008` | P2 | **Complete in source — 2026-08-04.** The foreground replay test now injects and restores an isolated granted `ConsentManager`; a closed-gate negative test is retained. | Hosted iOS run 183 included this test in the 1,333-test passing unit gate. The current candidate SHA must repeat that result. |
| `CONSENT-009` | P1 release gate | **Complete in source — 2026-08-04.** The retained internal-testing copy now uses fresh Gemini `2026-08-04.1` and analytics `2026-08-04` disclosure versions. A forward-only migration makes the newest Gemini action authoritative, preserves bounded prior-beta compatibility, and adds strict `2026-08-04` cutover without rewriting historical receipts. | Migration/source contracts and iOS tests must pass on the exact candidate SHA; TestFlight must prove accounts with only earlier versions return to the final consent screen and write exact new-version local/cloud evidence. |

`CONSENT-001` through `CONSENT-009` are closed in source. The current candidate
still requires exact-SHA compiled/runtime evidence; “complete in source” is not
itself a production approval.

## Verification Snapshot

The 2026-08-03 second pass produced this local evidence:

| Check | Result |
| --- | --- |
| Unsigned generic iOS Simulator build | Passed: `** BUILD SUCCEEDED **` |
| SwiftLint | Passed: 808 files, zero violations |
| Swift parser check for changed consent/analytics/lifecycle views | Passed |
| Supabase migration source contracts | Passed: 246 tests |
| Focused legal-consent, PostHog, paid-Gemini, and quota tests | Passed: 18 tests |
| Public web tests | Passed: 60 tests |
| iOS CI tooling contracts and project source membership | Passed |
| Complete iOS unit-test target | **Failed during compilation** on `CONSENT-003`; no execution evidence is valid |
| Disposable PostgreSQL catalog/RLS/pgTAP replay | **Not run locally**: Docker was unavailable and installed Supabase CLI 2.101.0 did not match the reviewed 2.109.1 pin |

Static migration tests confirm the intended append-only ACL/RLS/publication
shape, but they do not replace a fresh disposable database replay with the
exact CLI or the hosted complete iOS result.

The 2026-08-04 remediation pass additionally produced this local evidence:

| Check | Result |
| --- | --- |
| Whole-app direct Xcode 26.6 frontend type-check against cached locked iOS dependencies | Passed with zero diagnostics |
| Optimized whole-module Release/device frontend type-check against PostHog 3.69.0-matching locked modules | Passed with zero diagnostics |
| Complete 85-source iOS unit-test frontend type-check against the freshly emitted app module | Passed; five pre-existing constant-`#expect(true)` notes only |
| Exact final PostHog and ghost-handoff regression source frontend type-check | Passed with zero diagnostics |
| Swift parser and `git diff --check` for the five changed implementation/test files | Passed |
| PostHog transport/order and ghost-ledger/handoff regression sources | Compiled; hosted runtime execution is still required because this desktop sandbox cannot connect to CoreSimulator |
| Hosted iOS run 183 at `1559e3f646952a10752526560684d9afbf4bb78b` | Unit gate passed: 1,333 tests; validation Release archive passed; queued-audio UI smoke failed because the Scans tab button did not appear |

The 2026-08-04 double-check on the final local working tree added this evidence:

| Check | Result |
| --- | --- |
| Focused PostHog, Keychain, and ghost-handoff simulator regressions | Passed; withdrawal order/gate behavior, per-session transport isolation, re-opt-in, ledger rebinding, and failure sequencing executed |
| Complete iOS unit-test target | Passed: 1,344 tests, zero failures |
| Deterministic queued-audio completion UI smoke | Passed locally: one test, zero failures |
| Unsigned generic optimized Release build | Passed with zero build diagnostics |
| Validation Release archive | Correctly refused the dirty review checkout; the unmodified preflight requires a clean exact SHA, so CI archive evidence remains required |
| Swift parser, strict SwiftLint, and `git diff --check` for the reviewed Swift files | Passed: zero diagnostics and zero lint violations |
| Supabase formatting and documentation contracts | Passed: 713 files formatted; 17 tests, zero failures |

The final 2026-08-04 account-lifecycle pass added this local evidence:

| Check | Result |
| --- | --- |
| Complete 408-source iOS app-module frontend type-check against cached locked dependencies | Passed with zero diagnostics in the project's Swift 5 language mode |
| Both changed XCTest sources type-checked against the freshly emitted reviewed app module | Passed with zero diagnostics |
| Swift parser, strict SwiftLint, and `git diff --check` for changed implementation/test sources | Passed with zero diagnostics and zero lint violations |
| Ghost merge, target flush, Realtime ownership/retry, and OAuth replacement source contracts | Passed: 6 tests, zero failures |
| Complete Supabase Deno suite and formatting gate | Passed: 1,535 tests, zero failures, one ignored; 713 files formatted |
| Full simulator unit/UI execution | Pending hosted exact-SHA workflow; this desktop sandbox cannot connect to CoreSimulator |

The final 2026-08-04 documentation reconciliation added this evidence:

| Check | Result |
| --- | --- |
| Public web TypeScript gate | Passed: `tsc --noEmit` |
| Public web unit and source-contract suite | Passed: 60 tests, zero failures |
| Supabase maintained-documentation contracts | Passed: 17 tests, including local-link and public Privacy control assertions |
| Supabase formatting gate | Passed: 713 files formatted |
| Stale consent-status search and `git diff --check` | Passed with no findings |

## Required Remediation and Rollout Order

1. Run the complete hosted **iOS Build and Test** workflow on the exact candidate
   SHA. Require a compiled and executed complete `merianTests` target, the
   focused UI smoke, and the unsigned Release validation archive.
2. With Docker running and Supabase CLI 2.109.1, replay every migration into a
   fresh disposable catalog; run all pgTAP fixtures, strict lint, and advisors.
3. Apply only the additive consent schema and deploy consent-gated Edge code.
   Keep `internal.ai_consent_rollout_config.enforcement_mode` at
   `legacy_compatible`.
4. Distribute the corrected replacement TestFlight build. Verify all switch
   combinations, inline Terms navigation, VoiceOver, Dynamic Type, smallest
   supported screens, offline withdrawal, account switching, foreground
   reconciliation, Realtime propagation, and ghost-profile merging.
5. Expire every older TestFlight build that cannot produce the current consent
   bundle.
6. Only then run the owner-only forward strict-cutover script and verify legacy,
   partial, revoked, and current-complete accounts against the deployed server.

Never backfill age, Terms, Gemini, or analytics evidence. Never relax the
provider guard to recover availability.

## External Production Blockers

Repository correctness does not close these operator-owned requirements:

- Configure and archive the reviewed 18+ App Store Connect age-rating override;
  verify product pages, campaigns, and distribution are not directed toward
  minors.
- A Google Cloud owner must confirm active paid billing for the project behind
  `GEMINI_PAID_API_KEY`, confirm the applicable DPA is in force, archive dated
  evidence in the restricted release record, rotate the key after confirmation,
  synchronize the new secret, smoke-test it, and revoke the superseded key.
- Counsel must approve the final Terms, Privacy Policy, consent presentation,
  App Store privacy answers, operator identity, and regional release scope.

Production remains blocked until hosted exact-SHA validation and every external
production control are closed with exact-version, exact-build evidence. Those
operator controls remain deferred for internal-only test builds.
