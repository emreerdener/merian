# App Lifecycle Management

Merian centralizes all iOS phase-transition logic inside `AppLifecycleManager`
(`Core/Utilities/AppLifecycleManager.swift`), a `@MainActor` class injected by
`AppDIContainer`. This decouples lifecycle routing from the DI container itself
and from individual ViewModels.

## Phase Contract

`handleActivePhase()` and `handleInactivePhase()` are first guarded by
`AppSettings.hasCompletedOnboarding`. If onboarding has not been completed, they
return immediately. After that legacy routing gate, the active handler always
schedules `ConsentManager.synchronizeWithCurrentSession()` so a closed required
gate can hydrate account evidence or retry an offline withdrawal. All hardware,
notification, usage, and queued provider work remains guarded by current adult,
Terms, and Gemini consent. The inactive handler stops the camera after the
onboarding guard. `handleBackgroundPhase()` is intentionally minimal and always
records the background timestamp for later timeout evaluation.

The account-switch synchronization, Realtime retry ownership, OAuth analytics
suppression, and adjacent consent test defects are closed in source. Hosted
exact-SHA iOS and validation-only Supabase execution remain pending; the
production exit evidence is canonical in the
[consent readiness record](../legal/production-consent-readiness-2026-08-03.md).

---

## Cold-Launch Root Presentation

Scene-phase handling and root presentation are separate contracts. `MerianApp`
evaluates `AppRootPresentationPolicy` before mounting either the onboarding flow
or Capture workspace:

1. Incomplete onboarding presents `OnboardingView` immediately.
2. Completed onboarding plus current required consent presents
   `CaptureWorkspaceView`.
3. Completed onboarding plus missing local evidence presents
   `ConsentRestorationView` while `ConsentManager` is awaiting the initial auth
   result, waiting for an expired cached session to refresh, reconciling the
   restored account, or holding an automatic/explicit retry.
4. An authoritative initial result with no active session presents onboarding at
   `.ready`. For an authenticated account, a successful merge presents `.ready`
   when evidence is absent or opens the workspace when evidence is restored.

`ConsentRestorationView` matches the black launch screen and waits 350
milliseconds before showing an accessible progress indicator. It prevents a
completed user from seeing actionable approval controls for a fraction of a
second while account evidence loads. Supabase's immediate local-session event
may contain a known user with an expired access token; `SupabaseManager` keeps
that user attached to consent restoration while leaving authenticated request
state closed. Only the subsequent `tokenRefreshed` or `signedOut` event may
advance the root. A non-cancellation reconciliation failure retains this neutral
root, shows an immediate retry action, and enters a bounded 5-, 10-, then
20-second account-fenced retry schedule. Exhaustion keeps the explicit retry
action visible; it does not treat the failure as authoritative absence.
Cancellation caused by account/session replacement keeps the transition pending
until the replacement is evaluated. If invalidation cancels a scheduled retry
for the same unresolved account, the state returns to `.reconciling` under the
new synchronization generation rather than leaving an orphaned `.waitingToRetry`
state.

This presentation policy does not weaken the phase contract below. Hardware,
provider requests, ordinary sync, and queued work still require both completed
onboarding and current required consent.

The phase gate is local and intentionally not the final provider authority.
Before the first or any later Identify request is built,
`ConsentManager.ensureCloudConsentForInference()` pushes pending account
evidence and requires a fresh remote adult/Terms/Gemini-head proof. Exact
`403 ai_consent_required` durably closes only the affected account, preserves
queued media, stops automatic inference retry, and returns the root through
restoration to Ready. It is not a quota-exhaustion transition and does not run
the paywall or daily-limit lifecycle path.

---

### `handleActivePhase()`

Triggered by `MerianApp.swift` when `scenePhase == .active`.

After current required consent passes, the handler runs these **synchronous
triggers (Main thread):**

1. `UsageManager.evaluateDailyRefresh()` — resets daily scan token count if the
   calendar day has rolled over.
2. `PushNotificationManager.setupDelegate()` — re-registers the
   UNUserNotificationCenter delegate.
3. `PushNotificationManager.syncPermissionState()` — reconciles local
   notification settings with the OS authorization status to handle revocations
   in Settings.
