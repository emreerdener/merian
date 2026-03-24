# App Lifecycle Management

Merian centralizes all iOS phase-transition logic inside `AppLifecycleManager` (`Core/Utilities/AppLifecycleManager.swift`), a `@MainActor` class injected by `AppDIContainer`. This decouples lifecycle routing from the DI container itself and from individual ViewModels.

## Phase Contract

All three handlers are guarded by `UserDefaults("hasCompletedOnboarding")`. If onboarding has not been completed, every phase handler returns immediately — no sessions, timers, or background tasks are started.

---

### `handleActivePhase()`

Triggered by `MerianApp.swift` when `scenePhase == .active`.

**Synchronous triggers (Main thread):**
1. `CameraManager.startSession()` — resumes AVFoundation capture session.
2. `UsageManager.evaluateDailyRefresh()` — resets daily scan token count if the calendar day has rolled over.
3. `PushNotificationManager.setupDelegate()` — re-registers the UNUserNotificationCenter delegate.
4. `PushNotificationManager.syncPermissionState()` — reconciles local `@AppStorage("isPushNotificationsEnabled")` with the OS authorization status to handle revocations in Settings.

**Async `Task {}` (off Main thread):**
5. `SupabaseManager.initializeGhostSession()` — ensures a valid anonymous or authenticated session exists before any network calls.
6. `OfflineQueueManager.syncPendingScans()` — immediately drains queued captures if `NWPathMonitor` shows connectivity.
7. `ScanRepository.syncHistoricalScansDown(modelContext:)` — fetches paginated cloud history and reconciles against local SwiftData (supports reinstalls and multi-device access). **Throttled to once per 15 minutes** via `UserDefaults("lastHistoricalSyncDate")` to prevent redundant full-table network syncs on every foreground transition (e.g. returning from Control Center).
8. **Archive Safety Protocol** (once per 24 hours via `UserDefaults("lastArchiveRescueDate")`): `ArchiveManager.evaluateAndRescueAgingScans(modelContext:)` — downloads images for Free-tier scans approaching Cloudflare R2's 90-day lifecycle deletion window.

---

### `handleInactivePhase()`

Triggered when `scenePhase == .inactive` (app switcher, incoming call overlay).

1. `CameraManager.stopSession()` — halts AVFoundation to preserve thermal budget and release hardware resources.
2. Posts `NSNotification.Name("AppDidEnterInactivePhase")` — consumed by `CameraViewModel` (and other observers) to reset view state (e.g., dismiss result sheets) without directly coupling `AppLifecycleManager` to individual ViewModels.

> `CameraViewModel` intentionally **does not** nil out active ML payloads on this notification — that is reserved for `handleBackgroundPhase()` to prevent a race condition where UI cleanup runs before the background rescue can read the payload.

---

### `handleBackgroundPhase()`

Triggered when `scenePhase == .background`.

This phase handles the **mid-flight inference race condition**: if the user navigates away from the app while a scan is in progress, the behavior depends on subscription tier.

**Pro users — rescue via offline queue:**
1. Checks `InferenceEngine.isProcessing && !activeLiveCaptureDatas.isEmpty`.
2. Calls `OfflineQueueManager.enqueueCapture(imageDatas:telemetry:blurScore:)` with the live capture bytes and a `CaptureTelemetry` snapshot.
3. Calls `InferenceEngine.cancelActiveRequest()` — only after the enqueue call, guaranteeing zero data loss.
4. The offline queue's background URLSession handles the upload + inference + push notification independently of app state.

**Free users — complete in-flight naturally:**
1. Checks `InferenceEngine.isProcessing && !activeLiveCaptureDatas.isEmpty`.
2. The already in-flight URLSession request is **not cancelled**. iOS grants approximately 30 seconds of background execution time, which is sufficient for a typical edge inference (2–5 seconds).
3. When `InferenceEngine.analyze()` completes, `self.speciesData` is set and a push notification is dispatched if `UIApplication.shared.applicationState != .active` and `isPushNotificationsEnabled` is true.

> **Pro/Free distinction**: The Pro gate covers *offline queuing* (no-connectivity captures, re-queuing mid-flight scans for guaranteed delivery). Completing an already in-flight network request is available to all users.

---

## Phase Ordering & Critical Rules

| Phase | Camera Session | Offline Queue | Inference (Pro) | Inference (Free) |
|---|---|---|---|---|
| Active | Start | Drain | Normal | Normal |
| Inactive | Stop | Untouched | Untouched | Untouched |
| Background | Already stopped | Enqueue + cancel | Enqueue → cancel → URLSession handles | Let complete naturally in ~30s window |

**Rules AI agents must follow:**
- **Never cancel inference before enqueuing** in `handleBackgroundPhase` for Pro users. The ordering is enqueue → cancel, not cancel → enqueue.
- **Never cancel a free user's in-flight inference** in `handleBackgroundPhase`. Free users rely on the live inference task completing within iOS's background execution window. Cancelling it loses the scan with no recourse.
- **Never add direct ViewModel references** to `AppLifecycleManager`. Use `NotificationCenter` for UI side-effects.
- `syncHistoricalScansDown` is throttled to once per 15 minutes. Do not add additional call sites without also checking `UserDefaults("lastHistoricalSyncDate")`.
- The Archive Safety Protocol runs at most once per 24-hour wall-clock period. Do not trigger it manually from other call sites.
- All async work inside `handleActivePhase` is intentionally fire-and-forget (`Task {}`). Errors are logged but never surface to the user during a phase transition.
