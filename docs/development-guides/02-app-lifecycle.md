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
7. `OfflineQueueManager.replayInferenceForUploadedScans()` — re-enters any `OfflineQueuedScan` stuck in `.staged` or `.inferencing` state (upload confirmed but inference interrupted, e.g. app killed or suspended mid-inference). Also reconciles `.uploading` orphans back to `.pending` on every call so scans whose `generateUploadURLs` request failed mid-session are visible on the next retry. `NWPathMonitor` only fires on connectivity *changes*, so this call is required here to recover stuck scans when the app returns to foreground on an already-stable connection.
8. `ScanRepository.syncHistoricalScansDown(modelContext:)` — fetches paginated cloud history and reconciles against local SwiftData (supports reinstalls and multi-device access). **Throttled to once per 15 minutes** via `UserDefaults("lastHistoricalSyncDate")` to prevent redundant full-table network syncs on every foreground transition (e.g. returning from Control Center). The timestamp is stamped **before** the sync starts, not after — this is an optimistic lock that prevents two concurrent foreground handlers (e.g. the auth listener and the lifecycle manager) from both reading `distantPast` before either has written the timestamp, which would otherwise cause two simultaneous historical syncs.
9. **Archive Safety Protocol** (once per 24 hours via `UserDefaults("lastArchiveRescueDate")`): `ArchiveManager.evaluateAndRescueAgingScans(modelContext:)` — downloads images for Free-tier domesticated scans approaching the targeted 90-day edge function domesticated purge window (wild and invasive scans are permanently archived by the server).

---

### `handleInactivePhase()`

Triggered when `scenePhase == .inactive` (app switcher, incoming call overlay, system alerts, **iOS limited photo library access prompt**).

1. `CameraManager.stopSession()` — halts AVFoundation immediately to preserve thermal budget and release hardware resources.

> **Sheet dismissal is NOT performed on inactive.** System overlays — including the iOS limited photo library access prompt — transition the scene to `.inactive` without ever reaching `.background`. Closing sheets on inactive would cause the insight sheet to disappear behind the system prompt whenever a user with restricted photo library access completed a scan, requiring them to manually reopen results. Sheet dismissal is deferred to `handleBackgroundPhase()`.

---

### `handleBackgroundPhase()`

Triggered when `scenePhase == .background`.

Posts `.appDidEnterBackgroundPhase` via `AppEventPublisher` — consumed by `CameraViewModel` to call `resetModalsForBackground()`.

**Why sheets close on background (not inactive):**
The iOS scene lifecycle distinguishes two classes of interruption:
- **System overlays** (limited photo prompt, incoming call banner, Control Center): `active → inactive → active`. The user never leaves the app; the overlay dismisses and the app returns to full activity.
- **Leaving the app** (home screen, app switcher): `active → inactive → background`. Only this path reaches `.background`.

Firing `resetModalsForBackground` only on `.background` means the insight sheet survives the limited photo library prompt uninterrupted, while still closing correctly when the user genuinely leaves the app.

#### `CameraViewModel` background reset policy

`CameraViewModel.resetModalsForBackground()` handles the background notification with selective state preservation:

**Always reset (unconditionally):**
- `activeSheet`, `imageToCrop`, `editingCropIndex` — sheets hold UI locks and must not reopen stale.
**Conditionally preserved — governed by `shouldPreserveStagingOnBackground`:**
- `stagedCapture` (the `StagedCapture` value — `images: [StagedImage]` bundling compressed inference copy, 2048 px display copy, `UIImage` thumbnail, and full-resolution original) — cleared via `stagedCapture.clearAll()` when `shouldPreserveStagingOnBackground` returns `false`.

`shouldPreserveStagingOnBackground` is a private computed property that returns `true` when the user has images staged in the Active Scan Toolbar (`!stagedCapture.isEmpty`). This prevents a brief background trip (e.g. switching apps momentarily) from silently discarding the user's in-progress scan workflow.

