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
4. `PushNotificationManager.syncPermissionState()` — reconciles the local `@AppStorage(UserDefaultsKeys.isPushNotificationsEnabled)` flag with the OS authorization status to handle revocations in Settings.
5. **Deep Linking (Intents & Notifications):** `handleActivePhase` securely routes `MerianAppIntents.swift` triggers (Spotlight / Shortcuts) and Push Notification deep links by intercepting payload IDs and firing `AppEventPublisher.shared.send(.appDidEnterActivePhaseWithScan(scanId: scanId))`. This seamlessly injects modal presentation parameters universally across the codebase without causing race conditions against App init phases.

**Async `Task {}` (off Main thread):**
5. `SupabaseManager.initializeGhostSession()` — ensures a valid anonymous or authenticated session exists before any network calls.
6. `OfflineQueueManager.syncPendingScans()` — drains queued captures immediately if `NWPathMonitor` shows connectivity.
7. `OfflineQueueManager.replayInferenceForUploadedScans()` — re-enters any `OfflineQueuedScan` whose upload completed (`isUploaded == true`) but whose inference was interrupted before the scan was finalized (e.g. app killed or suspended mid-inference). `NWPathMonitor` only fires on connectivity *changes*, so this call is required here to recover stuck scans when the app returns to foreground on an already-stable connection.
8. `ScanRepository.syncHistoricalScansDown(modelContext:)` — fetches paginated cloud history and reconciles against local SwiftData (supports reinstalls and multi-device access). **Throttled to once per 15 minutes** via `UserDefaults("lastHistoricalSyncDate")` to prevent redundant full-table network syncs on every foreground transition (e.g. returning from Control Center).
9. **Archive Safety Protocol** (once per 24 hours via `UserDefaults("lastArchiveRescueDate")`): `ArchiveManager.evaluateAndRescueAgingScans(modelContext:)` — downloads images for Free-tier domesticated scans approaching the targeted 90-day edge function domesticated purge window (wild and invasive scans are permanently archived by the server).

---

### `handleInactivePhase()`

Triggered when `scenePhase == .inactive` (app switcher, incoming call overlay).

1. `CameraManager.stopSession()` — halts AVFoundation to preserve thermal budget and release hardware resources.
2. Posts `.appDidEnterInactivePhase` (`Notification.Name.appDidEnterInactivePhase`, defined in `Core/Utilities/NotificationNames.swift`) — consumed by `CameraViewModel` (and other observers) to reset view state without directly coupling `AppLifecycleManager` to individual ViewModels.

#### `CameraViewModel` background reset policy

`CameraViewModel.resetModalsForBackground()` handles the inactive notification with selective state preservation:

**Always reset (unconditionally):**
- `activeSheet`, `imageToCrop`, `editingCropIndex` — sheets hold UI locks and must not reopen stale.
**Conditionally preserved — governed by `shouldPreserveStagingOnBackground`:**
- `activeScannedDatas`, `activeScanImages`, `activeOriginals`, `activeDisplayDatas`, `selectedPhotoItems` — staged captures are only wiped when `shouldPreserveStagingOnBackground` returns `false`.

`shouldPreserveStagingOnBackground` is a private computed property that returns `true` when the user has images staged in the Active Scan Toolbar (`activeScanImages` is non-empty). This prevents a brief background trip (e.g. switching apps momentarily) from silently discarding the user's in-progress scan workflow.

To add new interrupt-sensitive states in the future, add a condition to `shouldPreserveStagingOnBackground` — the wipe path is already gated on it.

> `CameraViewModel` intentionally **does not** nil out active ML payloads on this notification — that is reserved for `handleBackgroundPhase()` to prevent a race condition where UI cleanup runs before the background rescue can read the payload.

---

### `handleBackgroundPhase()`

Triggered when `scenePhase == .background`.

This phase handles the **mid-flight inference race condition**: if the user navigates away from the app while a scan is in progress, the live request is cancelled and re-queued for all users via the background URLSession — guaranteeing reliable delivery and a push notification on completion.

**All users — rescue via offline queue:**
1. Checks `InferenceEngine.isProcessing && !activeLiveCaptureDatas.isEmpty`.
2. Calls `OfflineQueueManager.enqueueCapture(imageDatas:telemetry:blurScore:)` with the live capture bytes and a `CaptureTelemetry` snapshot.
3. Calls `InferenceEngine.cancelActiveRequest()` — only after the enqueue call, guaranteeing zero data loss.
4. The offline queue's background URLSession handles the upload + inference + push notification independently of app state.

Free users share the same path but are protected from scan hoarding by two enforcement layers in `OfflineQueueManager`:
- **Queue cap**: `enqueueCapture` refuses to add more than `UsageManager.shared.maxFreeScansPerDay` (2) items to the queue at once.
- **Quota gate at sync**: `syncPendingScans` checks `UsageManager.shared.canPerformScan(isProActive: false)` before processing any items and calls `consumeScan()` for each item submitted, so the daily limit is enforced even when scans complete via background URLSession.

---

## Phase Ordering & Critical Rules

| Phase | Camera Session | Offline Queue | Inference (All users) |
|---|---|---|---|
| Active | Start | Drain (quota-gated for free) | Normal |
| Inactive | Stop | Untouched | Untouched |
| Background | Already stopped | Enqueue + cancel | Enqueue → cancel → URLSession handles |

**Rules AI agents must follow:**
- **Never cancel inference before enqueuing** in `handleBackgroundPhase`. The ordering is enqueue → cancel, not cancel → enqueue.
- **Never start `AVCaptureSession` without verifying `scenePhase == .active`.** When UI sheets implicitly close during a background transition, they may emit state changes that inadvertently trigger `startSession()`. Firing a hardware start request into AVFoundation while suspended permanently deadlocks the video data queue on foreground return.
- **Never tie `AVCaptureSession` state to SwiftUI `.onAppear` or `.onDismiss` native sheet closures.** Because SwiftUI processes rapid View generation unpredictably, `.onAppear` closures embedded in sheets can fire out of sync with `.onDismiss` during fast presentation transitions. Always bind hardware interaction exactly 1:1 with the backing `@State` or `@Bindable` variable driving the UI via a deterministic `.onChange(of:)` hook (e.g., `.onChange(of: viewModel.activeSheet)`).
- **Never bypass the free user queue cap** in `enqueueCapture`. The cap is the primary defence against free-tier scan hoarding — do not remove or loosen it.
- **Never trigger the paywall from `InferenceEngine`'s catch block.** The paywall is only shown from the `canPerformScan` gate in `Capture.swift` and `handlePhotoPickerSelection`. Network failures must never surface a paywall.
- **Never add direct ViewModel references** to `AppLifecycleManager`. Use `NotificationCenter` for UI side-effects.
- `syncHistoricalScansDown` is throttled to once per 15 minutes. Do not add additional call sites without also checking `UserDefaults("lastHistoricalSyncDate")`.
- The Archive Safety Protocol runs at most once per 24-hour wall-clock period. Do not trigger it manually from other call sites.
- **Always call `replayInferenceForUploadedScans()` immediately after `syncPendingScans()` in `handleActivePhase()`.** `NWPathMonitor` only fires when connectivity changes, not when the app returns to foreground on an already-stable connection. Without this call, scans whose upload completed while the app was backgrounded are permanently stuck: `fetchPendingScans` filters them out (`isUploaded == false` predicate) and the connectivity handler never fires for them. Do not remove this call or move it to a throttled path.
- All async work inside `handleActivePhase` is intentionally fire-and-forget (`Task {}`). Errors are logged but never surface to the user during a phase transition.
