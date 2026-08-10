# Live Scan Connectivity Handoff Gap

**Date:** 2026-08-09\
**Severity:** Release-blocking scan-reliability risk\
**Affected boundary:** Queue-backed foreground Identify transport → durable
offline replay → open Insight presentation\
**Repository status:** Remediated in the current working tree; exact-SHA hosted
and physical-device acceptance remains open\
**Production status:** Do not describe the handoff as released until every
closure gate below passes, including one exact workflow SHA and the physical
device matrix

## Summary

Every submitted scan is durably queued before a live provider request begins.
That durability means a connectivity failure is not a terminal scan failure: the
foreground request should relinquish the uplink, the existing Insight should
change to **Queued for later**, and the durable queue should resume the same
scan UUID when transport is eligible.

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
pending before releasing `.networkConnectionLost` and
`.notConnectedToInternet`. Its `.timedOut` branch instead keeps the exact durable
owner active and the path online, modeling black-holed Wi-Fi reaching the
foreground deadline without an `NWPathMonitor` callback. Both branches prove
exact-ID queued routing, one request, bounded handoff timing, eventual durable
retirement, row survival, and circuit isolation. The matrix also covers a
transport-owned cancellation and a successful response that becomes
ownership-cancelled after the queue has already taken over. Separate protected
controls retain the reviewed queue-less 90-second window, retry, and **Network
timeout** presentation and keep provider `5xx` failures in **Analysis delayed /
Scan saved**.

This is source-remediation evidence, not a production-release claim. Closure
still requires one exact workflow SHA and the physical connectivity matrix
below.

## Required Customer Contract

| Condition                                             | Presentation                                                                                 | Retry owner                               |
| ----------------------------------------------------- | -------------------------------------------------------------------------------------------- | ----------------------------------------- |
| Offline before live dispatch                          | Capture queues the scan and does not start provider transport                                | Durable queue                             |
| Connectivity changes during the 150 ms context grace  | Open Insight changes to **Queued for later**                                                 | Durable queue                             |
| First queue-backed transport failure after dispatch   | Same-ID Insight changes to **Queued for later** without an error haptic or synthetic result  | Durable queue; no inline transport replay |
| Path stays satisfied but transport silently stalls    | Same-ID Insight changes to **Queued for later** by the 15-second foreground deadline          | Durable queue; exact-ID status/replay      |
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
callers retain the reviewed 90-second window and inline retry;
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

1. Visual and nonvisual queue-backed tests dispatch a real mocked request. The
   path-loss cases release the body-upload hold, trigger connectivity
   retirement, and only then deliver `.networkConnectionLost` or
   `.notConnectedToInternet`; a separate `.timedOut` case keeps path and durable
   ownership active until the transport deadline is delivered.
2. Both paths publish the exact `queuedPresentationScanId`, bind the matching
   durable row, route the open Insight to `.queued`, stop live processing, and
   emit no error placeholder, error haptic, network-circuit failure, or second
   provider request.
3. The durable queued scan survives; its deferred-upload hold and foreground
   generation eventually clear without test-only manual state repair; staged
   recovery can resume under the same scan UUID.
4. Deterministic request-policy, count, and timing assertions prove the
   queue-backed request carries the 15-second foreground bound, does not enter
   the two-second inline replay or a 90-second deadline, and hands presentation
   to the queue within 1.5 seconds after URLSession reports failure.
5. A queue-less direct transport failure still produces the reviewed **Network
   timeout** recovery state.
6. Exhausted queue-backed `5xx`/provider failure produces **Analysis delayed /
   Scan saved**, is classified as an inference error placeholder, never emits
   non-biological success treatment, and leaves durable retry intact.
7. A completed background response or status-recovered record for the same ID
   replaces queued content in place; a stale failure cannot overwrite that
   completion or a newer scan.
8. The complete iOS unit-test target, protected critical scan-flow inventory,
   deterministic live-Insight-to-queue and queued-scan-completion UI smokes, and
   current-SHA Release archive all pass with zero failures or skipped required
   cases. The live-sheet dismissal resolves `InsightSheetCloseButton` through
   the current `InsightSheetView`; a global `Close` label query is ambiguous
   when an underlying presentation remains in the accessibility tree.
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
`7111b2e56917788971ab798db85b59783d2ba5f0`. Hosted iOS Build and Test Run 226
passed all 1,465 unit tests and the queued-completion UI smoke. Its
validation-only Release archive also passed the privacy-manifest, ATS-default,
dSYM, and Debug-marker checks. The live-to-queue smoke reached the exact queued
message and every pre-dismissal assertion, then failed because the global
`app.buttons["Close"]` query matched both the active Insight close control and
an underlying close control.

The current working tree assigns `InsightSheetCloseButton` directly to the
native toolbar button and updates the smoke plus portable workflow contract to
require that identifier. Those changes still require a new hosted exact-SHA UI
run; Run 226 validates the behavior before dismissal but cannot validate the
selector correction.

Local construction evidence for the current working tree is:

- all changed Swift files parse;
- generated-project membership resolves 418 app target inputs, 89 unit-test
  sources, and two UI-test sources;
- the complete 417-file checked-in production Swift source set emits one
  testable app module against the cached iOS Simulator SDK and locked package
  modules; the generated-project guard separately accounts for the target's
  generated source input;
- the complete 89-file `merianTests` and two-file `merianUITests` source sets
  type-check against that exact current app module;
- the focused toolbar accessibility unit contract type-checks independently;
- strict no-cache lint reports zero violations across every changed production
  file and the smaller changed test files. The new hunks in the two large test
  files add no violation; their whole-file runs retain only known baseline debt
  outside this change (one large tuple in `InferenceEngineTests` and 31 legacy
  findings in `MerianNetworkClientTests`);
- the critical-result and focused-result validator harnesses plus the iOS
  build/workflow contract pass, with all 91 protected unit declarations and the
  exact two-case UI result requirement retained; and
- `git diff --check` passes.

Supabase Candidate Validation Run 1676 at
`fd1eb8dda7ff109ec339960104a49e577fa27f5b` correctly selected complete
validation because the push changed backend, iOS/schema, documentation, and
workflow/tooling inputs. It used no production environment, production secret,
or production mutation. Its disposable validation failed only after the
repository-tooling phase found two stale documentation expectations: the old
81-case protected inventory and the former singular queued-completion UI smoke.
The current tree updates those contracts to 91 cases and the exact two-smoke
set. The fail-closed candidate scope detector and complete Supabase tooling gate
now pass locally, including all 18 documentation contracts; all 262 migration
source assertions across 39 discovered files also pass. This repairs the
reported source/documentation gate but does not substitute for the workflow's
fresh disposable-database replay on one committed exact SHA.

The sandbox cannot reliably connect to CoreSimulatorService or apply SwiftPM's
nested build sandbox, so it cannot run the Xcode test bundle locally. Direct
compiler construction is not runtime evidence. A new hosted exact-SHA unit/UI
run and Release archive plus physical-device QA remain acceptance gates 8 and
9.

The supplied `supabase_logs (1).csv` contains 76 auth/RPC rows, no Identify or
inference transport row, and no non-zero latency value. It cannot establish a
production latency distribution. The checked-in rollout contract does provide
a cache-hit end-to-end p95 target of six seconds, so the current source uses a
conservative 15-second queue-owned foreground bound while retaining the
90-second direct-caller window. The no-upstream Wi-Fi and captive-portal device
cases must still measure actual tap-to-queue timing and verify that legitimate
slow completions recover under the same scan ID before this policy is released
or tuned further.

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
