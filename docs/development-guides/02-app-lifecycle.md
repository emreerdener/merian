# App Lifecycle Management

Merian centralizes all iOS phase-transition logic inside `AppLifecycleManager` (`Core/Utilities/AppLifecycleManager.swift`), a `@MainActor` class injected by `AppDIContainer`. This decouples lifecycle routing from the DI container itself and from individual ViewModels.

## Phase Contract

`handleActivePhase()` and `handleInactivePhase()` are guarded by `AppSettings.hasCompletedOnboarding`. If onboarding has not been completed, they return immediately — no notification sync, queue work, or camera stop calls are triggered. `handleBackgroundPhase()` is intentionally minimal and always records the background timestamp for later timeout evaluation.

---

### `handleActivePhase()`

Triggered by `MerianApp.swift` when `scenePhase == .active`.

**Synchronous triggers (Main thread):**
1. `UsageManager.evaluateDailyRefresh()` — resets daily scan token count if the calendar day has rolled over.
2. `PushNotificationManager.setupDelegate()` — re-registers the UNUserNotificationCenter delegate.
3. `PushNotificationManager.syncPermissionState()` — reconciles local notification settings with the OS authorization status to handle revocations in Settings.
4. `PushNotificationManager.registerForRemoteNotificationsIfAuthorized()` — re-registers APNs when the user has already granted notification access.
5. **Session timeout reconciliation:** reads `UserDefaultsKeys.lastBackgroundedDate`. If the app was backgrounded for more than 5 minutes, publishes `.appDidResumeAfterTimeout`, then clears the stored background timestamp.
6. `AppSettings.refreshFromDefaults()` — reconciles settings written by background delegates while SwiftUI was suspended.

Camera session startup is owned by `CaptureWorkspaceView` / `CaptureWorkspaceViewModel.handleScenePhaseChange`, not by `AppLifecycleManager`. `handleActivePhase()` should not directly start AVFoundation hardware.

**Deep links and intents:**
`MerianApp.handleMerianDeepLink(_:)`, `PushNotificationManager.handleNotificationAction(...)`, and App Intents publish typed `AppEventPublisher` events. `CaptureWorkspaceViewModel` consumes scan, Explore-post, and Species Dictionary events to present the appropriate sheet and stack route. Species events contain only the validated canonical dictionary UUID. `CaptureWorkspaceView` consumes identify/recall intent events that need to modify the pager or reuse current insight state.

**Photos document import:**
`MerianApp.onOpenURL` handles Google Sign-In and Merian deep links before
classifying file URLs, and leaves remaining URLs for Supabase authentication.
An accepted image is copied immediately into `ExternalImageImportStore`; only
then does the app publish `.externalImageImportAvailable`. The durable inbox,
not the transient `AppEvent`, is authoritative. `CaptureWorkspaceView` checks it
on appearance and every active transition so cold launch, onboarding, or an
event sent before the workspace subscribes cannot lose the photo. Capacity and
quota blocks retain the receipt. See
`docs/features-and-hardware/26-photos-share-import.md`.

**Fresh-launch Explore preference:**
`AppSettings.opensExploreOnLaunch` is default-off and sampled once when the app
process is created. After onboarding, an ordinary launch may initialize the
Capture workspace with the root Explore feed presented over it. Foreground
phase changes never resample the preference. Because the Capture workspace is
still the root, this is an initial sheet presentation rather than a second app
root or an architectural mode switch. Camera startup is suppressed while that
sheet is visible; dismissing it restores the configured Scan, Record, or
Describe mode. The Explore sheet's appearance also sets
`AppSettings.hasSeenExploreNewChip`.

Launch presentation precedence is:

1. A Photos/Files image handoff clears or dismisses generic Explore and
   continues into the durable pending-import staging and crop flow.
2. Deep links and tapped notifications replace generic Explore with their
   requested Explore post, Species Dictionary page, community request, scan
   Insight, or Scans library.
3. The generic Explore feed remains only when no explicit intent supersedes it.

When adding a new external route, clear any generic launch destination before
presenting the requested state and protect it from the same foreground timeout
event that accompanied the launch.

**Internal Cross-Sheet Routing:**
`AppEventPublisher` is also utilized for decoupled internal routing. For example, toast actions originating from the `InsightSheetViewModel` can dispatch specific intents (e.g., `.requestOpenNonBiologicalScansIntent`) that are captured by the `CaptureWorkspaceViewModel` and `ScansSheetView` to mutate root presentation states and push nested navigation views, completely avoiding tight coupling between sibling modal sheets.

