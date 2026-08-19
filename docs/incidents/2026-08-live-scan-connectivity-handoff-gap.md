# Live Scan Connectivity Handoff Gap

**Date:** 2026-08-09 (updated 2026-08-10)\
**Severity:** Release-blocking scan-reliability risk\
**Affected boundary:** Caller-scoped admission preview → durable queue
acceptance → foreground Identify transport → offline replay → open Insight
presentation\
**Repository status:** Remediated in the current working tree; exact-SHA hosted
and physical-device acceptance remains open\
**Production status:** Do not describe the handoff as released until every
closure gate below passes, including one exact workflow SHA and the physical
device matrix

## Summary

Every submitted scan is durably queued before a live provider request begins.
The original remediation protected connectivity loss after that durable
acceptance. A second review found an earlier boundary: online Capture asked
Supabase for a caller-scoped admission preview before starting hardware or
creating the queue row. `NWPathMonitor` could still report online on captive,
black-holed, or no-upstream Wi-Fi, leaving that shared request to fail or stall
before the observation became durable.

The joined source now bounds that preflight to two seconds with no connectivity
wait, cache, or retry. A classified URL transport failure plus current local
eligibility selects a queue-only route. Submission then persists the normal
queue row without a foreground inference generation or analyzing Insight; the
durable scheduler and authoritative `reserve_ai_quota(...)` transaction own
later retry. Missing/malformed data, cancellation, authentication/TLS, server
failure, and valid plan/quota denials retain their fail-closed behavior.

After durable acceptance, connectivity failure is likewise not terminal: the
foreground request should relinquish the uplink, the existing Insight should
keep ordinary analysis copy while online or show queued/waiting copy while
offline, and the durable queue should resume the same scan UUID when transport
is eligible.

The current source separates local presentation authority from durable provider
authority. Queue-backed live Identify disables the generic transient transport
replay and bounds its one foreground request to 15 seconds. The first URLSession
connectivity failure—or that deadline on a silently stalled path—moves only the
exact still-current sheet to queued content even if path monitoring already
retired the durable generation. That handoff releases the upload hold, does not
advance the provider/network circuit, retains the same durable row, and leaves
background recovery as the sole retry owner.

The regression now runs at the URLSession boundary for visual and nonvisual
submissions. It deliberately retires durable ownership while requests are
pending before releasing `.networkConnectionLost` and `.notConnectedToInternet`.
Its `.timedOut` branch instead keeps the exact durable owner active and the path
online, modeling black-holed Wi-Fi reaching the foreground deadline without an
`NWPathMonitor` callback. Both branches prove exact-ID queued routing, one
request, bounded handoff timing, eventual durable retirement, row survival, and
circuit isolation. The matrix also covers a transport-owned cancellation, the
reviewed cannot-load-from-network and background-session-disconnect variants,
and a successful response that becomes ownership-cancelled after the queue has
already taken over. Admission and post-durable recovery share one bounded
recursive URL-error classifier while TLS/authentication remain excluded from
queue-only admission. Specific certificate, authentication, and ATS policy codes
veto both decisions at every inspected wrapper depth, so a broad outer transport
error cannot hide them; a chain exceeding the reviewed bound also fails closed.
Separate protected controls retain the reviewed queue-less 90-second window,
retry, and **Network timeout** presentation and keep provider `5xx` failures in
**Analysis delayed / Scan saved**.

This is source-remediation evidence, not a production-release claim. Closure
still requires one exact workflow SHA and the physical connectivity matrix
below.

## Required Customer Contract

