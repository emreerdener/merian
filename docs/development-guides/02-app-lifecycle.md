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
7. `ScanRepository.syncHistoricalScansDown(modelContext:)` — fetches paginated cloud history and reconciles against local SwiftData (supports reinstalls and multi-device access).
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

This phase handles the **mid-flight inference rescue race condition**: if the user navigates away from the app while an inference is in progress, the capture must not be lost.

**Rescue sequence (Pro users only):**
1. Checks `InferenceEngine.isProcessing && !activeLiveCaptureDatas.isEmpty`.
2. Checks `RevenueCatManager.isProActive` — Free users do not get offline rescue.
3. Calls `OfflineQueueManager.enqueueCapture(imageDatas:telemetry:blurScore:)` with the live capture bytes and a `CaptureTelemetry` snapshot.
4. Calls `InferenceEngine.cancelActiveRequest()` — only after the enqueue completes, guaranteeing zero data loss.

If the device is not Pro or inference is not in-flight, nothing is written and the handler is a no-op.

---

## Phase Ordering & Critical Rules

| Phase | Camera Session | Offline Queue | Inference |
|---|---|---|---|
| Active | Start | Drain | Normal |
| Inactive | Stop | Untouched | Untouched |
| Background | Already stopped | Rescue in-flight capture | Cancel after enqueue |

**Rules AI agents must follow:**
- **Never cancel inference before enqueuing** in `handleBackgroundPhase`. The ordering is enqueue → cancel, not cancel → enqueue.
- **Never add direct ViewModel references** to `AppLifecycleManager`. Use `NotificationCenter` for UI side-effects.
- The Archive Safety Protocol runs at most once per 24-hour wall-clock period. Do not trigger it manually from other call sites.
- All async work inside `handleActivePhase` is intentionally fire-and-forget (`Task {}`). Errors are logged but never surface to the user during a phase transition.