**Async `Task {}` (off Main thread):**
1. `SupabaseManager.initializeGhostSession()` — ensures a valid anonymous or authenticated session exists before any network calls.
2. `PushNotificationManager.syncRemotePushRegistrationIfPossible(reason: "app_active")` — reconciles the current APNs token with the server when possible.
3. `OfflineQueueManager.purgeSoftDeletedRecords()` — removes local records that are safe to delete after sync.
4. `OfflineQueueManager.syncPendingScans()` — drains queued captures immediately if `NWPathMonitor` shows connectivity.
5. `OfflineQueueManager.replayInferenceForUploadedScans()` — re-enters any `OfflineQueuedScan` stuck in `.staged` or `.inferencing` state (upload confirmed but inference interrupted, e.g. app killed or suspended mid-inference). It polls `/check-scan-status` before resetting orphaned `.inferencing` scans: `found` scans are synced down, server-owned `processing` / `finalizing` jobs stay protected for another poll, retryable jobs respect `retry_after`, and true orphans return to `.staged`. It also reconciles `.uploading` orphans back to `.pending` on every call so scans whose `generateUploadURLs` request failed mid-session are visible on the next retry. `NWPathMonitor` only fires on connectivity *changes*, so this call is required here to recover stuck scans when the app returns to foreground on an already-stable connection.
6. `SpeciesPreferredNameRepository.syncCloudPreferences(modelContext:)` — reconciles preferred species names when a model context is available. Clean lifecycle/auth syncs skip when a successful sync completed in the last 60 seconds, while local set/clear edits force a follow-up sync.
7. `ScanRepository.purgeExpiredNonBiologicalScans(modelContainer:)` — removes local non-biological records older than `MerianConfig.nonBiologicalRetentionDays`, queues cloud-deletion tombstones, purges committed local media files, and kicks pending deletion sync. `NonBiologicalScansView` also invokes this on entry so stale rows clear immediately when the collection opens.
8. `ScanRepository.syncHistoricalScansDown(modelContext:)` — fetches paginated cloud history and reconciles against local SwiftData (supports reinstalls and multi-device access). **Throttled to once per 15 minutes** via `UserDefaultsKeys.lastHistoricalSyncDate` to prevent redundant full-table network syncs on every foreground transition. The timestamp is stamped **before** the sync starts, not after — this is an optimistic lock that prevents two concurrent foreground handlers from both reading `distantPast` before either has written the timestamp.

---

### `handleInactivePhase()`

Triggered when `scenePhase == .inactive` (app switcher, incoming call overlay, system alerts, **iOS limited photo library access prompt**).

1. `CameraManager.stopSession()` — halts AVFoundation immediately to preserve thermal budget and release hardware resources.

> **Sheet dismissal is NOT performed on inactive.** System overlays — including the iOS limited photo library access prompt — transition the scene to `.inactive` without ever reaching `.background`. Closing sheets on inactive would cause the insight sheet to disappear behind the system prompt whenever a user with restricted photo library access completed a scan, requiring them to manually reopen results. Stale sheet cleanup is deferred to the foreground session-timeout reset.

---

### `handleBackgroundPhase()`

Triggered when `scenePhase == .background`.

Records `UserDefaultsKeys.lastBackgroundedDate` so `handleActivePhase()` can evaluate the 5-minute session timeout on foreground. It does not directly dismiss sheets or mutate view models.

**Why timeout starts from background (not inactive):**
The iOS scene lifecycle distinguishes two classes of interruption:
- **System overlays** (limited photo prompt, incoming call banner, Control Center): `active → inactive → active`. The user never leaves the app; the overlay dismisses and the app returns to full activity.
- **Leaving the app** (home screen, app switcher): `active → inactive → background`. Only this path reaches `.background`.

Recording the background timestamp only on `.background` means the limited photo library prompt does not count as a session exit. The actual UI reset is deferred until the next `.active` transition and only fires if the user was away for more than 5 minutes.

#### `CaptureWorkspaceViewModel` session timeout reset policy

`CaptureWorkspaceViewModel.handleSessionTimeoutReset()` handles `.appDidResumeAfterTimeout` with selective state preservation:

**Always reset (unconditionally):**
- `activeSheet`, `pendingExplorePostId`, `imageToCrop`, `editingCropIndex` — sheets hold UI locks and must not reopen stale.

**Conditionally preserved — governed by `shouldPreserveStagingOnBackground`:**
- `stagedCapture` (the `StagedCapture` value — `images: [StagedImage]` bundling compressed inference copy, 2048 px display copy, bounded `UIImage` thumbnail, and crop/metadata bundle, plus staged video/audio/description items) plus pending required gallery crop routing. When `shouldPreserveStagingOnBackground` returns `false`, the reset uses `clearStagedCaptureAndCropState(discardStagedMediaFiles: true)` so temporary playback videos and companion WAV files are deleted instead of only dropping UI references.