| Condition                                                                      | Presentation                                                                                                              | Retry owner                               |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| Known offline before admission                                                 | If local eligibility permits, Capture proceeds queue-only and does not call the preview RPC                               | Durable queue                             |
| Path appears online but admission transport fails                              | If local eligibility permits, save queue-only with no analyzing Insight or foreground owner                               | Durable queue                             |
| Admission returns a valid plan/quota denial                                    | Preserve staged input and open the paywall                                                                                | User after entitlement change             |
| Admission is cancelled, malformed, unauthorized, or fails at TLS/server policy | Preserve staged input and show retry feedback; do not infer offline admission                                             | User                                      |
| Offline before live dispatch                                                   | Capture queues the scan and does not start provider transport                                                             | Durable queue                             |
| Connectivity changes during the 150 ms context grace                           | Offline Insight shows queued/waiting; an online durable handoff keeps ordinary analysis copy                              | Durable queue                             |
| First queue-backed transport failure after dispatch                            | Same-ID Insight keeps normal analysis copy online, or queued/waiting offline, without an error haptic or synthetic result | Durable queue; no inline transport replay |
| Path stays satisfied but transport silently stalls                             | Same-ID Insight keeps ordinary analysis copy after the 15-second durable handoff                                          | Durable queue; exact-ID status/replay     |
| Queue-less direct request loses transport                                      | **Network timeout / Please try again** may be shown                                                                       | Caller                                    |
| Handler/provider returns an exhausted service failure                          | **Analysis delayed / Scan saved** as an error placeholder, never a biological classification                              | Durable queue                             |
| Background or status recovery completes the same UUID                          | Completed result replaces queued content in place                                                                         | Completed owner row                       |

The transport signal and the path monitor are advisory inputs, not competing
sources of customer truth. The stable queue row is the recovery authority. A
connectivity callback may retire provider ownership immediately, but that
retirement must not erase the still-current local presentation identity before
the exact-ID queued handoff is published.

## Root Cause

### A shared pre-queue request treated reachability as transport proof

`CaptureWorkspaceViewModel.requestScanAdmission` formerly chose between a local
offline meter and an online Supabase RPC solely from
`OfflineQueueManager.isOnline`. A satisfied network path does not prove DNS,
upstream internet, a usable captive-portal route, or Supabase reachability. The
online branch used the shared client transport and collapsed every error into
one unavailable result. Because this happened before `OfflineQueuedScan`
creation, a timeout could show **Unable to check scan availability** while no
durable retry owner existed.

`ScanAdmissionManager` now returns typed `available`, `connectivityUnavailable`,
or `unavailable` results from an isolated ephemeral session. Its request and
resource deadlines are exactly two seconds, `waitsForConnectivity` is false, URL
caching is absent, the explicit request timeout is set, and PostgREST retry is
disabled. Only a reviewed set of URL transport errors—including timeout, no
internet, connection loss, DNS/host, and data-path failures—maps to
`connectivityUnavailable`. Cancellation, TLS, authentication, server, and
response-shape failures remain `unavailable`.

The Capture policy combines that typed result with current local eligibility.
Connectivity unavailability may proceed only as queue-only; it cannot create a
foreground generation or dispatch Identify. Local ineligibility still opens the
paywall, while generic unavailability still requests retry. The provider-side
reservation remains authoritative during durable replay, so the fallback grants
no quota and cannot override a cross-device decision.

### Durable ownership and local presentation were coupled

`InferenceEngine.isLiveInferenceAttemptCurrent` requires both the local
presentation generation and the queue manager's foreground generation to be
current. When `OfflineQueueManager` observes an unsatisfied path, it calls
`releaseAllForegroundInferenceClaims`. Retirement synchronously registers the
generation in the retirement registry, making the full ownership check false
before URLSession necessarily returns.

The later `URLError` catch therefore formerly exited at the stale-owner guard.
Its defer path could stop processing and clear active identity without
publishing `queuedPresentationScanId`. With no queued context, no `SpeciesData`,
and `isProcessing == false`, the open Insight could continue routing to
analyzing content with no state transition able to complete it.

The repair distinguishes these two authorities:

- **local presentation ownership** decides whether the exact still-open sheet
  may change to queued content; and
- **durable foreground ownership** decides whether provider results, failures,
  queue cleanup, telemetry, or retries may still commit.

