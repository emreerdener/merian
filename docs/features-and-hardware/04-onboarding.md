# Onboarding Flow

Merian gates all hardware initialization, background sync, and lifecycle handlers behind a `hasCompletedOnboarding` flag in `UserDefaults`. This document explains the 6-step permission flow, the state machine, and the completion gate.

---

## Architecture

| File | Role |
|---|---|
| `OnboardingStep` enum | Defines the 6 steps in order |
| `OnboardingViewModel` | `@Observable @MainActor` — owns `currentStep` and the `hasCompletedOnboarding` flag |
| `OnboardingView` | Root view, switches content based on `currentStep` |
| Step component views | One view per step, in `Features/Onboarding/Components/` |
| `LocationPermissionDelegate` | `CLLocationManagerDelegate` for native location permission priming |

---

## The Steps

```swift
enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case camera
    case location
    case ready
}
```

| Step | Component | What happens |
|---|---|---|
| `.welcome` | `WelcomeStepView` | Branding screen — no permission request |
| `.camera` | `CameraPermissionStepView` | Requests `AVCaptureDevice` camera permission |
| `.location` | `LocationPermissionStepView` | Requests `CLLocationManager` always/when-in-use authorization via `LocationPermissionDelegate` |
| `.ready` | `ReadyStepView` | Confirms setup complete; calls `viewModel.completeOnboarding()` |

Each step view is wrapped in `OnboardingStepWrapper` which provides consistent layout, animation, and the "Continue" button that calls `viewModel.advanceStep()`.

---

## State Transitions

```swift
func advanceStep() {
    if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
        currentStep = next
    }
}

func completeOnboarding() {
    AppTelemetry.trackOnboardingCompleted()  // fires before flag write — activation funnel signal
    hasCompletedOnboarding = true            // writes to UserDefaults("hasCompletedOnboarding")
}
```

`completeOnboarding()` is called on the `.ready` step. It fires a `OnboardingCompleted` TelemetryDeck signal before writing the flag, capturing the activation moment. Writing `true` to `hasCompletedOnboarding` is the gate that activates the full app lifecycle:

- `AppLifecycleManager.handleActivePhase()` checks this flag first and returns immediately if false
- `AppLifecycleManager.handleInactivePhase()` — same guard
- `AppLifecycleManager.handleBackgroundPhase()` — same guard

This means during onboarding: no camera session starts, no offline sync runs, no archive rescue fires.

---

## The `hasCompletedOnboarding` Gate

`OnboardingViewModel` exposes `hasCompletedOnboarding` as a computed property backed by `UserDefaults`:

```swift
var hasCompletedOnboarding: Bool {
    get { UserDefaults.standard.bool(forKey: "hasCompletedOnboarding") }
    set { UserDefaults.standard.set(newValue, forKey: "hasCompletedOnboarding") }
}
```

`MerianApp.swift` reads this flag via `@AppStorage("hasCompletedOnboarding")` to decide whether to show `OnboardingView` or the main `CameraRootView`. Once `completeOnboarding()` is called, the app never shows onboarding again (unless `UserDefaults` is reset via a hard reinstall).

---

## Permission Philosophy

Each permission step presents the rationale for the request before triggering the system dialog. This "permission priming" pattern maximizes grant rates by ensuring users understand the value before iOS shows the system alert.

- **Camera**: Required for all scan functionality. Without it the shutter is non-functional.
- **Location**: Required for GPS telemetry that improves AI accuracy (regional species ranges, invasive tracking) and populates the scan location metadata.

> [!NOTE]
> **Progressive Disclosure**: Push Notification and Photo Library permissions are deliberately omitted from the initial onboarding flow to reduce drop-off. Notifications are conditionally requested via a half-sheet after the first successful scan resolve. Photo Library permissions are conditionally requested via a half-sheet when the user specifically toggles "Save to camera roll" or taps the gallery import button.

---

## Re-entering from a Deep Link

If the app receives a deep link (e.g. a push notification tap routing to an `InsightSheet`) while onboarding is incomplete, the deep link is discarded. `CameraViewModel` observes `NSNotification.Name("AppDidEnterActivePhaseWithScan")` but its handler checks `diContainer.offlineQueueManager.modelContext` — which is nil until `ScanRepository.configure(with:)` runs during post-onboarding startup.