`shouldPreserveStagingOnBackground` is a private computed property that returns `true` when the user has images staged in the Active Scan Toolbar (`!stagedCapture.isEmpty`). This prevents a brief background trip (e.g. switching apps momentarily) from silently discarding the user's in-progress scan workflow.

To add new interrupt-sensitive states in the future, add a condition to `shouldPreserveStagingOnBackground` — the wipe path is already gated on it.

#### External route timeout suppression

External routes can arrive at the same time as the foreground timeout reset. Widget taps, Explore activity pushes, and scan-result pushes should win over a stale camera reset when they are the direct reason the app opened.

Photos document imports use this short route-suppression deadline once the
workspace receives their event or confirms a durable pending receipt. The
durable inbox still protects the source image independently, while suppression
prevents the same foreground timeout from clearing the crop presentation after
the import is staged. The import also clears a generic launch-time Explore
sheet before beginning the Capture workflow.

`CaptureWorkspaceViewModel.protectExternalRouteFromImmediateSessionTimeoutReset()` creates a short one-shot suppression deadline when a scan, Explore post, or Species Dictionary deep link is handled. If `.appDidResumeAfterTimeout` arrives during that window, `handleSessionTimeoutReset()` consumes the suppression and skips the reset. This prevents the sequence `external URL -> activeSheet = .explore -> timeout reset -> activeSheet = nil`.

The suppression is intentionally narrow:
- It applies only to the next timeout reset after an external route.
- It is cleared whether it is consumed or expired.
- Ordinary stale sheets still clear on timeout.
- `resetModalsForSessionTimeout()` clears `pendingExplorePostId` and
  `pendingSpeciesDictionaryRoute`, preventing old external destinations from
  carrying into a later manual Explore open.

**Scan durability note:** This handler is a no-op for scan durability. Scans are made durable at submission time in `CaptureWorkspaceViewModel.submitActiveScan` — the background URLSession upload is dispatched while the app is still in the foreground, before any async boundary is crossed. It does not cancel inference, enqueue captures, or modify `InferenceEngine` state.

**Why the old rescue pattern was removed:**
The previous architecture called `enqueueCapture` from `handleBackgroundPhase`, `CaptureWorkspaceView.onChange(of: activeSheet)`, and `InsightSheetView.onDisappear`. All three paths were unreliable for the same structural reason: `Task(priority: .background)` tasks can be starved by the cooperative scheduler before `urlSession.uploadTask(...).resume()` is ever called if the process suspends within milliseconds. The `isSyncing` guard in `syncPendingScans` also silently dropped the rescue if a prior sync was in-flight. See `docs/development-guides/11-swiftdata-and-api-gotchas.md` §8 for the full analysis.

---

## Phase Ordering & Critical Rules

| Phase | Camera Session | Offline Queue | Inference |
|---|---|---|---|
| Active | Start | Drain (quota-gated for free) | Normal live path |
| Inactive | Stop | Untouched | Untouched — scan already queued |
| Background | Already stopped | No-op — upload already dispatched; timestamp recorded for timeout evaluation | Live `inferenceTask` may still be running; background URLSession owns delivery if it completes first |

**Rules AI agents must follow:**
- **Never re-introduce rescue logic in `handleBackgroundPhase`.** Scans are enqueued in `submitActiveScan` before any async boundary. Rescue handlers re-added here will be unreliable for the same structural reasons the originals were — see §8 of `docs/development-guides/11-swiftdata-and-api-gotchas.md`.
- **Never start `AVCaptureSession` without verifying `scenePhase == .active`.** When UI sheets implicitly close during a background transition, they may emit state changes that inadvertently trigger `startSession()`. Firing a hardware start request into AVFoundation while suspended permanently deadlocks the video data queue on foreground return.
- **Never tie `AVCaptureSession` state to SwiftUI `.onAppear` or `.onDismiss` native sheet closures.** Because SwiftUI processes rapid View generation unpredictably, `.onAppear` closures embedded in sheets can fire out of sync with `.onDismiss` during fast presentation transitions. Always bind hardware interaction exactly 1:1 with the backing `@State` or `@Bindable` variable driving the UI via a deterministic `.onChange(of:)` hook (e.g., `.onChange(of: viewModel.activeSheet)`).
- **Never bypass the free user queue cap** in `enqueueCapture`. The cap is the primary defence against free-tier scan hoarding — do not remove or loosen it.
- **Never trigger the paywall from `InferenceEngine`'s catch block.** The paywall is only shown from the `canPerformScan` gate in `Capture.swift` and `handlePhotoPickerSelection`. Network failures must never surface a paywall.
- **Never add direct ViewModel references** to `AppLifecycleManager`. Publish typed `AppEventPublisher` events for UI side effects that need to cross from lifecycle/services into SwiftUI.
- `syncHistoricalScansDown` is throttled to once per 15 minutes. Do not add additional call sites without also checking `UserDefaultsKeys.lastHistoricalSyncDate`.
- **Always call `replayInferenceForUploadedScans()` immediately after `syncPendingScans()` in `handleActivePhase()`.** `NWPathMonitor` only fires when connectivity changes, not when the app returns to foreground on an already-stable connection. Without this call, scans whose upload completed while the app was backgrounded are permanently stuck and never recovered. Do not remove this call or move it to a throttled path.
- All async work inside `handleActivePhase` is intentionally fire-and-forget (`Task {}`). Errors are logged but never surface to the user during a phase transition.