A newer scan or completed same-ID result must invalidate the local presentation
before a delayed failure can act. Durable retirement alone must not prevent the
current sheet from acknowledging that the queue took over.

### Generic transport replay delays durable recovery

`identifyMultiModal` historically used a 90-second request timeout and always
sent a stable idempotency key. The shared authenticated request helper also
retried every eligible transient `URLError` once after two seconds. A
black-holed Wi-Fi or captive path could therefore keep a queue-backed scan in
live analysis for approximately 182 seconds before the engine saw the final
error. Removing the replay reduced that worst case to 90 seconds but still left
the most frustrating path far outside the documented six-second cache-hit
end-to-end p95 target.

The request now accepts explicit recovery ownership. Queue-backed foreground
Identify sets `durableQueueOwnsRecovery`, receives one 15-second request window,
and returns its first transport failure to the engine. Fifteen seconds is more
than twice the documented p95 target, while a slow valid completion remains
recoverable under the same stable scan ID and idempotency key. Queue-less
callers retain the reviewed 90-second window and inline retry; authentication
refresh, route-propagation recovery, and handler `5xx` behavior remain
independently scoped.

### Error presentation no longer depends on display copy

The generic saved-service fallback constructs non-biological-shaped
`SpeciesData` titled **Analysis delayed**. The former placeholder whitelist did
not recognize that title, so the row could be classified as a genuine
non-biological result and receive the wrong pill, retention copy, haptic, or
success lifecycle.

The current contract uses explicit typed presentation state instead of a title
whitelist. `InferenceEngine.makeErrorSpeciesData(...)` marks every transient
failure and policy presentation as `.inferenceError`; decoded and persisted
classifications default to `.inferenceResult`. `isInferenceErrorPlaceholder`
therefore cannot change when customer-facing copy changes. A direct role test
and the protected queue-backed server/provider tests lock both sides of this
boundary. Exact-SHA workflow and device acceptance still apply to the joined
source repair.

### The former test stopped before the transport boundary

The original
`queueBackedConnectivityFailuresUseQueuedPresentationForVisualAndNonVisual`
injected `URLError` through `overridingInferenceConsentCheck`, before request
construction and URLSession dispatch. It proved only the catch classifier under
uninterrupted ownership.

The replacement uses `MockURLProtocol` with a bounded gate. It observes the
first request, invokes the same upload-hold and foreground-claim retirement used
by the path monitor, waits for durable generation metadata to clear, and only
then releases path-loss transport errors. The timeout branch deliberately skips
that retirement, proves the queue owner and generation metadata are still
current, then releases `.timedOut` and requires the handoff itself to retire
them. Companion network-client tests prove queue-backed Identify carries the
15-second request bound and returns after one request, while the reviewed
queue-less path retains the 90-second bound and one stable-idempotency-key
replay.

## Closure Gates

This incident is closed only when one exact workflow SHA supplies all of the
following:

1. Pre-queue admission uses an exact two-second request/resource bound, no
   connectivity wait, no cache, and no PostgREST retry. A path-satisfied
   `.timedOut` preview plus local eligibility persists visual and nonvisual
   queue rows with no foreground generation, analyzing Insight, or live engine
   processing; malformed/non-connectivity failure stays blocked and local
   ineligibility still paywalls.
2. Visual and nonvisual queue-backed tests dispatch a real mocked request. The
   path-loss cases release the body-upload hold, trigger connectivity
   retirement, and only then deliver `.networkConnectionLost` or
   `.notConnectedToInternet`; a separate `.timedOut` case keeps path and durable
   ownership active until the transport deadline is delivered.
3. Both paths publish the exact `queuedPresentationScanId`, bind the matching
   durable row, route the open Insight to `.queued`, stop live processing, and
   emit no error placeholder, error haptic, network-circuit failure, or second
   provider request.
4. The durable queued scan survives; its deferred-upload hold and foreground
   generation eventually clear without test-only manual state repair; staged
   recovery can resume under the same scan UUID.
