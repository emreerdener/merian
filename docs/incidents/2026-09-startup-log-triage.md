# Startup log triage: offerings, media, and readiness

- **Date detected:** 2026-09-28
- **Status:** Investigating; targeted iOS mitigations and corrected regression
  guards pass local validation. Local media, Insight scrolling, and startup
  probes completed; the final full target passed. Original-device verification
  remains open.
- **Reported build:** 1.0.3 (275), source
  `b01eb5682945e12fb7b91476da1e37ff5467266c`.
- **Implementation baseline:** `d8a771c8f`, differing from the reported source
  only in three compiler/lint fixes.
- **Environment:** Physical-device model, OS version, exact interaction
  sequence, and visible impact remain unconfirmed. Local validation uses iPhone
  18 Pro / iOS 27.0 Simulator; it is not a reproduction of the original
  environment.

## Observations and limits

The supplied excerpt contains 17 HTTP timing samples, all returning status 200.
Authentication preparation ranges from 0.006 to 1.326 seconds (median 0.039);
transfer plus server time ranges from 0.427 to 3.796 seconds (median 1.027).
These sparse samples do not separate server work from network transfer and do
not establish an end-to-end startup duration or a performance regression.

| Area              | Evidence                                                                                | Conclusion                                                                               |
| ----------------- | --------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| Local persistence | Current V52 store selected; library records become visible                              | No migration failure or recovery reset is shown                                          |
| Remote media      | Repeated connection-attempt warnings; no terminal `LocalImageLoader` failure diagnostic | Final image failure and cause are unproven                                               |
| Recovery          | Existing media incidents load; local image recovery succeeds                            | Incidents are server records, not a count of failures created by this launch             |
| Offerings         | Fetch fails, followed by successful identity-link marker                                | Identity completion does not establish product availability                              |
| UI                | Two repeated-per-frame `CGFloat` warnings; one gesture timeout                          | Reproduction and source attribution remain open                                          |
| History           | Two first-page synchronization markers                                                  | Source permits overlapping foreground/listener work; exact runtime overlap is unmeasured |
| Navigation badge  | Initial request rejected during account setup                                           | Source lacks an explicit readiness-triggered retry                                       |

Raw logs, provider bodies, account identifiers, credentials, and media object
paths are deliberately excluded from this record.

During this investigation, credential-free HEAD requests to the public media
hostname's root completed TLS over both IPv4 and IPv6 from the development Mac.
Both returned HTTP 404 (root path only), in 0.222 and 0.182 seconds
respectively. This proves current host reachability from that network, not
availability of any affected object or successful loading on the original
device.

## Confirmed source gaps and mitigations

1. **Offerings recovery and diagnostics.** The unavailable-plan presentation had
   no in-place retry. `PaywallView` now exposes **Try again** through its
   existing injected action; `PaywallViewModel` rejects overlap and
   already-cancelled admission. Purchase readiness still gates retry. The
   offerings failure seam now reports fixed source/category labels and approved
   numeric error codes; SDK message bodies and unknown domains remain excluded.
   This does not fix or diagnose an unverified App Store/RevenueCat
   configuration problem.
2. **Shared startup history work.** Foreground and listener triggers now share
   `AuthHistoricalSessionSyncLiveService` by exact session and Auth generation.
   Same-key callers join one retained task. Replacement cancels old work; stale
   admission or completion cannot displace the replacement. Existing account
   leases, preference coordination, and persistence checks remain authoritative.
3. **Badge readiness.** `MainTabBar` includes account and account-work readiness
   in its refresh identity. Unready calls make no request and invalidate prior
   results; readiness reopening reruns the existing refresh. Foreground and
   Explore-dismissal refresh triggers remain available.

Current contracts are the
[revenue guide](../features-and-hardware/02-revenue-and-identity.md),
[app lifecycle guide](../development-guides/02-app-lifecycle.md), and
[Capture Shell ownership guide](../../apps/ios/Merian/Features/Capture/Shell/README.md).

