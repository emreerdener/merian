# Incident: First photo import can precede account readiness

- **Date detected:** 2026-09-22
- **Status:** First-launch readiness gap mitigated in source; reported-device
  cause unconfirmed
- **Affected versions/environments:** Reported build and incident time unknown
- **Affected surfaces:** iOS Capture admission and Auth bootstrap
- **Current contract:**
  [Scan admission preview](../backend-and-data/05-api-contracts.md#scan-admission-preview-rpc)

## Observation and impact

A new user reported granting full Photos access and then seeing “Unable to check
scan availability. Please try again.” The image-import entry check can produce
this message before the picker opens. No device logs or correlated production
diagnostics were supplied, so the exact cause remains unconfirmed.

## Evidence and hypotheses

Capture starts best-effort Auth warmup asynchronously. Previously,
`ScanAdmissionManager.preview` immediately attempted an account-work lease and
required a published user and SDK session. An unfinished or failed first-launch
bootstrap therefore returned unavailable without waiting or retrying setup. The
online admission policy maps unavailable to the reported message.

Server, authentication, TLS, and invalid-response failures can produce the same
message. Existing ordinary timeout and quota-denial paths instead select the
offline fallback or paywall. Photos permission completion only dismisses its
sheet in current source; a subsequent import tap performs admission.

## Repository remediation

`ScanAdmissionSessionReadiness` joins the existing anonymous-bootstrap
single-flight or retries eligible first-launch setup before acquiring any
account-work lease. Stable sessions use the existing fast path. Prior OAuth
recovery, purchase handoff, deletion, and non-bootstrap Auth transitions remain
blocked. Cancellation and changed identities cannot admit the suspended import.
The shared bootstrap retains ownership of its task. Each caller waits at most
five seconds and returns promptly on cancellation; the existing two-second RPC
deadline applies separately. A fixed session-readiness diagnostic contains no
user or session data.

The lease cleanup is also installed immediately after acquisition so later
credential or URL validation cannot leave a lease outstanding.

## Candidate validation

The final focused run on a temporary clean iOS 27 simulator passed 121 tests:
102 XCTest cases and 19 Swift Testing cases. All 14 new readiness regressions
passed, including the actual photo-picker admission method, delayed publication,
failure then retry, identity protection, prompt cancellation, non-cooperative
bootstrap deadlines, and unrelated Auth transitions. App and test targets
compiled successfully through `make ios-local-build` using checkout-local
caches.

The broader run on the previously used simulator executed 1,347 XCTest cases and
2,912 Swift Testing cases. Every Swift Testing case passed; three XCTest cases
failed:
`AuthLocalSignOutFacadeTests.testFacadeClosesRequestGateBeforeSDKInvalidation`,
`SupabaseManagerTests.testGetValidAuthHeadersUsesDeterministicTestStub`, and
`InsightMediaCarouselArchitectureTests.testPlaybackStateRemainsPrivateAndColocated`.
The first two passed in the final clean-simulator run, consistent with shared
Auth state or persisted simulator state affecting the broader run. The last
asserts the old audio-player declaration, which separate existing workspace
edits replaced. Those unrelated files were preserved. Xcode stalled after all
broad-run test results were emitted; its idle wrapper was interrupted, so this
is not a green complete candidate gate.

Generated-project, event-routing, privacy-manifest, transport-security, changed
Markdown formatting, focused strict SwiftLint, and diff-whitespace checks
passed. Physical-device Photos permission QA, a clean complete candidate gate,
and correlation with the reported build remain open. No real Auth or provider
request was used by the new regression fixtures. The temporary test simulator
was removed after validation.

## Production deployment

**Not performed.**

## Runtime verification

**Not performed.** The reported device's cause and recovery remain unconfirmed.