4. `PushNotificationManager.registerForRemoteNotificationsIfAuthorized()` —
   re-registers APNs when the user has already granted notification access.
5. **Session timeout reconciliation:** reads
   `UserDefaultsKeys.lastBackgroundedDate`. If the app was backgrounded for more
   than 5 minutes, publishes `.appDidResumeAfterTimeout`, then clears the stored
   background timestamp.
6. `AppSettings.refreshFromDefaults()` — reconciles settings written by
   background delegates while SwiftUI was suspended.

Camera session startup is owned by `CaptureWorkspaceView` /
`CaptureWorkspaceViewModel.handleScenePhaseChange`, not by
`AppLifecycleManager`. `handleActivePhase()` should not directly start
AVFoundation hardware.

Before any ordinary active-phase work, the app root checks the identity-free
`pendingLocalAccountDeletionCleanup.v1` barrier. A backend-accepted deletion
uses capability preparation, intake, cleanup, and retirement phases. Before the
first request suspension, iOS atomically read-after-write verifies distinct
recovery and acknowledgement capabilities in device-only Keychain. It records
`capability_preparation_pending`, calls the non-destructive server prepare,
records `capability_prepared_pending`, and then records
`capability_intake_pending` before destructive commit. It keeps the exact cached
session solely so that JWT-derived, idempotent commit can be replayed after a
crash or lost response. Both preparation markers are admitted back into that
single deletion-owned recovery transition on relaunch; every other SDK Auth
event, background sync, OAuth callback, and scene-phase operation remains
closed. A successful or publicly
recovered receipt advances to `capability_cleanup_pending`, which authorizes
verified local sign-out and SwiftData purge. Acknowledgement then advances to
`capability_retirement_pending`; verified proof removal precedes marker removal.
Retirement relaunches re-run verified local sign-out and idempotent purge before
proof removal.
Launch and foreground show a blocking recovery surface and retry with bounded
backoff. Only explicit `409 purchase_continuity_pending` may retire an
unaccepted intent. The app first persists
`capability_rejection_retirement_pending`, then verifies removal of the unused
Keychain proof before clearing the barrier. Relaunch in that phase never signs
out or purges local data. Legacy unknown proofs and all ambiguous failures retain
both authority and barrier. A v2 `not_committed` or genuinely unknown proof
definitively retires only the unused intent; before ordinary lifecycle work
reopens, it verifies proof retirement, adopts the same cached unexpired session
into the transition coordinator while the barrier is still present, clears the
barrier, and only then republishes that session. The UUID and anonymous/account
kind must match exactly. A tombstoned expired preparation
retired during another device's commit is non-authorizing and retains the
barrier. Only a server-matched expired committed capability permits
conservative local erasure.
Legacy `intake_pending` and `cleanup_pending` remain readable. This prevents a
terminated deletion from restoring the source account or later erasing a newly
signed-in account's cache.

At runtime, Apple, Google, Sign out, anonymous bootstrap, 401 recovery, and
deletion share one Auth-transition owner. Ordinary account-bound work acquires
an exact-session lease before direct Supabase or authenticated HTTP I/O. A
transition closes new admission, cancels/awaits consent synchronization, drains
`InferenceEngine` presentation/metadata tasks (including cancellation-ignoring
tails), collection work, and every lease, then changes the SDK session. Background
upload and inference tasks are terminal-owned rather than resume-owned: their
Auth UUID and generation are persisted in both job metadata and versioned task
descriptions, their leases remain held until terminal callbacks, and the drain
restages rows/clears source object keys before cancellation. Relaunched or late
callbacks require the same durable owner and live session; unknown legacy tasks
fail closed and cannot be adopted by a replacement account. Consent and
Explore Realtime channels close for the transition and restart only after the
verified final account is installed. This makes scene activation and background
completion safe even when they coincide with a provider sheet or sign-out.
Every terminal delegate callback registers its asynchronous persistence work
synchronously before hopping actors. `urlSessionDidFinishEvents` waits for that
tracker to become idle before taking and invoking the system completion handler,
so iOS cannot suspend the process between network completion and the durable
queue/result update.