## Sequential runtime follow-up

The local Debug build uses an Apple RevenueCat SDK key and the shared scheme
does not attach a StoreKit configuration. Only the key's category was inspected;
no key value was recorded. This matches the documented App Store product path,
but does not establish the original device's environment or product readiness.

The first media UI probe failed before opening a scan. Its captured
accessibility hierarchy showed only **Restoring your choices**. Source tracing
and a deterministic consent test expose an ordering gap: initial unowned fixture
consent stops applying when Auth adopts an account, while test mode disables the
cloud synchronization that would bind that evidence. The App root now reapplies
the existing, argument-gated Debug seed after the consent manager adopts a
nonnil owner. Seed failures report an error type rather than being discarded.

Independent review also found that the original fixture used the ordinary
durable consent ledger. Before completing the rerun, Debug UI-test default
managers were changed to a Core-owned in-memory ledger and withdrawal journal.
Synthetic approvals cannot read, modify, or survive into ordinary-launch consent
storage. Explicit store injection and normal/Release durable behavior remain
unchanged. No existing ledger or Keychain state was cleared. Review confirmed
the isolation issue is addressed. This is a test-fixture finding, not evidence
that the reported device was stuck in consent restoration.

The media UI flow then passed: the workspace was reachable, missing video fell
back to its retained image, and the image opened in the zoom viewer. The first
Insight scroll probe assumed automatic library presentation; its prerequisite
was corrected to use the same visible Scans entry already used by the private
map UI test. The rerun passed. Saved screenshots show the header title moving
into the toolbar after scrolling. The private-map fixture supplies media
references without image files, so its placeholder is not evidence of a remote
media failure.

Filtered simulator logs for both passing flows contained no matching
`onChange(of:)`, gesture-gate timeout, or consent-seed failure messages. The
ordinary consent ledger fingerprint was unchanged across the isolated UI run.
These observations cover the seeded flows only, not every Explore geometry path
or the original device session.

### Focused startup measurements

Both existing `RuntimePerformanceTests` passed, with ten samples per test on
iPhone 18 Pro / iOS 27.0 Simulator, Xcode 27.0 (`27A266a`), macOS 26.6.2,
MacBookPro18,1, Debug configuration. The source identity stayed unchanged during
collection. Existing audit helpers validated the selected cases and retained raw
metrics and environment metadata.

| Measured boundary                              | Samples |    Mean |  Median | Sample SD |    CV |
| ---------------------------------------------- | ------: | ------: | ------: | --------: | ----: |
| Cold launch through first-frame responsiveness |      10 | 6.125 s | 6.050 s |   0.278 s | 4.54% |
| Warm foreground elapsed time                   |      10 | 1.242 s | 1.241 s |   0.020 s | 1.61% |

This is a focused diagnostic sample, not the complete runtime audit, an approved
baseline, or evidence of a speedup. It excludes live provider work and is not
comparable to the sparse device HTTP samples. Retained local evidence:
`startup-triage-9bc8730d831e4c5182317641abf07ff5/evidence.json` under
`.artifacts/local-ios`; XCResult `15867da5653f44c79fb3e61c050106be.xcresult`.

## Reproduction and regression coverage

- `PlanViewModelTests`: overlapping retries, subsequent retry after an
  unavailable result, and pre-cancelled admission.
- `RevenueCatManagerTests`: fixed classifications and rejection of provider
  descriptions, underlying errors, and unknown domains.
- `HistoricalSessionSyncLiveServiceTests`: foreground/listener coalescing,
  same-account generation replacement, account replacement, stale admission,
  cancellation-uncooperative work, and later eligible refresh.
- `CaptureNavigationViewModelTests`: deferred admission, readiness reopening,
  and rejection of suspended results when readiness closes.
- Existing media tests retain bounded retries, coalescing, local recovery,
  revision invalidation, and paged recovery registration.

## Candidate validation