5. Deterministic request-policy, count, and timing assertions prove the
   queue-backed request carries the 15-second foreground bound, does not enter
   the two-second inline replay or a 90-second deadline, and hands presentation
   to the queue within 1.5 seconds after URLSession reports failure.
6. A queue-less direct transport failure still produces the reviewed **Network
   timeout** recovery state.
7. Exhausted queue-backed `5xx`/provider failure produces **Analysis delayed /
   Scan saved**, is classified as an inference error placeholder, never emits
   non-biological success treatment, and leaves durable retry intact.
8. A completed background response or status-recovered record for the same ID
   replaces queued content in place; a stale failure cannot overwrite that
   completion or a newer scan.
9. The complete iOS unit-test target, protected critical scan-flow inventory,
   deterministic live-Insight-to-queue and queued-scan-completion UI smokes, and
   current-SHA Release archive all pass with zero failures or skipped required
   cases. The live-sheet dismissal resolves `InsightSheetCloseButton` through
   the current `InsightSheetView`; a global `Close` label query is ambiguous
   when an underlying presentation remains in the accessibility tree.
10. Physical-device QA covers airplane mode, Wi-Fi with no upstream internet,
    captive portal, Wi-Fi-to-cellular handoff, app backgrounding during upload,
    and reconnect. The saved scan must remain visible and complete exactly once.

The reviewed remediation addressed gates 1–8 in source and exact protected test
declarations. At that review point, the hosted workflow required the
open-live-sheet queue transition and queued-completion smokes as one exact
two-case result set. The current workflow retains both incident cases inside its
later three-case set, alongside the progressive-analyzing smoke. The incident
remains open because gate 9 has not run from a clean commit containing the
remediation and gate 10 requires physical-device evidence.

## Validation Status at Review

The current local review checkout is based on published HEAD
`1dc9c587a32bdcccf6ef6c6a40e19caf17df6fb8`. That commit contains the bounded
admission route, queue-backed transport handoff, stable Insight close selector,
and 92-case protected inventory. Hosted iOS Build and Test Run 226 ran on the
earlier ancestor `fc2a55594339827ad2d2402d86da80dfccd67575`: it passed all 1,465
unit tests and the queued-completion UI smoke, and its validation-only Release
archive passed the privacy-manifest, ATS-default, dSYM, and Debug-marker checks.
The live-to-queue smoke reached the exact queued presentation and every
pre-dismissal assertion, then failed because the old global
`app.buttons["Close"]` query matched both the active Insight close control and
an underlying close control.

Published HEAD assigns `InsightSheetCloseButton` directly to the native toolbar
button and requires that identifier in the smoke and portable workflow contract.
Run 226 validates the queue handoff before dismissal but cannot validate that
later selector correction or the later pre-queue admission boundary. A separate
22-file local delta replaces title-derived inference-error routing with explicit
`SpeciesData.presentationRole` and centralizes wrapped URL-failure
classification across pre-queue admission and post-durable recovery; this
environment exposes `.git` read-only, so that final hardening does not yet have
a commit SHA.

Local construction evidence is deliberately split by source state:

- published HEAD's complete 418-file production module, 89-file unit target, and
  two-file UI target type-checked against the cached iOS Simulator SDK and
  locked package modules before the current delta;
- all seven Swift files changed by the current delta parse;
- the exact current `SpeciesData` and Identify DTO sources type-check together
  for the iOS Simulator target, and a focused executable using those real model
  sources passes both copy-independence directions;
- the exact current `ScanAdmissionManager`, `MerianError`, and locked Supabase
  module type-check together for the iOS Simulator target, while a second
  focused executable using the real connectivity policy passes its complete
  queue-only, wrapped-error, TLS/auth exclusion, and post-durable matrix;
- generated-project membership resolves 418 app target inputs, 89 unit-test
  sources, and two UI-test sources;
- strict no-cache lint reports zero violations across all seven changed Swift
  production and test files;