## 2026-04 Hardening Updates

- App startup now uses corruption-specific store recovery. A generic `ModelContainer` init failure is no longer treated as permission to delete the local SwiftData store.
- Recovery-first startup behavior is now: inspect store metadata, choose the
  narrowest safe `ModelContainer` strategy (current-store open, source-isolated
  recent migration plan, or full historical plan), inspect the error chain for
  SQLite/Core Data corruption signatures if opening fails, quarantine the store
  bundle only when corruption is confirmed, then retry container creation
  exactly once. Non-corrupt legacy migration failures archive the old store
  bundle under `store-rescue/` and open a fresh persistent store instead of
  looping in safe mode.
- `handleActivePhase()` continues to be the right place for replay recovery, but any new lifecycle work must not resurrect stale scan mutations. `InferenceEngine` now invalidates pending background writes whenever a scan is cancelled or a new scan begins.

## 2026-05 Startup Safety Update

- If the post-quarantine retry still cannot open the persistent store, startup now falls back to an in-memory `ModelContainer` and surfaces a recovery notice banner instead of crashing in a launch loop.
- Lifecycle code must tolerate this safe mode. Do not assume persistent storage was available just because the app reached `.active`.

## 2026-07 Startup Store-Recovery Guardrails

The full operating contract lives in `docs/backend-and-data/08-startup-store-recovery.md`.

- SwiftData/Core Data can raise Objective-C `NSException`s during `ModelContainer` initialization, which Swift `do/catch` cannot catch directly. `MerianApp` wraps container creation with a tiny Objective-C bridge so those launch-time exceptions become Swift errors and can enter the existing recovery path.
- Startup reads SwiftData store metadata before creating the persistent
  container. Fresh/current stores open without a migration plan, known recent
  stores use source-isolated V48/V47/V46/V45/V44/V43/V42 plans, and unknown
  older stores use the full historical plan. That full plan jumps V42→V49 or
  V43→V49 so SwiftData does not validate the duplicate-prone V44/V45/V46
  recent cluster during older-store migrations. V42/V43 use short direct plans
  to avoid validating older full-historical custom stages that can raise
  SwiftData's equal-model-reference exception. V46 is a no-op checksum twin of V45, so its
  recent plan keeps V46 as the only duplicate-cluster source representative and
  jumps directly to V49. V47 has its own source-isolated plan for stores already
  stamped V47.
  Duplicate-checksum failures retry through the same recent-plan ladder before
  legacy rescue or safe mode.
- Store quarantine remains corruption-only and is owned by `Core/Data/StoreRecovery/ModelStoreRecoveryCoordinator.swift`. Non-corrupt failures on legacy migration strategies archive `default.store`, `default.store-shm`, and `default.store-wal` under `store-rescue/`, then recreate a fresh persistent current-schema store. Generic current-store failures still boot safe mode without moving user data.
- Quarantine and rescue directories include `recovery-manifest.json` with app/build/OS metadata, archive reason, moved artifact names, and a sanitized error reason. This manifest is for support and debugging only; it must not include user IDs, paths outside the archive, access tokens, or profile data.
- Store recovery must never clear Keychain auth, Supabase sessions, device identity, profile state, or cloud ownership. Local SwiftData recovery is isolated from account identity so a damaged local library cannot sign a user out or orphan Explore posts.
- Recovery emits the coarse `StartupStoreRecovery` telemetry event after analytics initialization with only `outcome` and `reason`.
- Folder-level `README.md` files are documentation only. `project.yml` excludes markdown from the Merian target, and `make validate-ios-project` fails if generated Xcode resources start bundling markdown docs again.