The app root separately restores `pendingManualAppleRevocationNotice.v1` on
appearance and every active transition. That non-sensitive flag is written
before a legacy Apple account signs out, so authentication teardown and local
database purge cannot erase the customer instruction. Opening Apple's support
page dismisses the current alert but leaves the flag pending; returning to the
foreground presents it again. Only the explicit **I Revoked Access** action
resolves it.

This restoration path exists only in supporting binaries. Older clients can
ignore the server's manual-revocation disposition, so public promotion requires
the minimum-supported-build or independent server-delivery control defined by
the
[canonical Sign in with Apple deletion contract](../backend-and-data/20-sign-in-with-apple-account-deletion.md).

**Deep links and intents:** `MerianApp.handleMerianDeepLink(_:)`,
`PushNotificationManager.handleNotificationAction(...)`, and App Intents enqueue
typed `AppRoute` values in `AppRouteCoordinator`. `CaptureWorkspaceViewModel`
claims each route and applies it through the single root presentation host.
Species routes contain only the validated canonical dictionary UUID. Identify
and recall intents use the same queue rather than a separate event subscriber.

**Photos document import:** `MerianApp.onOpenURL` handles Google Sign-In and
Merian deep links before classifying file URLs, and leaves remaining URLs for
Supabase authentication. An accepted image is copied immediately into
`ExternalImageImportStore`; only then does the app request
`AppRoute.processExternalImageImports` with the `durableExternalImport` source.
The durable inbox, not the process-local route envelope, is authoritative.
`CaptureWorkspaceView` also checks the inbox on appearance and every active
transition so cold launch, onboarding, or a request sent before the workspace
mounts cannot lose the photo. Capacity and quota blocks retain the receipt. See
`docs/features-and-hardware/26-photos-share-import.md`.

**Fresh-launch Explore preference:** `AppSettings.opensExploreOnLaunch` is
default-off and sampled once when the app process is created. After onboarding
and current required consent, an ordinary launch may initialize the Capture
workspace with the root Explore feed presented over it. Foreground phase changes
never resample the preference. Because the Capture workspace is still the root,
this is an initial sheet presentation rather than a second app root or an
architectural mode switch. Camera startup is suppressed while that sheet is
visible; dismissing it restores the configured Scan, Record, or Describe mode.

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

**Internal cross-sheet routing:** Cross-module navigation uses
`AppRouteCoordinator`, including Insight actions that open refinement,
non-biological scans, Scans Library, Field trips, or an achievement detail. If a
root sheet is occupied, the coordinator records a deferral, dismisses that
presentation, and resumes the same request from the sheet's `onDismiss`; no
fixed animation sleep or sibling root sheet is used. Feature-local Capture
editors and covers also defer the route, but are allowed to finish normally;
their exact `onDismiss` requeues it. Supabase marks only its `initialSession`
event as cold restoration, so interactive sign-in cannot adopt private launch
routes from a prior account generation. Loss-tolerant cache invalidations
continue to use `AppEventPublisher`. See
[Event and Presentation Routing](../system-architecture/10-event-and-presentation-routing.md).

**Async tasks:**

1. Before the required-consent guard,
   `ConsentManager.synchronizeWithCurrentSession()` reconciles local and account
   evidence. It must remain session-bound after every suspension point and must
   push target-owned pending rows in the same synchronization pass.
2. After the guard, `AppIconBadgeCoordinator` refreshes the Explore unread count
   and `PushNotificationManager.syncRemotePushRegistrationIfPossible` reconciles
   APNs state.
3. `OfflineQueueManager.purgeSoftDeletedRecords()` removes safe local records.
4. When a model context exists, preferred-name sync, expired non-biological
   purge, and throttled historical scan download run. Historical sync stamps the
   15-minute throttle before starting to prevent concurrent foreground handlers.
5. `OfflineJobScheduler.drainRunnableJobs(using:)` drains work and recreates the
   next process-local wake from durable retry dates. This scheduler owns pending
   upload and interrupted-inference replay; the lifecycle manager no longer
   calls `syncPendingScans()` or `replayInferenceForUploadedScans()` directly.

Lifecycle tests must provide current required consent before expecting any work
after item 1. The old onboarding-complete flag alone now intentionally returns
before queue replay.

