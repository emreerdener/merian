# Live Scan Connectivity Handoff Gap

**Date:** 2026-08-09\
**Severity:** Release-blocking scan-reliability risk\
**Affected boundary:** Queue-backed foreground Identify transport → durable
offline replay → open Insight presentation\
**Repository status:** Open in source; presentation plumbing exists, but the
joined transport/ownership behavior is not yet accepted\
**Production status:** Do not describe the handoff as released until every
closure gate below passes on one exact workflow SHA

## Summary

Every submitted scan is durably queued before a live provider request begins.
That durability means a connectivity failure is not a terminal scan failure: the
foreground request should relinquish the uplink, the existing Insight should
change to **Queued for later**, and the durable queue should resume the same
scan UUID when transport is eligible.

The reviewed working tree contains the exact-ID presentation state and queued
view needed for that experience, but four joined gaps remain:

1. connectivity monitoring can retire the durable foreground generation before
   the live URLSession failure reaches `InferenceEngine`;
2. the shared authenticated client can replay the queue-backed Identify request
   once after a transient transport failure, delaying the handoff through a
   second 90-second request deadline;
3. the queued service fallback title **Analysis delayed** is not included in
   `SpeciesData.isInferenceErrorPlaceholder`; and
4. the new connectivity tests throw from a pre-request consent seam, so they do
   not exercise URLSession retry, upload-hold release, or connectivity-driven
   retirement.

Until those gaps close, a user can still see a long **Analyzing** state, a late
**Network timeout**, or non-biological result treatment for a saved scan that
the queue still owns.

## Required Customer Contract

| Condition                                             | Presentation                                                                                 | Retry owner                               |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------- | ----------------------------------------- |
| Offline before live dispatch                          | Capture queues the scan and does not start provider transport                                | Durable queue                             |
| Connectivity changes during the 150 ms context grace  | Open Insight changes to **Queued for later**                                                 | Durable queue                             |
| First queue-backed transport failure after dispatch   | Same-ID Insight changes to **Queued for later** without an error haptic or synthetic result  | Durable queue; no inline transport replay |
| Queue-less direct request loses transport             | **Network timeout / Please try again** may be shown                                          | Caller                                    |
| Handler/provider returns an exhausted service failure | **Analysis delayed / Scan saved** as an error placeholder, never a biological classification | Durable queue                             |
| Background or status recovery completes the same UUID | Completed result replaces queued content in place                                            | Completed owner row                       |

The transport signal and the path monitor are advisory inputs, not competing
sources of customer truth. The stable queue row is the recovery authority. A
connectivity callback may retire provider ownership immediately, but that
retirement must not erase the still-current local presentation identity before
the exact-ID queued handoff is published.

## Root Cause

### Durable ownership and local presentation were coupled

`InferenceEngine.isLiveInferenceAttemptCurrent` requires both the local
presentation generation and the queue manager's foreground generation to be
current. When `OfflineQueueManager` observes an unsatisfied path, it calls
`releaseAllForegroundInferenceClaims`. Retirement synchronously registers the
generation in the retirement registry, making the full ownership check false
before URLSession necessarily returns.

The later `URLError` catch therefore exits at the stale-owner guard. Its defer
path can stop processing and clear active identity without publishing
`queuedPresentationScanId`. With no queued context, no `SpeciesData`, and
`isProcessing == false`, the open Insight can continue routing to analyzing
content with no state transition able to complete it.

The fix must distinguish these two authorities:

- **local presentation ownership** decides whether the exact still-open sheet
  may change to queued content; and
- **durable foreground ownership** decides whether provider results, failures,
  queue cleanup, telemetry, or retries may still commit.

A newer scan or completed same-ID result must invalidate the local presentation
before a delayed failure can act. Durable retirement alone must not prevent the
current sheet from acknowledging that the queue took over.

### Generic transport replay delays durable recovery

`identifyMultiModal` uses a 90-second request timeout and always sends a stable
idempotency key. The shared authenticated request helper currently retries
selected transient `URLError` values once after two seconds whenever ambiguous
replay is allowed. A black-holed Wi-Fi or captive path can therefore keep a
queue-backed scan in live analysis for approximately 182 seconds before the
engine sees the final error.

Queue-backed foreground Identify needs an explicit retry policy that returns the
first transport failure to the engine. The durable queue already owns later
retry and status recovery. This exception must be scoped to queue-backed live
Identify; it must not silently remove reviewed retry behavior from unrelated
read routes, server-route propagation recovery, or a truly queue-less caller.