- the critical-result and focused-result validator harnesses plus the iOS
  build/workflow contract pass, with all 95 protected unit declarations,
  including exact durable scan-ID/generation pairing for both engine pipelines,
  automatic single-capture suppression of the manual **Identify** toolbar,
  pre-import paywall admission before picker/crop work, and the exact two-case
  UI result requirement retained at that review point; the current three-case
  set still contains both incident regressions; and
- `git diff --check` passes.

The full current app module cannot be reconstructed again inside this sandbox:
the standalone compiler reaches SwiftData but the platform macro plugin server
is denied, while Xcode/SwiftPM remain blocked by CoreSimulator and nested build
sandbox policy. The narrower current-source check above is real compile/runtime
evidence, but it does not upgrade the current uncommitted delta to full-target
or simulator evidence.

Supabase Candidate Validation Run 1676 at
`fd1eb8dda7ff109ec339960104a49e577fa27f5b` correctly selected complete
validation because the push changed backend, iOS/schema, documentation, and
workflow/tooling inputs. It used no production environment, production secret,
or production mutation. Its disposable validation failed only after the
repository-tooling phase found two stale documentation expectations: the old
81-case protected inventory and the former singular queued-completion UI smoke.
The committed descendant base updated those contracts to 91 cases and the exact
two-smoke set; published HEAD extends the protected inventory to 92 for the
pre-queue admission connectivity handoff. The current scan-reliability delta
strengthens that protected case and extends the inventory to 93 by protecting
the visual/nonvisual durable scan-ID/generation ownership fence. The staged-
toolbar presentation follow-up extends it to 94 by protecting automatic
single-capture suppression and failure recovery. The pre-import admission
follow-up extends it to 95 by protecting paywall denial before picker/crop work.
The complete local candidate/tooling gate now passes: 186 standard TypeScript
tooling tests, 16 isolated DTO tests, executable Identify contract tests, every
shell/tooling check, and all 18 documentation contracts. All 262 migration
source assertions pass across 39 discovered test files, including the
caller-scoped read-only scan-admission RPC. These source results repair the
reported contract failure but do not substitute for the workflow's fresh
disposable-database replay on one committed exact SHA.

The sandbox cannot reliably connect to CoreSimulatorService or apply SwiftPM's
nested build sandbox, so it cannot run the Xcode test bundle locally. Direct
compiler construction is not runtime evidence. A new hosted exact-SHA unit/UI
run and Release archive plus physical-device QA remain acceptance gates 9 and
10.

The supplied `supabase_logs (1).csv` contains 76 auth/RPC rows, no Identify or
inference transport row, and no non-zero latency value. It cannot establish a
production latency distribution. The checked-in rollout contract does provide a
cache-hit end-to-end p95 target of six seconds, so the current source uses a
conservative 15-second queue-owned foreground bound while retaining the
90-second direct-caller window. The no-upstream Wi-Fi and captive-portal device
cases must still measure actual tap-to-queue timing and verify that legitimate
slow completions recover under the same scan ID before this policy is released
or tuned further.

## Related Contracts

- [Scan Ingestion Reliability and Recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
- [API Contracts](../backend-and-data/05-api-contracts.md)
- [Offline Sync Pipeline](../backend-and-data/01-offline-sync-pipeline.md)
- [Error Handling](../development-guides/06-error-handling.md)
- [AI Engineering](../system-architecture/04-ai-engineering.md)
- [Insight Sheet](../features-and-hardware/05-insight-sheet.md)
- [Gamification and Telemetry](../features-and-hardware/03-gamification-and-telemetry.md)
- [Core AI](../../apps/ios/Merian/Core/AI/README.md)
- [Core Network](../../apps/ios/Merian/Core/Network/README.md)
- [Core Security](../../apps/ios/Merian/Core/Security/README.md)
- [Capture Submission](../../apps/ios/Merian/Features/Capture/Submission/README.md)
- [Insight Content](../../apps/ios/Merian/Features/Insights/Content/README.md)
