# Live Scan Connectivity Handoff Gap

**Date:** 2026-08-09\
**Severity:** Release-blocking scan-reliability risk\
**Affected boundary:** Queue-backed foreground Identify transport → durable
offline replay → open Insight presentation\
**Repository status:** Remediated in the current working tree; exact-SHA hosted
and physical-device acceptance remains open\
**Production status:** Do not describe the handoff as released until every
closure gate below passes on one exact workflow SHA

## Summary

Every submitted scan is durably queued before a live provider request begins.
That durability means a connectivity failure is not a terminal scan failure: the
foreground request should relinquish the uplink, the existing Insight should
change to **Queued for later**, and the durable queue should resume the same
scan UUID when transport is eligible.

The current source separates local presentation authority from durable provider
authority. Queue-backed live Identify disables the generic transient transport
replay, and the first URLSession connectivity failure moves only the exact
still-current sheet to queued content even if path monitoring already retired
the durable generation. That handoff releases the upload hold, does not advance
the provider/network circuit, retains the same durable row, and leaves
background recovery as the sole retry owner.

The regression now runs at the URLSession boundary for visual and nonvisual
submissions. It deliberately retires durable ownership while the request is
pending, then releases `.networkConnectionLost`,
`.notConnectedToInternet`, or `.timedOut` and proves exact-ID queued routing,
one request, bounded handoff timing, durable-row survival, and circuit
isolation. It also covers a transport-owned cancellation and a successful
response that becomes ownership-cancelled after the queue has already taken
over. Separate protected controls retain the reviewed queue-less retry and
**Network timeout** presentation and keep provider `5xx` failures in
**Analysis delayed / Scan saved**.

This is source-remediation evidence, not a production-release claim. Closure
still requires one exact workflow SHA and the physical connectivity matrix
below.

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

`identifyMultiModal` uses a 90-second request timeout and always sends a stable
idempotency key. The shared authenticated request helper formerly retried every
eligible transient `URLError` once after two seconds. A black-holed Wi-Fi or
captive path could therefore keep a queue-backed scan in live analysis for
approximately 182 seconds before the engine saw the final error.

The request helper now accepts an explicit transient-transport retry policy.
Queue-backed foreground Identify sets it to false and returns the first
transport failure to the engine because the durable queue owns later retry and
status recovery. The default remains true for reviewed queue-less callers;
authentication refresh, route-propagation recovery, and handler `5xx` behavior
remain independently scoped.

### Error placeholder classification was string-fragile

The generic saved-service fallback constructs non-biological-shaped
`SpeciesData` titled **Analysis delayed**. The former placeholder whitelist did
not recognize that title, so the row could be classified as a genuine
non-biological result and receive the wrong pill, retention copy, haptic, or
success lifecycle. The current source whitelist includes it.

The long-term contract should use typed presentation state. The minimum safe
repair now classifies **Analysis delayed** as an inference error placeholder,
and the protected queue-backed server-failure test locks that routing. Exact-SHA
workflow and device acceptance still apply to the joined source repair.

### The former test stopped before the transport boundary

The original
`queueBackedConnectivityFailuresUseQueuedPresentationForVisualAndNonVisual`
injected `URLError` through `overridingInferenceConsentCheck`, before request
construction and URLSession dispatch. It proved only the catch classifier under
uninterrupted ownership.

The replacement uses `MockURLProtocol` with a bounded gate. It observes the
first request, invokes the same upload-hold and foreground-claim retirement used
by the path monitor, waits for durable generation metadata to clear, and only
then releases the transport error. Companion network-client tests prove
queue-backed Identify returns after one request while the reviewed queue-less
path retains one stable-idempotency-key replay.

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
   deterministic live-Insight-to-queue and queued-scan-completion UI smokes,
   and current-SHA Release archive all pass with zero failures or skipped
   required cases.
9. Physical-device QA covers airplane mode, Wi-Fi with no upstream internet,
   captive portal, Wi-Fi-to-cellular handoff, app backgrounding during upload,
   and reconnect. The saved scan must remain visible and complete exactly once.

The current working tree addresses gates 1–7 in source and exact protected test
declarations. Its hosted workflow now requires both the open-live-sheet queue
transition and the queued-completion UI smokes as one exact two-case result set.
The incident remains open because gate 8 has not run from a clean commit
containing these changes and gate 9 requires physical-device evidence.

## Validation Status at Review

The current local review checkout is based on HEAD
`bd9087b566c0e4654f8be3b742d6cd87e035cb19`. The connectivity-handoff source,
critical-result inventory, and this documentation are still working-tree
changes, so that base SHA is not evidence for the remediation and cannot close
this incident.

The supplied hosted workflow evidence for source SHA
`5247c6a72606e7cb149fe0377a2b5e0dbe2cd069` reported 1,447 passed tests and one
failure:
`InferenceEngineTests/providerAdmissionFailuresStayOutOfNetworkCircuitForVisualAndNonVisual()`.
Its validation-only Release archive completed with the privacy manifest,
ATS-default transport posture, dSYM UUIDs, and Debug-marker checks satisfied.
That archive does not validate the later uncommitted connectivity-handoff work.

Local construction evidence for the current working tree is:

- all changed Swift files parse;
- the complete 418-file app module, 89-file `merianTests` target, and two-file
  `merianUITests` target type-check against the cached iOS Simulator SDK and
  package modules;
- strict lint reports no violation in the changed production files or newly
  added test lines;
- the critical-result validator harness and iOS build/workflow contract pass,
  with 91 exact protected iOS cases; and
- `git diff --check` and the reviewed Supabase-skill symlink check pass.

The sandbox cannot connect to CoreSimulatorService and SwiftPM's default user
cache is not writable, so it cannot execute the full Xcode unit target or UI
smoke locally. Those runs, the current-SHA Release archive, and physical-device
QA remain acceptance gates 8 and 9. The URLSession-level test now reaches the
required transport/retirement boundary, but it has not yet produced hosted
exact-SHA execution evidence.

The supplied `supabase_logs (1).csv` contains 76 auth/RPC rows, no Identify or
inference transport row, and no non-zero latency value. It therefore cannot
support an evidence-based reduction of the provider's first-response deadline.
The source repair removes the redundant second live transport attempt; the
no-upstream Wi-Fi and captive-portal device cases remain responsible for
measuring whether a separate foreground deadline is warranted.

## Related Contracts

- [Scan Ingestion Reliability and Recovery](../backend-and-data/16-scan-ingestion-reliability-and-recovery.md)
- [Offline Sync Pipeline](../backend-and-data/01-offline-sync-pipeline.md)
- [Error Handling](../development-guides/06-error-handling.md)
- [AI Engineering](../system-architecture/04-ai-engineering.md)
- [Insight Sheet](../features-and-hardware/05-insight-sheet.md)
- [Gamification and Telemetry](../features-and-hardware/03-gamification-and-telemetry.md)
- [Core AI](../../apps/ios/Merian/Core/AI/README.md)
- [Core Network](../../apps/ios/Merian/Core/Network/README.md)
- [Capture Submission](../../apps/ios/Merian/Features/Capture/Submission/README.md)
- [Insight Content](../../apps/ios/Merian/Features/Insights/Content/README.md)
