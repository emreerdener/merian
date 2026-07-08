# Logging and Debugging

Merian uses Apple's unified `os.Logger` API via a centralized `MerianLog` namespace (`Core/MerianLog.swift`). This document explains which subsystem to use where, when to use `.debug` vs `.error`, how privacy specifiers work, and how to filter logs in Instruments or Console.

---

## The `MerianLog` Namespace

```swift
// Core/MerianLog.swift
import os

enum MerianLog {
    static let auth     = Logger(subsystem: "com.merian.app", category: "Auth")
    static let network  = Logger(subsystem: "com.merian.app", category: "Network")
    static let data     = Logger(subsystem: "com.merian.app", category: "Data")
    static let hardware = Logger(subsystem: "com.merian.app", category: "Hardware")
    static let exploreVideo = Logger(subsystem: "com.merian.app", category: "ExploreVideo")
    static let general  = Logger(subsystem: "com.merian.app", category: "General")
}
```

**Never use `print()` in production code.** `Logger` entries appear in Console.app and Instruments, are filterable by category, respect privacy specifiers, and have negligible performance overhead. `print()` does none of these. The codebase has been fully audited — there are no remaining `print()` calls outside of tests. Any new `print()` introduced during development must be replaced before merge.

---

## Subsystem Selection

| Subsystem | Use for |
|---|---|
| `MerianLog.auth` | `SupabaseManager` — sign in, Ghost sessions, JWT refresh, OAuth flows |
| `MerianLog.network` | `MerianNetworkClient` — HTTP requests, R2 uploads, Edge function calls, status codes |
| `MerianLog.data` | All SwiftData actors, `OfflineQueueManager`, `ScanRepository`, `FileIOActor`, `ArchiveManager` |
| `MerianLog.hardware` | `CameraManager` — AVFoundation locks, focus, torch, thermal states, video stabilization mode |
| `MerianLog.exploreVideo` | Explore public video playback — active player changes, sheet overlay pause/resume, player/layer rebuilds, recovery watchdogs |
| `MerianLog.general` | `InferenceEngine`, `CircuitBreakerManager`, `GamificationManager`, `PostHogManager`, `AppTelemetry`, everything else |

When in doubt, use `MerianLog.general`. Do not create new `Logger` instances outside of `MerianLog` — adding a new category requires updating the enum and this document.

---

## Log Level Selection

| Level | Method | When to use |
|---|---|---|
| Debug | `.debug(...)` | Expected paths, performance timings, state transitions that are useful during development. Stripped from production builds by the OS by default. |
| Info | `.info(...)` | Informational messages that should survive to production logs. Use sparingly. |
| Error | `.error(...)` | Any `catch` block where the failure represents a real problem (data loss risk, save failure, upload failure). Persists in production. |
| Fault | `.fault(...)` | Reserved for programmer errors / invariant violations. Do not use in data paths. |

**Rule: use `.error` in any `catch` that could cause data loss or inconsistency.** Use `.debug` for anything that is part of normal flow. The previous codebase used `.debug` for SwiftData save failures — those were upgraded to `.error` during the concurrency audit.

Startup store recovery is a production support path:

- Log the initial persistent-store failure as `.error`.
- Log a successful quarantine/retry as `.error` so it survives production log collection.
- Log a failed quarantine/retry as `.fault` because the app is entering safe mode after a verified corruption attempt.
- Never log full local store paths, tokens, user IDs, scan IDs, or profile data. The quarantine `recovery-manifest.json` is the support artifact for sanitized context.

---

## Privacy Specifiers

Every interpolated value in a `Logger` message must have an explicit `privacy:` label.

```swift
// Private — value is redacted in production logs
MerianLog.data.error("Save failed for scan \(scanId, privacy: .private): \(error, privacy: .private)")

// Public — value appears in production logs (safe for counts, statuses, durations)
MerianLog.data.debug("Reconciling \(allScans.count, privacy: .public) remote scans")

// Auto — redacted in non-development builds (default if omitted, but be explicit)
MerianLog.general.debug("Species: \(name, privacy: .auto)")
```

