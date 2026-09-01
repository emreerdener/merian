# Onboarding Permissions

The `Permissions` directory owns Onboarding's narrow adapters for system
permission prompts. It contains no user-facing step layout.

## Structure

- **Services**: `OnboardingPermissionDependencies.live` adapts AVFoundation
  camera access and a retained location delegate into completion closures for
  the shell.
- **Location**: The `@MainActor` `LocationPermissionDelegate` owns
  `CLLocationManager`, immediately hops nonisolated delegate callbacks back to
  the main actor before reading authorization state, retains one pending request
  completion, ignores `.notDetermined` callbacks, and clears the completion
  before delivery.

## Purpose

While `Steps` defines the permission rationale and actions, `Permissions`
isolates AVFoundation and Core Location. Step views receive closures and cannot
invoke native permission APIs directly. The shell's expected-step fence makes
late or duplicate OS completions harmless without changing prompt behavior.
