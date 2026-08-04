# Production Consent Readiness — 2026-08-03

## Status

**Blocked.** The repository contains the intended final onboarding surface,
versioned consent evidence, server-side Gemini admission guard, optional
analytics control, and legal copy. A second-pass review found internal defects
that must be corrected and verified before this candidate is distributed to
TestFlight or nominated for production.

This record is the canonical status source for the adult, Terms, Google Gemini,
and PostHog consent release. Architecture documents describe the required end
state; they do not override the release hold recorded here.

## Required Product Contract

The onboarding order remains Welcome → Camera → Location → Powered by AI. The
final screen must show this disclosure before its controls:

> Naturebook sends your scan data to Google Gemini, a third-party AI service,
> for identification.

It presents three initially-off, left-aligned switches:

1. **Required:** “I confirm I am 18 or older.”
2. **Required:** “I accept the terms and allow this data sharing.” The word
   “terms” links to the full Terms of Service.
3. **Optional:** “Share app usage and diagnostics with PostHog to help improve
   Naturebook. Optional.”

Only the first two switches gate **Start scanning**. Withholding or withdrawing
analytics permission must never block core functionality. Existing beta users
without current required evidence return directly to Powered by AI without
repeating Camera or Location.

## Evidence and Enforcement Contract

- Adult eligibility uses self-attestation on every supported iOS version. Do
  not collect a birth date or exact age.
- Current adult policy and Terms versions are `2026-08-03`; the current Google
  Gemini disclosure version is `2026-08-03.1`.
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
| `CONSENT-001` | P1 | `PostHogManager.setConsentGranted(false, ...)` calls PostHog `reset()` before `optOut()`. In resolved PostHog iOS 3.69.0, `reset()` reloads feature flags and can start a PostHog request during withdrawal. | Remove the request-producing reset path, retain immediate identity clearing/opt-out/SDK closure, and prove with an injected network/SDK test that withdrawal starts no PostHog request. |
| `CONSENT-002` | P1 | A provider-bound ghost merge reparents synchronized server rows but does not reparent unsynced records in the local consent ledger. An offline PostHog revocation owned by the ghost can be orphaned while a prior server grant follows the permanent account. | After a confirmed handoff, atomically move local evidence from ghost UUID to target UUID, leave unsynced actions pending for the target, mark already-synchronized rows consistently with server reparenting, push pending rows, refetch, and test grant/revoke permutations. |
| `CONSENT-003` | P1 | The complete iOS unit-test target does not compile: `testReadyTermsLinkTargetsTheFullTermsOfService()` uses throwing `XCTUnwrap` without declaring `throws` or handling the error. | Correct the test and retain a green complete `merianTests` target on the hosted exact-SHA iOS gate. |
| `CONSENT-004` | P2 | Consent synchronization checks the active session only before awaited network work. A cancelled old-account fetch can still reach `merge(...)` if cancellation is not propagated promptly. | Check cancellation and session identity after each await and immediately before every merge/persist/SDK transition; add a deterministic account-switch race test. |
| `CONSENT-005` | P2 | When the persisted active ledger belongs to another account, synchronization fetches and merges the target but does not first flush pending local rows already owned by that target. Account-wide revocation can remain delayed until a later synchronization. | Activate and flush target-owned pending rows during account restoration, refetch authoritative state, and test offline revoke → switch away → switch back. |
| `CONSENT-006` | P2 | Realtime startup is keyed to a change in `currentSessionUserId`. Another synchronization path can assign that ID before the auth observer, causing the observer to skip channel startup; failed subscriptions also lack an explicit retry owner. | Track the subscribed account independently, ensure one healthy owner-scoped channel after session adoption, retry after failure/foreground, and test cross-device grant and withdrawal. |
| `CONSENT-007` | P2 | OAuth replacement relies on the asynchronous auth-state observer to shut down the prior account’s analytics rather than suspending capture before installing a different target session. | Suspend the analytics facade and SDK before a true account replacement, reconcile the actual session on failure, and test that no old-identity event crosses the transition. |
| `CONSENT-008` | P2 | `AppLifecycleManagerTests.testHandleActivePhasePlaysBackStagedScans()` marks onboarding complete but does not provide current required consent. The production foreground path now returns before replay on a clean runner. | Inject an isolated granted `ConsentManager`, restore it after the test, and retain foreground replay plus closed-gate negative tests. |

All eight items are release blockers. P2 denotes lower exploitability or a more
specific race, not permission to defer the correction beyond production.

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

## Required Remediation and Rollout Order

1. Correct `CONSENT-001` through `CONSENT-008` and add deterministic regression
   coverage for every scenario.
2. Run the complete hosted **iOS Build and Test** workflow on the exact candidate
   SHA. Require a compiled and executed complete `merianTests` target, the
   focused UI smoke, and the unsigned Release validation archive.
3. With Docker running and Supabase CLI 2.109.1, replay every migration into a
   fresh disposable catalog; run all pgTAP fixtures, strict lint, and advisors.
4. Apply only the additive consent schema and deploy consent-gated Edge code.
   Keep `internal.ai_consent_rollout_config.enforcement_mode` at
   `legacy_compatible`.
5. Distribute the corrected replacement TestFlight build. Verify all switch
   combinations, inline Terms navigation, VoiceOver, Dynamic Type, smallest
   supported screens, offline withdrawal, account switching, foreground
   reconciliation, Realtime propagation, and ghost-profile merging.
6. Expire every older TestFlight build that cannot produce the current consent
   bundle.
7. Only then run the owner-only forward strict-cutover script and verify legacy,
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

Production remains blocked until both the internal and external sections are
closed with exact-version, exact-build evidence.