**Rules:**
- UUIDs, scan IDs, species names, GPS coordinates, user data → `.private`
- Counts, HTTP status codes, boolean flags, timing durations → `.public`
- Never log a raw `Error` without `privacy: .private` — error messages can contain user file paths or network URLs

---

## Reading Logs

### Console.app
1. Open Console.app → select the connected device
2. In the search bar, filter: `subsystem:com.merian.app`
3. Narrow by category: `subsystem:com.merian.app category:Data`

### Instruments (os_log)
1. Profile → Logging instrument
2. Filter by subsystem `com.merian.app`
3. Use category column to isolate the relevant layer

### Xcode Debug Console
During a debug build, all `.debug` messages appear in the Xcode console. To filter in the console output stream, use `subsystem` as a filter prefix.

### Runtime Log Triage

Some noisy lines come from Apple frameworks or third-party development configuration rather than Merian application faults:

| Log pattern | Meaning | Action |
|---|---|---|
| `FigCaptureSourceSimulator`, `FigCaptureSessionSimulator`, `FormatDescription` | AVFoundation simulator capture stack probing unavailable or synthetic camera formats. | Merian simulator builds use a no-preview camera path; investigate if these appear in a fresh build or if the preview is blank on physical devices. |
| `IOSurfaceClientSetSurfaceNotify failed` | Simulator/CoreAnimation surface notification failure. | Treat as simulator noise unless paired with a reproducible rendering failure. |
| `nw_connection_copy_connected_local_endpoint... no local endpoint` | Network framework inspected a socket before connection establishment completed. | Usually harmless; investigate only with request failures in `MerianLog.network`. |
| `PostHog identity buffered until SDK configuration completes` | Expected defensive path if identity arrives before setup in a future startup order. | Should be rare because Supabase configures PostHog before auth listening. |
| `AttributeGraph: cycle detected` | SwiftUI detected a state/layout feedback loop. | Investigate immediately. Layout measurements must be guarded by equality tolerances and deferred out of the active layout pass before writing `@State` or observable view-model state. |

---

## Explore Video Playback Triage

Explore feed/detail video playback logs use `MerianLog.exploreVideo`. In
Console.app or Instruments, filter with:

```text
subsystem:com.merian.app category:ExploreVideo
```

Useful event names:

| Event | Meaning |
|---|---|
| `active player=... surface=...` | The scoped coordinator selected the only Explore player that should be playing. Other visible players should pause after this. |
| `overlay began` / `overlay ended` | An Explore sheet or UIKit share surface changed the coordinator's overlay depth. Playback should resume only when depth returns to zero. |
| `pause-overlay` / `schedule-overlay-resume` | `ExplorePublicMediaView` converted a covering sheet into a recoverable interruption and queued a resume after dismissal. |
| `configure-rebuild` / `layer attach` / `layer dismantle` | The player or `AVPlayerLayer` was rebuilt. These should appear after sheet interruption recovery, not during ordinary healthy playback. |
| `status-change` | The underlying `AVPlayer.timeControlStatus` changed. Pair this with `pause-recoverable`, `unexpected-pause-confirmed`, or watchdog events. |
| `recovery-watchdog-passed` / `recovery-watchdog-failed` | The recovery attempt either reached `.playing` or left the visible play control as the user-facing recovery path. |
| `tap-repair-hidden-control` | A hidden, unhealthy video tap repaired/revealed playback instead of routing the feed card to detail. |

If a video freezes after a sheet closes, first check that every covering
Explore-hosted sheet owns exactly one
`.exploreVideoOverlayLifecycle(isPresented:reason:)` token, or that a UIKit
presenter ends the token returned by `beginOverlay(reason:)`. Do not reintroduce
global `NotificationCenter` playback notifications; nested sheet depth is what
keeps dismissal order deterministic.

---

## Performance Logging Pattern

Time-sensitive operations log their duration using `CFAbsoluteTimeGetCurrent()`:

```swift
let start = CFAbsoluteTimeGetCurrent()
// ... work ...
MerianLog.general.debug("⏱️ operation completed in \(String(format: "%.3f", CFAbsoluteTimeGetCurrent() - start), privacy: .public)s")
```

