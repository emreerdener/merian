# Incident: Simulator signing and startup recovery loop

- **Date detected:** 2026-09-22
- **Status:** Mitigated in source; affected simulator recovered; local
  verification recorded
- **Affected versions/environments:** Local unsigned simulator build 1.0.3
  (275), iPhone 18 Pro / iOS 27.0; broader simulator impact reported but not
  measured
- **Affected surfaces:** Local iOS build tooling and ordinary app startup
- **Current contracts:**
  [Local iOS build storage](../development-guides/08-testing-strategy.md#local-ios-build-storage)
  and
  [account-deletion crash recovery](../backend-and-data/20-sign-in-with-apple-account-deletion.md#client-crash-recovery)

## Summary

The installed simulator app repeatedly displayed **Finishing Account Deletion**
and could not reach capture. The owner reported the same behavior when launching
other simulators. Investigation found that the local build wrapper disabled
signing for every platform, omitting the runtime entitlement packaging needed
for ordinary simulator Keychain access. An unreadable Keychain makes startup
retain a conservative recovery barrier; repeated unreadable lookups cannot
resolve it. This path requires no actual deletion request.

The wrapper now uses local ad-hoc signing for simulator builds and retains
unsigned device compilation. That repaired Keychain access but did not clear the
already-persisted marker. A second defect prevented startup from rechecking an
existing lookup barrier, leaving later recovery dependent on a cached session
that a fresh simulator may not have. Startup now clears only that lookup-only
marker after verified proof absence. The corrected app reached its normal
welcome screen on the affected simulator without manual data cleanup. The owner
then completed onboarding, and the normal capture screen was observed.

## Impact and scope

One affected simulator was directly observed during preparation for an approved
two-photo identification benchmark. Both cases were unattempted during
diagnosis; they subsequently completed after local recovery and UI access were
restored. The owner reported additional affected simulator launches; their
number and installed build provenance were not measured. Physical devices,
TestFlight and hosted production were not diagnosed as affected by this local
tooling defect.

## Detection and timeline

| Date (UTC) | Event                                                                                                          | Evidence status                                         |
| ---------- | -------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| 2026-09-22 | Capture unavailable behind the recovery screen                                                                 | Direct simulator observation                            |
| 2026-09-22 | Wrapper found to force `CODE_SIGNING_ALLOWED=NO` on simulator actions                                          | Source inspection                                       |
| 2026-09-22 | Regression rejects unsigned simulator command construction                                                     | Failed before fix; passed afterward                     |
| 2026-09-22 | Independent review found qualified setting overrides bypassed validation                                       | Reproduced; fixed and covered                           |
| 2026-09-22 | Ad-hoc simulator build completed with populated simulated entitlements                                         | Local build and generated artifact inspection           |
| 2026-09-22 | Signed app returned normal missing-item status for an unrelated synthetic key, but remained on recovery screen | Read-only runtime probe and UI observation              |
| 2026-09-22 | Error followed by later absence reproduced the persisted-marker deadlock                                       | Focused Swift regression failed before source fix       |
| 2026-09-22 | Startup correction passed focused tests and reached the normal welcome screen                                  | 27 passing Swift tests and direct simulator observation |

## Reproduction and root cause

`scripts/local-ios-build.py` previously appended `CODE_SIGNING_ALLOWED=NO`
unconditionally. In the normal app process, `KeychainManager.dataOrThrow`
distinguishes a missing item from a failed secure-store lookup. Startup calls
`AccountDeletionRecoveryCapabilityStore.restoreBarrierBeforeAuthBootstrap`
before Auth. Any lookup error records `capability_lookup_pending`, because an
unreadable store cannot prove that a deletion recovery capability is absent.

`AccountDeletionRecoveryCoordinator.resumePendingLocalCleanup` then attempts the
same secure-store read. A repeated error retains the barrier and returns false;
the app's automatic retry task consequently keeps the recovery screen visible.
The expected Security failure for an entitlement-free process is
`errSecMissingEntitlement` (`-34018`), but that original error was not captured.
After the signing correction, an unrelated synthetic absent-key lookup in the
running process returned `errSecItemNotFound` (`-25300`). It read no stored item
data, and the debugger detached. Apple's
[entitlement error documentation](https://developer.apple.com/documentation/security/errsecmissingentitlement)
describes that authorization failure.

The initial packaging defect and the persisted-marker deadlock are separate. The
original pre-Auth helper returned immediately for every existing marker,
including `capability_lookup_pending`. The later recovery coordinator could
resolve missing proof only after restoring an exact cached session; without one,
a temporary lookup failure became a permanent startup block. The isolated
regression reproduces an unreadable first lookup followed by verified absence on
a second startup, without constructing an Auth session.

Treating a secure-store error as a missing recovery proof would weaken the
deletion contract. Recovery tests use isolated defaults suites and injected
secure stores; no evidence was found of those tests writing the production
deletion marker. The test-only Keychain fallback is inactive during ordinary app
launches.

## Repository mitigation and regression coverage

- Simulator actions now append `CODE_SIGNING_ALLOWED=YES` and
  `CODE_SIGN_IDENTITY=-`, using local ad-hoc signing without developer
  certificates or provisioning updates.
- Device validation still appends `CODE_SIGNING_ALLOWED=NO`.
- The wrapper owns both signing settings. SDK- and configuration-qualified
  variants of owned settings are rejected along with ordinary overrides.
  Existing output-path, cache-lock, archive and provisioning controls remain.
- Regression cases cover all four simulator actions, unsigned device
  compilation, ordinary identity overrides, and qualified signing/output-path
  overrides. The qualified cases failed before the validation fix.
- Normal startup now rechecks only missing or lookup-only state. Verified
  absence clears only the lookup marker, without session restoration, proof
  retirement, or account-data cleanup. All actual, legacy and unknown phases,
  present proofs and read errors retain their existing guard.
- Pre-bootstrap resolution suppresses runtime events. Failed durable removal
  reasserts the marker. App-hosted tests skip the live probe because their
  synthetic Keychain fallback cannot establish real proof absence.
- Swift regressions cover the failed-read/later-absence sequence, repeated
  startup, preservation of unrelated preferences, no Keychain mutations,
  present/unreadable proof, other deletion phases and event suppression. The
  App-root architecture assertion fixes the test-mode guard before dependency
  initialization; the full native run includes that new assertion.
- The testing guide and iOS skill now describe the platform-specific signing
  behavior and recovery through an install over the existing app.

## Candidate validation

The complete portable iOS tooling gate passed, including 18 runtime-audit tests,
27 build-wrapper tests and all fifteen shell suites. The signing-only Debug
`build-for-testing` completed through `make ios-local-build` for the affected
simulator using the reusable cache. Its XCResult is retained locally at
`.artifacts/local-ios/1a0e0505b1384705944be581e0c5688c.xcresult`.

The built app reports source revision
`7cb12cce16bd736ea1dc725663cacd10471cac46`, dirty source state, and fingerprint
`4238ea4da74946a2eba10580d5c1081e7571acf0670d20d068f815290dafd132`. Its
generated `Merian.app-Simulated.xcent` contains the application identifier and
one Keychain access group. Simulator entitlements must be inspected at the
simulated runtime boundary; a code-signature entitlement dictionary alone is not
sufficient evidence of their presence or absence.

The signing-only build predates the Swift recovery-state correction and is not
evidence of final startup recovery. The first method-level Swift selector
matched zero tests and is excluded from correctness evidence. The subsequent
complete capability-store suite reproduced the new regression failure: nine
tests passed and the new case failed in
`.artifacts/local-ios/1a88d0763ca440c38b0d42683bee78f9.xcresult`.

After the source correction, all 27 selected Swift tests passed in
`.artifacts/local-ios/d2be80922e97483d85017d1973eda9e9.xcresult`, with zero
skips. The six Deno account-deletion source-contract tests and generated iOS
project validation also passed.

The complete native target ran 4,267 tests with zero skips: 4,266 passed and one
failed in `.artifacts/local-ios/41aef949f7814fbd9ef7eb3c85e8955b.xcresult`. The
sole failure was
`InsightMediaCarouselArchitectureTests.testPlaybackStateRemainsPrivateAndColocated`,
which still expected the view to hold `AVAudioPlayer` after the separately
staged audio refactor introduced `AudioPlaybackFilePlayer`. The assertion now
checks the wrapper while retaining the private, view-owned state requirement. No
audio runtime code was changed for this correction.

All 15 tests in the subsequent audio-carousel and App-root architecture rerun
passed, with zero skips, in
`.artifacts/local-ios/e77e5b5eddf84e7cbde43522c1ed6e08.xcresult`. This includes
the new pre-Auth test-mode guard assertion. The full target was not repeated
after that test-only correction; the focused result supplements the failed
full-run bundle. An optional simulator diagnostic collector was stopped after
test execution had finished so Xcode could finalize the first result; no test
runner or app process was interrupted for that collection step. The focused
rerun disabled optional verbose diagnostic collection.

Changed-Markdown formatting passed for all 37 changed documents. Agent-asset
validation, the exact Supabase functions/scripts formatting check, focused
documentation links and diff whitespace checks also passed.

## Production deployment

**Not performed.** No hosted mutation, external release, or production
account-deletion request is part of this fix. The native correction is in the
local simulator build; distributing it through TestFlight or the App Store is
separate release work.

## Runtime verification

The corrected app was installed over the affected simulator installation and
launched through the ordinary app entry point. It reached the normal welcome
screen. No recovery marker, Keychain item, app container or simulator was
manually deleted. Genuine deletion-state preservation was checked through the
isolated negative tests; no real deletion was initiated to test it. Only one
simulator was directly verified. The owner subsequently completed onboarding and
account selection, and the normal capture screen was observed. A separate macOS
Screen Recording permission blocked UI automation until the owner completed the
Computer Use helper's setup. Automation and Accessibility had already been
enabled.

After native verification finished, the app was relaunched without test-host
arguments or environment overrides. The ordinary launch command succeeded. After
window capture became available, the normal capture screen and two completed
identifications were observed through the live UI. Their outcomes and timings
are retained in the
[live benchmark](../rfcs/identification-production-app-benchmark-2026-09-22.md).

## Data recovery

No manual data cleanup, account reset or simulator erase was performed. The
app's verified-absence startup path resolved the false lookup barrier.

## Privacy and security review

Evidence is restricted to source, build configuration, synthetic tests, bundle
provenance and aggregate UI outcomes. No credentials, personal data,
coordinates, auth/session material or production response bodies are retained.
Secure-store failure remains fail closed; the fix restores the runtime
capability rather than changing that policy.

## Exit criteria

- [x] Local unsigned-build failure path is bounded and regression-covered.
- [x] Independent review findings are addressed.
- [x] Complete affected tooling gate and documentation checks pass.
- [x] Full native results are retained and the sole stale assertion passes its
      focused rerun.
- [x] Local recovery is distinguished from any future native release.
- [x] Affected simulator opens normally after installing the corrected build.
- [x] Recovery succeeds without manual data or deletion-journal cleanup.

## Follow-ups

The prepared two-photo identification experiment has resumed and completed.
Additional simulators with old unsigned app installations need the corrected
build; changing simulator selection alone does not correct the installed binary.