### Error placeholder classification is string-fragile

The generic saved-service fallback constructs non-biological-shaped
`SpeciesData` titled **Analysis delayed**, but the placeholder whitelist does
not recognize that title. The row can therefore be classified as a genuine
non-biological result and receive the wrong pill, retention copy, haptic, or
success lifecycle.

The long-term contract should use typed presentation state. The minimum safe
repair must classify **Analysis delayed** as an inference error placeholder and
lock its Insight routing and lifecycle behavior in tests.

### Existing tests stop before the transport boundary

`queueBackedConnectivityFailuresUseQueuedPresentationForVisualAndNonVisual`
injects `URLError` through `overridingInferenceConsentCheck`. That hook runs
before request construction and URLSession dispatch. The test can prove only the
catch classifier under uninterrupted ownership; it cannot prove the customer
race described above.

Transport coverage must use `MockURLProtocol` or an equally narrow client seam
at the URLSession boundary. It must deliberately retire the foreground claim
before releasing the transport error to the engine.

## Closure Gates

This incident is closed only when one exact workflow SHA supplies all of the
following:

1. Visual and nonvisual queue-backed tests dispatch a real mocked request,
   release the body-upload hold, trigger connectivity retirement, and only then
   deliver `.networkConnectionLost`, `.notConnectedToInternet`, or `.timedOut`.
2. Both paths publish the exact `queuedPresentationScanId`, bind the matching
   durable row, route the open Insight to `.queued`, stop live processing, and
   emit no error placeholder, error haptic, network-circuit failure, or second
   provider request.
3. The durable queued scan survives; its deferred-upload hold and foreground
   generation eventually clear without test-only manual state repair; staged
   recovery can resume under the same scan UUID.
4. A deterministic request-count/timing assertion proves queue-backed transport
   failure does not enter the two-second inline replay or another 90-second
   request deadline.
5. A queue-less direct transport failure still produces the reviewed **Network
   timeout** recovery state.
6. Exhausted queue-backed `5xx`/provider failure produces **Analysis delayed /
   Scan saved**, is classified as an inference error placeholder, never emits
   non-biological success treatment, and leaves durable retry intact.
7. A completed background response or status-recovered record for the same ID
   replaces queued content in place; a stale failure cannot overwrite that
   completion or a newer scan.
8. The complete iOS unit-test target, protected critical scan-flow inventory,
   deterministic queued-scan completion UI smoke, and current-SHA Release
   archive all pass with zero failures or skipped required cases.
9. Physical-device QA covers airplane mode, Wi-Fi with no upstream internet,
   captive portal, Wi-Fi-to-cellular handoff, app backgrounding during upload,
   and reconnect. The saved scan must remain visible and complete exactly once.

## Validation Status at Review

The local review checkout was based on HEAD
`7a3190f9be8f2653f34f35724bb2e2ce46478399`. The connectivity-handoff source and
this documentation were uncommitted, so that base SHA by itself is not evidence
for either the attempted behavior or its closure.

The supplied hosted workflow evidence for source SHA
`5247c6a72606e7cb149fe0377a2b5e0dbe2cd069` reported 1,447 passed tests and one
failure:
`InferenceEngineTests/providerAdmissionFailuresStayOutOfNetworkCircuitForVisualAndNonVisual()`.
Its validation-only Release archive completed with the privacy manifest,
ATS-default transport posture, dSYM UUIDs, and Debug-marker checks satisfied.
That archive does not validate the later uncommitted connectivity-handoff work.

Local source parsing, strict production lint, workflow-contract checks, and diff
validation are useful construction evidence, but they do not close this
incident. The sandboxed local environment could not execute CoreSimulator or the
full Xcode test target, and the current pre-request connectivity test does not
reach the required boundary.

## Related Contracts

- [Scan Ingestion Reliability and Recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
- [Offline Sync Pipeline](../backend-and-data/01-offline-sync-pipeline.md)
- [Error Handling](../development-guides/06-error-handling.md)
- [AI Engineering](../system-architecture/04-ai-engineering.md)
- [Insight Sheet](../features-and-hardware/05-insight-sheet.md)
- [Core AI](../../apps/ios/Merian/Core/AI/README.md)
- [Core Network](../../apps/ios/Merian/Core/Network/README.md)
- [Capture Submission](../../apps/ios/Merian/Features/Capture/Submission/README.md)
- [Insight Content](../../apps/ios/Merian/Features/Insights/Content/README.md)
