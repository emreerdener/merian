# Incident: First-launch browsing blocked by account setup

- **Date detected:** 2026-09-25
- **Status:** Mitigated in source; complete local iOS unit gate passed
- **Affected versions/environments:** Reported as latest TestFlight; exact build
  and occurrence time not supplied
- **Affected surfaces:** iOS Explore Observations, Identify/Species, Profile
- **Current contract:**
  [Auth bootstrap](../development-guides/09-core-managers.md#supabasemanager)

## Summary and impact

One reported fresh installation showed an Explore error, failed to load the
Identify Species index, and displayed disabled Profile sign-in buttons. Closing
and reopening restored operation. The reporter subsequently confirmed the exact
error: “Authentication is changing. Try again in a moment.” This identifies the
client Auth-transition request guard; it does not identify which dependency
extended the transition on that device. No device logs or measured duration were
supplied. No data loss was reported or verified.

## Evidence and failed invariant

`AuthSessionBootstrapCoordinator` adopted and published a session but retained
its exclusive anonymous-bootstrap transition while awaiting purchase identity
resolution and provider linking. Ordinary authenticated requests were rejected
by `AuthTransitionPolicy` during that wait, and Profile intentionally disabled
provider sign-in during any Auth transition. Explore's initial feed and Species
overview did not reload when account setup finished. The same gap affected an
empty Community dashboard.

The failed invariant was that a usable Auth session should allow browsing
without waiting for purchase-provider readiness, and initial loading interrupted
by startup should recover when account work becomes available. Persisted session
reuse on relaunch is consistent with the reported recovery, but the device's
specific delayed operation remains unconfirmed.

## Repository mitigation

Internally owned anonymous bootstrap now validates and returns the published
Auth session before purchase work. Caller-owned bootstrap, including sign-out
recovery, retains the purchase wait and cancellation/session fences. Successful
anonymous-bootstrap transition finish forces the existing retained lifecycle
replay even when the SDK has not delivered a deferred event. That replay keeps
its exact-session/generation checks and acquires account-work leases for
purchase linking. Paid admission and durable handoff barriers remain closed
until their existing requirements are met.

Explore's feed, Species overview, and empty Community dashboard observe
account-work readiness. Initial failures can retry when the session becomes
usable; a failed fresh anonymous bootstrap leaves readiness unchanged and does
not create a retry loop. Feed recovery supersedes an unfinished initial request
so a late cancelled failure cannot replace a successful retry. Successful feed
content and the Species overview freshness policy are preserved. An initial
request still starts Auth while readiness is false, so concurrent requests may
briefly show the transition error. The mitigation provides automatic recovery
after successful Auth setup; it does not suppress every transient error.

## Regression coverage

- `AuthSessionBootstrapCoordinatorTests`: ownerless restored/new sessions open
  ordinary request admission before purchase readiness; explicit owners retain
  the gate; existing cancellation, session replacement, and single-flight cases.
- `AuthSessionLifecycleLiveProviderTests`: forced reconciliation without a
  deferred SDK event performs purchase and entitlement effects, and rejects a
  newer transition before replay.
- `ExploreFeedViewModelTests`: startup failure then successful retry, successful
  page reuse, and a late cancelled initial request after recovery.
- Existing Species overview, lifecycle, purchase-readiness, and architecture
  suites cover freshness, stale completions, session fences, and owner wiring.

All new fixtures use injected synthetic state without real provider requests.

## Candidate validation

The final complete iOS unit run on a disposable iOS 27 simulator passed **4,337
tests**: 1,367 XCTest cases and 2,970 Swift Testing cases in 463 suites. Xcode
reported `TEST SUCCEEDED` and the repository build wrapper exited successfully.
This run includes the new startup regressions, the unchanged Auth source-size
ceilings, purchase/session safety suites, and the complete unit target against
the current working tree. It reused the repository's checkout-local build cache.

The 24 targeted `purchasePrincipalMigrationContract` and
`ghostProfileMergeClientContract` Deno tests passed. Generated-project/resource,
event-routing, privacy-manifest, transport-security, strict changed-production
SwiftLint, Markdown formatting, and diff-whitespace checks also passed. No new
Swift source file or generated-project membership change was needed for this
fix.

Earlier focused attempts exposed and resolved an Auth line-budget failure and an
incorrectly updated architecture assertion; every focused XCTest case passed.
Those unsuccessful Xcode runs stalled after their test results and were stopped
through their own wrapper. A first attempt had been refused while another build
was active; that build was left untouched. Only the final complete successful
run is candidate evidence. Its result bundle is retained under
`.artifacts/local-ios/8c9a5c9c3c8c4fd19488edccc7c1f2f7.xcresult` in the
validation checkout. It is local evidence, not a committed or hosted release
artifact. The disposable simulator was removed after validation.

The
[first-launch verification matrix](../development-guides/08-testing-strategy.md#first-launch-account-readiness-verification)
owns the regression boundaries and manual fresh-install procedure.

Physical-device fresh-install QA, critical UI smokes, a Release archive, exact
reported-build correlation, and verification after an authorized TestFlight
release remain open. Local unit success does not establish those outcomes.

## Production deployment and runtime verification

**Not performed.** No TestFlight upload, hosted mutation, or deployment was
requested. The fix has not been verified on the reporting device.

## Data recovery and privacy

No recovery operation was performed; no data-loss evidence was supplied. This
record includes no credentials, personal data, coordinates, session material, or
production response bodies.

## Exit criteria

- [x] Reported error matched to the client request guard.
- [x] Repository mitigation and synthetic regression coverage added.
- [x] Complete local iOS unit suite and targeted contract checks pass.
- [ ] Physical-device, UI-smoke, and Release candidate validation pass.
- [ ] Exact reported build and delayed dependency are identified.
- [ ] Fresh-install TestFlight behavior is verified after an authorized release.