To add new interrupt-sensitive states in the future, add a condition to `shouldPreserveStagingOnBackground` — the wipe path is already gated on it.

**Scan durability note:** This handler is a no-op for scan durability. Scans are made durable at submission time in `CameraViewModel.submitActiveScan` — the background URLSession upload is dispatched while the app is still in the foreground, before any async boundary is crossed. It does not cancel inference, enqueue captures, or modify `InferenceEngine` state.

**Why the old rescue pattern was removed:**
The previous architecture called `enqueueCapture` from `handleBackgroundPhase`, `CameraRootView.onChange(of: activeSheet)`, and `InsightSheetView.onDisappear`. All three paths were unreliable for the same structural reason: `Task(priority: .background)` tasks can be starved by the cooperative scheduler before `urlSession.uploadTask(...).resume()` is ever called if the process suspends within milliseconds. The `isSyncing` guard in `syncPendingScans` also silently dropped the rescue if a prior sync was in-flight. See `docs/development-guides/11-swiftdata-and-api-gotchas.md` §8 for the full analysis.

---

## Phase Ordering & Critical Rules

| Phase | Camera Session | Offline Queue | Inference |
|---|---|---|---|
| Active | Start | Drain (quota-gated for free) | Normal live path |
| Inactive | Stop | Untouched | Untouched — scan already queued |
| Background | Already stopped | No-op — upload already dispatched; sheet dismissal fires here | Live `inferenceTask` may still be running; background URLSession owns delivery if it completes first |

**Rules AI agents must follow:**
- **Never re-introduce rescue logic in `handleBackgroundPhase`.** Scans are enqueued in `submitActiveScan` before any async boundary. Rescue handlers re-added here will be unreliable for the same structural reasons the originals were — see §8 of `docs/development-guides/11-swiftdata-and-api-gotchas.md`.
- **Never start `AVCaptureSession` without verifying `scenePhase == .active`.** When UI sheets implicitly close during a background transition, they may emit state changes that inadvertently trigger `startSession()`. Firing a hardware start request into AVFoundation while suspended permanently deadlocks the video data queue on foreground return.
- **Never tie `AVCaptureSession` state to SwiftUI `.onAppear` or `.onDismiss` native sheet closures.** Because SwiftUI processes rapid View generation unpredictably, `.onAppear` closures embedded in sheets can fire out of sync with `.onDismiss` during fast presentation transitions. Always bind hardware interaction exactly 1:1 with the backing `@State` or `@Bindable` variable driving the UI via a deterministic `.onChange(of:)` hook (e.g., `.onChange(of: viewModel.activeSheet)`).
- **Never bypass the free user queue cap** in `enqueueCapture`. The cap is the primary defence against free-tier scan hoarding — do not remove or loosen it.
- **Never trigger the paywall from `InferenceEngine`'s catch block.** The paywall is only shown from the `canPerformScan` gate in `Capture.swift` and `handlePhotoPickerSelection`. Network failures must never surface a paywall.
- **Never add direct ViewModel references** to `AppLifecycleManager`. Use `NotificationCenter` for UI side-effects.
- `syncHistoricalScansDown` is throttled to once per 15 minutes. Do not add additional call sites without also checking `UserDefaults("lastHistoricalSyncDate")`.
- The Archive Safety Protocol runs at most once per 24-hour wall-clock period. Do not trigger it manually from other call sites.
- **Always call `replayInferenceForUploadedScans()` immediately after `syncPendingScans()` in `handleActivePhase()`.** `NWPathMonitor` only fires when connectivity changes, not when the app returns to foreground on an already-stable connection. Without this call, scans whose upload completed while the app was backgrounded are permanently stuck and never recovered. Do not remove this call or move it to a throttled path.
- All async work inside `handleActivePhase` is intentionally fire-and-forget (`Task {}`). Errors are logged but never surface to the user during a phase transition.