---

### `handleInactivePhase()`

Triggered when `scenePhase == .inactive` (app switcher, incoming call overlay,
system alerts, **iOS limited photo library access prompt**).

1. `CameraManager.stopSession()` — halts AVFoundation immediately to preserve
   thermal budget and release hardware resources.

> **Sheet dismissal is NOT performed on inactive.** System overlays — including
> the iOS limited photo library access prompt — transition the scene to
> `.inactive` without ever reaching `.background`. Closing sheets on inactive
> would cause the insight sheet to disappear behind the system prompt whenever a
> user with restricted photo library access completed a scan, requiring them to
> manually reopen results. Stale sheet cleanup is deferred to the foreground
> session-timeout reset.

---

### `handleBackgroundPhase()`

Triggered when `scenePhase == .background`.

Records `UserDefaultsKeys.lastBackgroundedDate` so `handleActivePhase()` can
evaluate the 5-minute session timeout on foreground. It does not directly
dismiss sheets or mutate view models.

**Why timeout starts from background (not inactive):** The iOS scene lifecycle
distinguishes two classes of interruption:

- **System overlays** (limited photo prompt, incoming call banner, Control
  Center): `active → inactive → active`. The user never leaves the app; the
  overlay dismisses and the app returns to full activity.
- **Leaving the app** (home screen, app switcher):
  `active → inactive → background`. Only this path reaches `.background`.

Recording the background timestamp only on `.background` means the limited photo
library prompt does not count as a session exit. The actual UI reset is deferred
until the next `.active` transition and only fires if the user was away for more
than 5 minutes.

#### `CaptureWorkspaceViewModel` session timeout reset policy

`CaptureWorkspaceViewModel.handleSessionTimeoutReset()` handles
`.appDidResumeAfterTimeout` with selective state preservation:

**Always reset (unconditionally):**

- `activeSheet`, `pendingExplorePostId`, `imageToCrop`, `editingCropIndex` —
  sheets hold UI locks and must not reopen stale.

**Conditionally preserved — governed by `shouldPreserveStagingOnBackground`:**

- `stagedCapture` (the `StagedCapture` value — `images: [StagedImage]` bundling
  compressed inference copy, 2048 px display copy, bounded `UIImage` thumbnail,
  and crop/metadata bundle, plus staged video/audio/description items) plus
  pending required gallery crop routing. When
  `shouldPreserveStagingOnBackground` returns `false`, the reset uses
  `clearStagedCaptureAndCropState(discardStagedMediaFiles: true)` so temporary
  playback videos and companion WAV files are deleted instead of only dropping
  UI references.

`shouldPreserveStagingOnBackground` is a private computed property that returns
`true` when the user has images staged in the Active Scan Toolbar
(`!stagedCapture.isEmpty`). This prevents a brief background trip (e.g.
switching apps momentarily) from silently discarding the user's in-progress scan
workflow.

To add new interrupt-sensitive states in the future, add a condition to
`shouldPreserveStagingOnBackground` — the wipe path is already gated on it.

#### External route timeout suppression

External routes can arrive at the same time as the foreground timeout reset.
Widget taps, Explore activity pushes, and scan-result pushes should win over a
stale camera reset when they are the direct reason the app opened.

Photos document imports use this short route-suppression deadline once the
workspace receives their event or confirms a durable pending receipt. The
durable inbox still protects the source image independently, while suppression
prevents the same foreground timeout from clearing the crop presentation after
the import is staged. The import also clears a generic launch-time Explore sheet
before beginning the Capture workflow.

`CaptureWorkspaceViewModel.protectExternalRouteFromImmediateSessionTimeoutReset()`
creates a short one-shot suppression deadline when a scan, Explore post, or
Species Dictionary deep link is handled. If `.appDidResumeAfterTimeout` arrives
during that window, `handleSessionTimeoutReset()` consumes the suppression and
skips the reset. This prevents the sequence
`external URL -> activeSheet = .explore -> timeout reset -> activeSheet = nil`.

The suppression is intentionally narrow:

- It applies only to the next timeout reset after an external route.
- It is cleared whether it is consumed or expired.
- Ordinary stale sheets still clear on timeout.
- `resetModalsForSessionTimeout()` clears `pendingExplorePostId` and
  `pendingSpeciesDictionaryRoute`, preventing old external destinations from
  carrying into a later manual Explore open.

**Scan durability note:** This handler is a no-op for scan durability. Scans are
made durable at submission time in `CaptureWorkspaceViewModel.submitActiveScan`
— the background URLSession upload is dispatched while the app is still in the
foreground, before any async boundary is crossed. It does not cancel inference,
enqueue captures, or modify `InferenceEngine` state.

**Why the old rescue pattern was removed:** The previous architecture called
`enqueueCapture` from `handleBackgroundPhase`,
`CaptureWorkspaceView.onChange(of: activeSheet)`, and
`InsightSheetView.onDisappear`. All three paths were unreliable for the same
structural reason: `Task(priority: .background)` tasks can be starved by the
cooperative scheduler before `urlSession.uploadTask(...).resume()` is ever
called if the process suspends within milliseconds. The `isSyncing` guard in
`syncPendingScans` also silently dropped the rescue if a prior sync was
in-flight. See `docs/development-guides/11-swiftdata-and-api-gotchas.md` §8 for
the full analysis.

---

## Phase Ordering & Critical Rules

| Phase      | Camera Session  | Offline Queue                                                                | Inference                                                                                            |
| ---------- | --------------- | ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Active     | Start           | Drain (quota-gated for free)                                                 | Normal live path                                                                                     |
| Inactive   | Stop            | Untouched                                                                    | Untouched — scan already queued                                                                      |
| Background | Already stopped | No-op — upload already dispatched; timestamp recorded for timeout evaluation | Live `inferenceTask` may still be running; background URLSession owns delivery if it completes first |

**Rules AI agents must follow:**

- **Never re-introduce rescue logic in `handleBackgroundPhase`.** Scans are
  enqueued in `submitActiveScan` before any async boundary. Rescue handlers
  re-added here will be unreliable for the same structural reasons the originals
  were — see §8 of `docs/development-guides/11-swiftdata-and-api-gotchas.md`.
- **Never start `AVCaptureSession` without verifying `scenePhase == .active`.**
  When UI sheets implicitly close during a background transition, they may emit
  state changes that inadvertently trigger `startSession()`. Firing a hardware
  start request into AVFoundation while suspended permanently deadlocks the
  video data queue on foreground return.
- **Do not treat a presentation binding becoming `nil` as proof that UIKit has
  released the camera presentation slot.** Stop the session when observed
  root/local presentation state becomes occupied. During dismissal,
  `isRootPresentationDismissing` prevents an early restart; the exact root or
  feature-local `onDismiss` may restore the session only after rechecking visual
  Capture mode, `scenePhase == .active`, no remaining presentation, and no
  in-flight or queued route. Ordinary non-presentation hardware state still
  follows deterministic `.onChange(of:)` observation.
- **Never bypass the free user queue cap** in `enqueueCapture`. The cap is the
  primary defence against free-tier scan hoarding — do not remove or loosen it.
- **Never trigger the paywall from `InferenceEngine`'s catch block.** The
  paywall is only shown from the `canPerformScan` gate in `Capture.swift` and
  `handlePhotoPickerSelection`. Network failures must never surface a paywall.
- **Never add direct ViewModel references** to `AppLifecycleManager`. Send a
  loss-tolerant `AppEvent` for lifecycle invalidation, or enqueue an `AppRoute`
  when delivery changes navigation. Do not encode routes as lifecycle events.
- `syncHistoricalScansDown` is throttled to once per 15 minutes. Do not add
  additional call sites without also checking
  `UserDefaultsKeys.lastHistoricalSyncDate`.
- **Always let `OfflineJobScheduler.drainRunnableJobs(using:)` own foreground
  queue drain and replay after the required-consent guard.** `NWPathMonitor`
  only fires when connectivity changes, while delayed Swift tasks do not survive
  process termination. Do not restore direct lifecycle calls to
  `syncPendingScans()` or `replayInferenceForUploadedScans()`; preserve the
  scheduler's durable wake reconstruction.