- Baseline media suite: **30 tests passed** in three suites before mitigation
  validation. Evidence: local XCResult
  `eb5e6035420845a2ba2c3e00451ee02f.xcresult`.
- Focused mitigation and architecture checks: **92 tests passed** (71 XCTest and
  21 Swift Testing cases). Evidence: local XCResult
  `c5aaf61b7c034e9b84e487d2904c29b9.xcresult`. The initial run found three
  assertions against earlier source-size budgets; review accepted exactly 22
  Auth lines and 14 façade lines for keyed coordination and replacement fencing.
  All ownership and per-file guards remain enforced. That initial run stalled
  during result finalization and was stopped before the successful rerun.
- Full iOS unit-test target executed **4,526 tests**: 1,424 XCTest cases passed;
  3,102 Swift Testing cases completed with the single stale assertion described
  below. No behavioral test failed. Xcode stalled during result finalization
  again and the wrapper was stopped after both frameworks reported their totals;
  this is not a clean full-target command exit. Console evidence:
  `/private/tmp/merian-log-triage-full-tests.log`.
- Full-target validation also exposed a stale Core Data architecture assertion
  that expected the pre-Swift-6 `.live` default argument. The assertion now
  preserves both initializer contracts: an injectable designated initializer and
  an actor-isolated live convenience initializer, with no `.live` default
  argument. This updates the guard for the earlier compiler fix rather than
  changing persistence behavior. The corrected suite passed **8 tests** with a
  successful command exit. Evidence: local XCResult
  `65db0f6b9ffc4bc8b30e7ee4afb3e103.xcresult`.
- A subsequent full run passed **4,526 tests** and exited successfully before
  the runtime probes exposed the fixture gaps. Evidence:
  `9cf682a9ffed4d4e816170ac3278534e.xcresult`.
- Fixture correction: **27 focused App/consent tests and the media UI case
  passed**. Evidence: `92e05c50c1414ba89ff370de6b4451cb.xcresult`. Final storage
  selection lives in `ConsentLedgerStoreFactory`, keeping the manager within its
  existing 600-line boundary. The rebuilt Insight scroll case passed in
  `bd91076e9b094401bc6884f538f5a06d.xcresult`.
- Final full-target run after the fixture changes: **4,527 tests passed** (1,425
  XCTest and 3,102 Swift Testing cases), with zero failures or skips and a
  successful command exit. Evidence:
  `625226d79e434fd8b3ff48244935b78c.xcresult`. Later local runs disable only
  verbose failure sysdiagnose collection to avoid the observed finalization
  stalls; assertions and ordinary XCResult reporting remain active.
- The media UI smoke case passed again against the final build, with a
  successful command exit. Evidence:
  `c6c6c67c5c6945a8ae1a4985adf959ac.xcresult`.
- Strict SwiftLint on all touched Swift files, generated-project validation,
  event-routing, privacy-manifest, transport-security, versioning, migration
  source guardrails, and changed-Markdown formatting checks passed. The build
  retains an unrelated existing `ThreadCheckingAudioPlayer` Sendable warning in
  `AudioPlaybackFilePlayerTests.swift`.
- Independent read-only contract review found no high-risk contract regression.
  End-to-end foreground/listener joining and SwiftUI readiness-triggered task
  restart still need device/UI verification in addition to unit coverage.

## Open investigation and exit criteria

### Review follow-up, 2026-09-28

The supplied CI log confirms that
`CoreDataIntegrationArchitectureTests.historicalSyncHasBoundedLayeredOwners`
still expected the removed `.live` default argument. The corrected local guard
described above covers both replacement initializers. The subsequent simulator
diagnostic timeout does not change the recorded assertion failure.

