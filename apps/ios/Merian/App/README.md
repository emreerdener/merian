# App Root

`App` owns process entry, root composition, application-delegate bridges,
startup presentation, external URL admission, lifecycle forwarding, and
compile-time-gated UI-test setup. Product workflows remain in `Features`, while
reusable infrastructure remains in `Core`.

## Ownership

- `MerianApp.swift` is the composition root. It constructs app-scoped
  dependencies, requests and attaches the Store Recovery-owned SwiftData
  bootstrap outcome, selects the root surface, binds scene phase, owns
  account-deletion recovery presentation, and remains the sole asynchronous
  caller for fallback Supabase authentication URLs.
- `AppDelegate.swift` is the UIKit callback bridge for background URLSession
  completion and APNs registration results. The platform-required delegate may
  forward into the established app-scoped managers; views must not duplicate
  those callbacks.
- `Lifecycle/` owns scene-phase admission and app-wide maintenance after the
  root forwards a phase transition.
- `Presentation/` owns deterministic launch/root selection, startup-store
  environment keys and rendering, and configuration-warning composition. Store
  Recovery supplies the value-only startup state and notice. Presentation
  performs no networking or persistence. Scroll-edge appearance belongs to the
  shared Core UI modifier applied directly by scrolling surfaces.
- `Routing/` owns value-only URL classification. `MerianApp` intentionally
  evaluates Google Sign-In first, then handles Naturebook/Merian routes, file
  imports, and finally fallback Supabase authentication. That ordering is a
  behavioral contract.
- `UITesting/` owns deterministic fixture preparation behind `#if DEBUG` and the
  signature-compatible Release no-op surface. Release code must contain no seed
  arguments, deterministic `ui_test_` identifiers, or fixture mutation. It
  consumes the process-wide test detector owned by
  `Configuration/TestExecutionCoordinator.swift`; reusable Core services do not
  depend on an App-root declaration.

## Startup persistence boundary