### Benchmark Timing (`[⏱ BENCH]`)

The inference pipeline emits structured `[⏱ BENCH]` markers at each stage to make latency breakdowns visible without an attached profiler. These use `.debug` level and are filtered by the prefix in the Xcode console or Console.app.

**iOS — `InferenceEngine.swift`** (filter in Xcode console: `⏱ BENCH`):

```
[⏱ BENCH] Pre-flight (encode+auth): 0.052s      ← base64 encode + auth headers
[⏱ BENCH] Post-flight (parse+save+state): 0.087s ← parseAndSave + awards + state commit
[⏱ BENCH] Total pipeline: 4.123s                 ← shutter to insight sheet
```

The existing `"Gemini inference completed in X.XXXs"` log (also `MerianLog.general`) captures the Gemini round-trip alone. The three `[⏱ BENCH]` lines bracket it so the pre-flight and post-flight overhead are separately visible.

**Edge Function — `identify/index.ts`** (Supabase Dashboard → Edge Functions → identify → Logs):

```
[⏱ BENCH] payload_resolved: 12ms    ← after base64 validation or R2 fetch
[⏱ BENCH] pre_gemini: 14ms          ← total overhead before Gemini call
[⏱ BENCH] gemini_done: 4203ms total, 4189ms inference
[⏱ BENCH] total_to_response: 4218ms
```

Note: `tier_resolved` does not appear in these logs — tier resolution runs in the background task after the response is sent and is not on the critical path.

---

## CircuitBreakerManager Logging

`CircuitBreakerManager` logs its state transitions via `MerianLog.general`:

```
CircuitBreakerManager: Circuit Tripped! Routing all network requests to local Field Queue.
CircuitBreakerManager: Circuit Reset. Resuming standard network requests.
```

If you see the "Circuit Tripped" message, it means 2+ consecutive network failures occurred. The circuit auto-resets after 15 minutes. During the tripped period, all new captures route directly to the offline queue — no network attempts are made.

---

## Comment Replies Diagnostic Tracing (`[RepliesDebug]` & `[UIRepliesDebug]`)

To troubleshoot thread hierarchies, race conditions, and network errors in the public comment replies ecosystem, we have integrated a structured double-layered tracing system that distinguishes between view model execution and SwiftUI view lifecycle triggers.

### 1. View Model Tracing (`[RepliesDebug]`)
These trace messages are emitted from the comments extension of `ExploreFeedViewModel` (`ExploreFeedViewModel+Comments.swift`) to capture network fetches, abort states, errors, and task cancellations.
- **Start**: `[RepliesDebug] loadReplies started for comment <ID>`
- **Abort Guard**: `[RepliesDebug] loadReplies aborted: already loading / loaded...`
- **Success**: `[RepliesDebug] loadReplies fetch successful: fetched <Count> replies`
- **Failure**: `[RepliesDebug] loadReplies failed with error: <Error>`
- **Task Cancellation**: `[RepliesDebug] loadReplies URLSession cancelled / task cancelled`

### 2. UI-Level Lifecycle Tracing (`[UIRepliesDebug]`)
These trace messages are emitted from the `.task` modifiers inside [ExplorePostDetailCommentsSection.swift](file:///Users/emreerdener/Developer/merian/apps/ios/Merian/Features/Explore/Feed/Components/ExplorePostDetailCommentsSection.swift) and [ExploreCommentsSheet.swift](file:///Users/emreerdener/Developer/merian/apps/ios/Merian/Features/Explore/Feed/Components/ExploreCommentsSheet.swift).
- **Task Start**: `[UIRepliesDebug] replyCountLabel task started for comment <ID>`
- **Task End (via `defer` block)**: `[UIRepliesDebug] replyCountLabel task ended for comment <ID> - isCancelled: <true/false>`

When debugging comments in Xcode's Console or the unified system Console.app, filter by `[RepliesDebug]` or `[UIRepliesDebug]` to observe real-time interaction logs. If any task prints `isCancelled: true` in an endless loop, it indicates that parent identity changes are forcing SwiftUI to tear down the view tree destructively.