A second independent review found that already-published Explore badge state
could survive an account transition when the next unread-count request was
unavailable. The view model now clears both badge sources on account replacement
or readiness closure, in addition to fencing suspended results. Regression
coverage exercises direct account replacement and same-account readiness
closure/reopening; temporary unavailable counts within one ready account still
preserve its last known state. Independent re-review found the badge issue
addressed. The rebuilt badge and Core Data architecture suites passed **16
tests**, with a successful command exit; evidence:
`b301eeab386f4f05a09f672135ded8a6.xcresult`.

The complete unit target then passed **4,528 tests** (1,425 XCTest and 3,103
Swift Testing cases) and exited successfully. Evidence:
`21ea72c2d66b4a30b78f3b8c6d7757bd.xcresult`. Strict lint, project/resource,
event-routing, privacy-manifest, transport-security, versioning, migration
source, and Markdown guards also passed during this review. The previous UI and
performance results above predate this badge follow-up; they were not rerun. At
review completion, the CI fix and triage changes were local and uncommitted.
These local results do not establish a passing remote CI run.

### Subsequent CI audio-preview finding, 2026-09-28

GitHub Actions
[iOS Build and Test run #590](https://github.com/emreerdener/merian/actions/runs/36433811358)
tested `7bf76630a`. Startup Safety passed, as did the critical scan UI smokes
and the current-SHA Release archive. The full unit target failed in
`StagedPreviewAudioBoostTests.dismissalDuringCompositionCannotInstallOrResumeLateItem`:
after stopping and removing the item, the test observed `AVPlayer.rate == 1`
instead of zero. This is distinct from the earlier stale initializer assertion.

The unmodified nine-case audio-preview suite passed locally in
`14b4d1b0116242b981b10f1e63b6f839.xcresult`; the requested Xcode iteration flag
did not establish repeated Swift Testing execution, so this is one confirmed
baseline run. Source review found that dismissal invalidates the generation and
active state before the delayed composition can replace an item or request play.
The test's single `Task.yield()` did not establish that delayed work had
finished.

The regression now awaits the exact retained preparation task and counts the
app's play requests through the existing playback dependency container. After
dismissal and late composition completion, it requires no additional play
request, no current item, cleared preparation, and removal of the derivative.
This replaces only the instantaneous rate check on the detached player. The
background-during-seek regression also awaits its exact task. Default playback
and cancellation behavior remain unchanged. Independent read-only review
endorsed these assertions. The rebuilt nine-case suite passed in two separate
test invocations, with successful command exits:
`0087586ecaa447af93afab77406d5f1c.xcresult` and
`a5f036621d2648739e1044f6da165db7.xcresult`.

The complete unit target then passed **4,528 tests** (1,425 XCTest and 3,103
Swift Testing cases), including the revised dismissal case, with a successful
command exit. Evidence: `08b5a33b886840c296f0aa7fe16cae41.xcresult`. Strict
SwiftLint, project/resource, event-routing, privacy-manifest,
transport-security, versioning, migration-source, and changed-Markdown checks
passed. Remote CI must validate the follow-up commit; the earlier successful
archive and UI jobs apply only to `7bf76630a`.

### Remaining device checks

- Confirm the original device/OS, interaction sequence, and visible symptoms.
- Recheck a failing image on Wi-Fi and cellular; correlate an actual terminal
  loader result with the recovery UI before changing media transport policy.
- Inspect the selected StoreKit/RevenueCat environment and a classified offering
  error; demonstrate expected products loading. No provider configuration has
  been changed.
- Reproduce the `CGFloat` warning. Insights header/toolbar threshold feedback,
  Explore detail geometry, and Map preview width observation are candidates, not
  established causes. No speculative geometry patch is included.
- Collect matching original-device startup measurements. The local fixture
  samples above cannot establish a speedup or a regression for the reported
  session.
- Repeat the original device flow with classified offering diagnostics and
  terminal media outcomes.

## Deployment, runtime verification, and recovery

No deployment, hosted mutation, purchase, restore, data cleanup, or media repair
was performed. Physical-device verification and recovery of any affected hosted
media remain open. This record is not a declaration that the reported runtime
issues are resolved.