- All async work inside `handleActivePhase` is intentionally fire-and-forget
  (`Task {}`). Errors are logged but never surface to the user during a phase
  transition.

## 2026-04 Hardening Updates

- App startup now uses corruption-specific store recovery. A generic
  `ModelContainer` init failure is no longer treated as permission to delete the
  local SwiftData store.
- Recovery-first startup behavior is now: inspect store metadata, choose the
  narrowest safe `ModelContainer` strategy (current-store open, source-isolated
  recent migration plan, or full historical plan), inspect the error chain for
  SQLite/Core Data corruption signatures if opening fails, quarantine the store
  bundle only when corruption is confirmed, then retry container creation
  exactly once. Non-corrupt legacy migration failures archive the old store
  bundle under `store-rescue/` and open a fresh persistent store instead of
  looping in safe mode.
- `handleActivePhase()` continues to trigger scheduler-owned replay recovery,
  but any new lifecycle work must not resurrect stale scan mutations.
  `InferenceEngine` now invalidates pending background writes whenever a scan is
  cancelled or a new scan begins. Auth transitions additionally close new
  inference-write admission and await every retained active handle before the
  SDK session may change.

## 2026-05 Startup Safety Update

- If the post-quarantine retry still cannot open the persistent store, startup
  now falls back to an in-memory `ModelContainer` and surfaces a recovery notice
  banner instead of crashing in a launch loop.
- Lifecycle code must tolerate this safe mode. Do not assume persistent storage
  was available just because the app reached `.active`.

## 2026-07 Startup Store-Recovery Guardrails

The full operating contract lives in
`docs/backend-and-data/08-startup-store-recovery.md`.

- SwiftData/Core Data can raise Objective-C `NSException`s during
  `ModelContainer` initialization, which Swift `do/catch` cannot catch directly.
  `MerianApp` wraps container creation with a tiny Objective-C bridge so those
  launch-time exceptions become Swift errors and can enter the existing recovery
  path.
- Startup reads SwiftData store metadata before creating the persistent
  container. Fresh/current stores open without a migration plan, known recent
  stores use source-isolated V48/V47/V46/V45/V44/V43/V42 plans, and unknown
  older stores use the full historical plan. That full plan jumps V42→V49 or
  V43→V49 so SwiftData does not validate the duplicate-prone V44/V45/V46 recent
  cluster during older-store migrations. V42/V43 use short direct plans to avoid
  validating older full-historical custom stages that can raise SwiftData's
  equal-model-reference exception. V46 is a no-op checksum twin of V45, so its
  recent plan keeps V46 as the only duplicate-cluster source representative and
  jumps directly to V49. V47 has its own source-isolated plan for stores already
  stamped V47. Every selected migration path then applies the shared lightweight
  V49→V50 stage that adds `OfflineQueuedScanGoalHint`; current V50 stores open
  without a migration plan. Duplicate-checksum failures retry through the same
  recent-plan ladder before legacy rescue or safe mode.
- Store quarantine remains corruption-only and is owned by
  `Core/Data/StoreRecovery/ModelStoreRecoveryCoordinator.swift`. Non-corrupt
  failures on legacy migration strategies archive `default.store`,
  `default.store-shm`, and `default.store-wal` under `store-rescue/`, then
  recreate a fresh persistent current-schema store. Generic current-store
  failures still boot safe mode without moving user data.
- Quarantine and rescue directories include `recovery-manifest.json` with
  app/build/OS metadata, archive reason, moved artifact names, and a sanitized
  error reason. This manifest is for support and debugging only; it must not
  include user IDs, paths outside the archive, access tokens, or profile data.
- Store recovery must never clear Keychain auth, Supabase sessions, device
  identity, profile state, or cloud ownership. Local SwiftData recovery is
  isolated from account identity so a damaged local library cannot sign a user
  out or orphan Explore posts.
- Recovery emits the coarse `StartupStoreRecovery` telemetry event after
  analytics initialization with only `outcome` and `reason`.
- Folder-level `README.md` files are documentation only. `project.yml` excludes
  markdown from the Merian target, and `make validate-ios-project` fails if
  generated Xcode resources start bundling markdown docs again.