Before dependency and Auth bootstrap, ordinary launches inspect the deletion
recovery proof through `AccountDeletionRecoveryCapabilityStore`. A prior
lookup-only barrier is cleared only on verified proof absence; a cached session
is not required at this stage. The store suppresses runtime events until
bootstrap is complete. App-hosted XCTest and UI-test processes skip that live
probe because their Keychain implementation is synthetic. Direct store tests
exercise the recovery logic with isolated defaults and injected secure storage.
See the
[account-deletion contract](../../../../docs/backend-and-data/20-sign-in-with-apple-account-deletion.md#client-crash-recovery).

`Core/Data/StoreRecovery/Services/ModelContainerFactory.swift` owns SwiftData
construction, source-isolated migration-plan routing, and duplicate-checksum
fallback. Its empty current-schema safe-mode container is plan-free, so a bad
historical stage cannot defeat the final recovery boundary; the full plan is
validated independently in `MigrationPlanTests`. `ModelContainerBootstrapper`
owns launch diagnostics and the quarantine, rescue, safe-mode, and blocked-state
ladder. `MerianApp` invokes one bootstrap entry point and retains only
composition after the result. Every Release production owner in `App` and Store
Recovery stays within the 600-line review guard. The UI-test coordinator is
excluded from the production ceiling because its fixture implementation is
compiled only in Debug and the same source owns the Release no-op contract. The
app-wide `IOSHygieneClosureArchitectureTests` inventory records that coordinator
as the only oversized App owner and rejects any additional App source above the
shared ceiling.

## Tests and safeguards

Mirrored tests live under `MerianTests/App/`. `AppRootArchitectureTests` freezes
the focused source inventory, production line ceiling, Store Recovery
delegation, DEBUG/Release seed separation, and root scene/Auth-task ownership.
Presentation and routing tests own their deterministic policy behavior.
Configuration tests freeze the shared test-execution signals and declaration
owner. The portable iOS workflow contract extracts every seed marker from the
Swift files in `UITesting/`, including focused extensions, and requires the
Release archive denylist to match exactly. A literal outside DEBUG remains
forbidden in the archived binary.

`UITestSeedCoordinator+OpenAIPermission.swift` owns the Debug/UI-test-only
synthetic permission ledger and matching saved-job funding used by the
permission recovery smoke. `AppDIContainer` selects this fixture only under the
dedicated UI-test argument. It does not replace a production SDK identity or
perform provider requests; test-mode synchronization and Realtime stay disabled.

The required-consent UI fixture seeds at initialization and again when the
consent manager adopts a nonnil account. Initial unowned receipts stop applying
after account adoption, while test mode deliberately disables the cloud sync
that would bind them. The App root observes the consent owner directly; Core
does not call fixture code. Seeding still requires Debug, `UITesting=true`, and
the existing consent seed argument, and its failure diagnostic contains only the
error type. Debug UI-test consent storage is process-local; normal launches
retain durable consent and every production readiness check.

See the canonical
[app lifecycle contract](../../../../docs/development-guides/02-app-lifecycle.md),
[startup recovery contract](../../../../docs/backend-and-data/08-startup-store-recovery.md),
and
[event routing contract](../../../../docs/system-architecture/10-event-and-presentation-routing.md).

Sign-out confirmation feedback is owned by `MerianApp`, outside the root
presentation switch. Profile, Settings, and explicit purchase-continuity
recovery invoke the `showSignOutConfirmation` environment callback only after
success; the shared top toast remains mounted when consent onboarding replaces
the workspace. The callback does not alter Auth or consent state.

`Presentation/WhatsNewLaunchStore.swift` owns the device-local highlight-set
acknowledgement. After required consent, the root mounts Workspace with the
announcement as its initial `CameraSheetRouter` destination. The App-owned
`acknowledgeWhatsNew` callback persists only after dismissal and rechecks
consent and recovery state. Workspace stays mounted; Settings reuses the content
view. See the
[What’s New contract](../../../../docs/development-guides/12-in-app-changelog.md#whats-new-sheet).

`Lifecycle/AppUpdateCoordinator` owns the account/build-scoped compatibility
pause and prompt dismissal state. The root uses `Presentation/AppRootAlertHost`
and one `AppRootAlertPolicy` to defer the update prompt behind account-deletion
recovery, Apple-revocation cleanup, and onboarding. The App Store action does
not clear the pause. Debug builds on physical devices and all simulator builds
suppress the update prompt because these installations have no App Store update
path; compatibility pauses still apply. Release device builds retain the prompt.
See the
[update-required UX contract](../../../../docs/system-architecture/10-event-and-presentation-routing.md#update-required-presentation).

## Guided device review

The shared `Merian Device - …` Xcode schemes reuse existing Debug/UI fixtures
for manual iPhone review. They set `UITesting=true`, a scenario keychain
namespace and the same launch arguments as the automated scenarios. They install
no live history bundle and use an in-memory SwiftData library. The
[device checklist](../../../../docs/development-guides/24-identification-history-device-review.md)
records exact supported inputs and the separate live/restart/migration limits.

## Prepared history composition

`Composition/PreparedHistoryReanalysisComposition.swift` assembles the existing
History, read-only reanalysis status, and protected Capture accesses. It
performs no work at construction and ordinary live dependencies do not install
it. The AppDI factory uses its supplied Supabase manager, route coordinator and
queue's shared preparation owner. Exact submitted-child and erasure callbacks
return to that same queue; no second runtime, route store or enrollment
scheduler exists.

All three accesses share the injected cloud client, account/session generation
and private-photo resolver. Photo preview, editor loading and original-photo
preparation use that resolver and the same verified downloader. An invalidated
session cannot regain access after A → B → A. The bundle does not enroll scans,
change selection, request consent or enable rollout. Explicit enrollment and
release qualification remain separate. `HistoryReanalysisCompositionTests`
exercises the actual prepared photo/editor/persistence/status handoff with
synthetic tickets, bytes and isolated files.

The inert history/reanalysis composition also exposes a protected saved-result
entry using the same cloud/account/session dependencies and QueueManager's
retained enrollment owner. Its current-container predicate follows the queue's
bound ModelContext. The bundle still starts no work and is not installed by
ordinary live factories. Explicit taps freeze their displayed baseline; History
and status reads do not enroll.

The App root now retains one optional bundle from `appInstallation`. The
immutable `isAppInstallationQualified` constant is false, so the factory is not
evaluated and ordinary access stays nil. No user preference, remote flag or
consent state can enable this source-controlled boundary. When qualified, the
same retained bundle supplies Capture synchronously before its State ViewModel
is created and supplies a feature-owned grouped Insight environment value across
the complete workspace, including navigation and modal hosts. It never installs
individual global optional services. Explicit injected feature dependencies take
precedence.

### Prepared audio Capture assembly

`PreparedHistoryReanalysisComposition+Audio` supplies an optional audio access
inside the inert bundle. It uses the same cloud account and queue preparation
owner. The adapter explicitly receives the network client, builds closed audio
execution dependencies from the opened file store, and starts only the exact
saved key/proof through `requestAudioExecution`. Cleanup uses the queue's
existing erasure owner and completion publishes through the injected App event
publisher. Account/session/generation and container validity govern retained
work; no presentation predicate reaches the queue. Construction performs no I/O.
The fixed-false App installer remains unchanged.

The same optional access now exposes explicit saved-child `openResume`. It
accepts owner/observation/source/child IDs, freezes the current account session,
generation and container through a short opening lease, then releases it. No
source lookup or new Capture plan occurs at opening. Explicit resume delegates
to the retained exact-proof reader and preparation/binding service. A fresh
matching snapshot and both common and presentation checks precede the injected
queue handoff. Presentation never enters retained execution. Construction and
opening start no queue; ordinary installation and automatic adoption remain off.

### Saved audio chooser UI qualification

`UITestSeedCoordinator+SavedAudio` supplies a Debug-only, UI-test-only chooser
model under the explicit `-seedSavedAudioChooser` argument. A DEBUG-gated root
modifier presents the real model and sheet with in-memory domain rows and an
unavailable-only resume closure. It acquires no lease and touches no
persistence, queue, media, consent or provider. `MerianApp` contains no raw
launch argument; Release compiles out both modifier and fixture. The existing
release-binary seed denylist includes the argument. Ordinary prepared-history
installation remains disabled. This fixture is rendering evidence, not durable
audio or backend qualification.
