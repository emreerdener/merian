# Onboarding Shell

The `Shell` directory contains the root container and state machine for the
onboarding sequence after `MerianApp` has selected onboarding as the app root.

## Structure

- **Views**: The top-level container switches the four step views and retains
  alert and transition timing.
- **ViewModels**: `OnboardingViewModel` owns ordered step state and completion
  orchestration through `OnboardingDependencies`. It compares every requested
  advance with the current step so duplicate or late callbacks cannot advance a
  replacement screen.
- **Services**: `OnboardingDependencies.live` is the only Onboarding owner that
  resolves `AppSettings`, `ConsentManager`, telemetry, consent-blocked queue
  recovery, or hardware-animation state.
- **Components**: Shell-only ambient presentation. Its hardware animation policy
  is injected; accessibility Reduce Motion remains view-owned.

## Root-presentation boundary

The shell does not decide whether missing consent is still being restored.
`AppRootPresentationPolicy` in `MerianApp.swift` owns that decision using
completed onboarding, current required consent, and
`ConsentManager.isRestoringRequiredConsent`:

- a first-time user enters this shell at `.welcome`;
- a completed user whose current local evidence is missing stays on the
  launch-matched restoration surface until the initial session establishes no
  active account or the authenticated account completes an authoritative consent
  merge; an expired cached session retains its known account identity there
  until Supabase refreshes it or emits sign-out; synchronization failures retain
  that surface with bounded automatic and explicit retry;
- a completed user whose resolved account still lacks current evidence enters
  this shell directly at `.ready`;
- a completed user whose first or later provider attempt receives exact
  `403 ai_consent_required` is durably fenced by account, completes an
  authoritative restoration pass, and then re-enters this shell at `.ready`.
  Relaunch cannot bypass that transition, and another account cannot inherit it;
  and
- a completed user with current evidence bypasses this shell for the Capture
  workspace.

Keeping the pending/absent distinction outside `OnboardingViewModel` prevents
approval controls from briefly appearing and then disappearing during launch.

## Dependency and completion boundary

`MerianApp` constructs the shell with the same app-scoped `AppSettings`,
`ConsentManager`, `OfflineQueueManager`, and `HardwareOrchestrator` instances
used by the rest of the root. Compatibility initializers remain available for
tests and previews, but views and the observable state owner do not resolve
singletons.

The default Camera and Location step initializers preserve their established
call-site signatures by composing the feature-local live permission adapter. The
production shell instead constructs one retained permission dependency and
injects its request closures into the mounted step. In both paths, native API
ownership remains under `Permissions`.

Completion preserves the established ordering: first record and verify the
durable consent action, then record completion telemetry, then open the
onboarding lifecycle flag, and finally resume the newest consent-blocked scan
for the current account when one exists. A failed consent write performs none of
the downstream effects.

## Purpose

Following the Merian iOS architecture guidelines, the `Shell` isolates sequence
orchestration from the individual onboarding screens. It controls progression
from Welcome through permission requests and into Ready, keeping each step
focused on its own presentation.
