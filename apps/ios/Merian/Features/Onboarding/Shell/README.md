# Onboarding Shell

The `Shell` directory contains the root container and state machine for the
onboarding sequence after `MerianApp` has selected onboarding as the app root.

## Structure

- **Views**: Contains the top-level container views that host the onboarding
  flow.
- **ViewModels**: Manages the onboarding sequence, determines which step to
  show, tracks completion, and handles the transition out of onboarding.

## Root-presentation boundary

The shell does not decide whether missing consent is still being restored.
`AppRootPresentationPolicy` in `MerianApp.swift` owns that decision using
completed onboarding, current required consent, and
`ConsentManager.isRestoringRequiredConsent`:

- a first-time user enters this shell at `.welcome`;
- a completed user stays on the launch-matched restoration surface until the
  initial session and any authoritative consent merge resolve;
- a completed user whose resolved account still lacks current evidence enters
  this shell directly at `.ready`; and
- a completed user with current evidence bypasses this shell for the Capture
  workspace.

Keeping the pending/absent distinction outside `OnboardingViewModel` prevents
approval controls from briefly appearing and then disappearing during launch.

## Purpose

Following the Merian iOS architecture guidelines, the `Shell` isolates sequence
orchestration from the individual onboarding screens. It controls progression
from Welcome through permission requests and into Ready, keeping each step
focused on its own presentation.
