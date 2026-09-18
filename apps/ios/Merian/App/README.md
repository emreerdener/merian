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
  performs no networking or persistence. `AppTopScrollEdgeEffectModifier` is
  applied outside the root presentation tree so all descendant scroll views,
  including sheets and navigation destinations, hide the iOS 26+ top scroll-edge
  effect. Individual control glass and bottom scroll-edge effects are unchanged.
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
owner. The portable iOS workflow contract extracts every Debug seed marker from
`UITesting/UITestSeedCoordinator.swift` and requires the Release archive
denylist to match exactly.

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
