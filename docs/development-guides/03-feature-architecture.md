# Feature Architecture Guide

This document defines the canonical structure for every feature in Merian and
explains how ViewModels wire to Core managers, where DI injection happens, and
the naming conventions that prevent structural drift across the codebase.

---

## Directory Layout

Every feature lives under `apps/ios/Merian/Features/<FeatureName>/`. Prefer a
product-area-first structure when a feature contains multiple user-facing areas.
Shared shell, staging, submission, or support code should sit beside those
product areas rather than mixing mode-specific UI in a single folder.

Use this ownership order:

1. Feature root: the main navigation or large product surface (`Explore`,
   `Scans`, `Profile`, `Capture`).
2. Product area: the user-recognizable area inside that feature (`Feed`, `Map`,
   `Settings`, `Scan`, `Record`, `Describe`).
3. Implementation type: `Views`, `Components`, `Models`, `ViewModels`,
   `Services`, or `Utilities`.

```text
Features/
└── <FeatureName>/
    ├── Shell/              # Root container, routing, tabs/pagers, and feature chrome
    ├── <ProductArea>/      # User-recognizable area owned by this feature
    │   ├── Views/
    │   ├── Components/
    │   ├── Models/
    │   ├── Services/
    │   └── ViewModels/
    └── Shared/             # Reused only inside this feature
```

Avoid parallel folders such as `Screens/` and `Views/`. In SwiftUI, a sheet,
detail route, tab, or full-screen page is still a view; nesting should
communicate ownership.

```
Features/
└── Capture/
    ├── Shell/              # Root view, root ViewModel, routing, and app chrome
    │   ├── Components/
    │   ├── Models/
    │   ├── Modifiers/
    │   ├── Services/
    │   ├── ViewModels/
    │   └── Views/
    ├── Scan/               # Visual input UI, actions, and bounded preparation
    │   ├── Components/
    │   ├── Models/
    │   ├── Modifiers/
    │   ├── Services/
    │   ├── ViewModels/
    │   └── Views/
    ├── Record/             # Audio-specific recording and visualization views
    │   └── Views/
    ├── Describe/           # Text/dictation input, prompts, subject matching
    │   ├── Managers/
    │   ├── Models/
    │   └── Views/
    ├── Staging/            # Multi-capture staging and pre-submit review
    │   ├── Models/
    │   └── Views/
    ├── Submission/         # Live/offline analysis submission paths
    │   └── ViewModels/
    └── Shared/             # Capture-only shared models or coordination helpers
        ├── Models/
        ├── Utilities/
        └── ViewModels/
```

**Rules:**

- `Views/` contain only SwiftUI `View` structs. Zero business logic.
- `ViewModels/` contain `@Observable @MainActor final class` ViewModels. Split
  large ViewModels into responsibility-named extensions in separate files (for
  example, `CaptureWorkspaceViewModel+PhotoCapture.swift` and
  `CaptureWorkspaceViewModel+VideoCapture.swift`) rather than growing one
  aggregate file.
- `Components/` are passive — they receive data via `let` properties and
  closures. They must not access `AppDIContainer.shared` directly.
- `Models/` are local to the feature and never `@Model` (SwiftData models live
  in `apps/ios/Merian/Models/`).
- `Modifiers/` implement `ViewModifier` or provide `.modifier(...)` call-site
  helpers.
- `Managers/` hold `@Observable @MainActor final class` service objects that own
  a hardware or OS resource scoped to the feature (e.g. `SpeechManager` owns
  `AVAudioEngine`). Managers that must be shared across multiple features belong
  in `AppDIContainer` instead.
- `Shared/` means shared within one feature. Promote to `Core/` only when the
  code is reused across features or represents app infrastructure.

---

## ViewModel Pattern

### Declaration

```swift
@Observable
@MainActor
final class CaptureWorkspaceViewModel {
    // Dependencies are initializer-injected; production may use the shared graph.
    @ObservationIgnored let diContainer: AppDIContainer

    init(diContainer: AppDIContainer = .shared) {
        self.diContainer = diContainer
    }
}
```

**Key rules:**

- Always `@Observable @MainActor final class` — never `ObservableObject`.
- Access Core managers via `diContainer.managerName`, not via global singletons
  in business logic methods.
- Use `@ObservationIgnored` for any stored property that should not trigger
  SwiftUI redraws (tasks, cancellables, the DI container reference itself).
- Use `private var tooltipTask: Task<Void, Never>?` (not `@ObservationIgnored`)
  only when the task IS part of observable state. Most tasks should be
  `@ObservationIgnored`.

### Instantiation in Views

```swift
struct CaptureWorkspaceView: View {
    @State private var viewModel = CaptureWorkspaceViewModel()
    // ...
}
```

The root view for a feature owns the ViewModel via `@State`. Child views receive
it as a parameter or via closures — never via `@EnvironmentObject`.

---

## Dependency Injection

`AppDIContainer.shared` is the production dependency graph. View models accept
the container through initialization so tests and previews can isolate event,
route, settings, and explicit test-seam state without binding global auth route
state. Observable render dependencies are also injected individually through
SwiftUI `@Environment`; the container itself is not installed as one broadly
observed environment value.

```swift
// In a ViewModel method
func executeCapture() {
    diContainer.cameraManager.startSession()
    diContainer.hapticManager.triggerMediumPulse()
}
```

**Rules:**

- Never inject managers via `@EnvironmentObject`. Use
  `@Environment(ManagerType.self)` only for types provided through
  `MerianApp.swift`'s `.environment()` chain.
- Do not fetch arbitrary dependencies from `AppDIContainer.shared` inside a
  reusable component's render expression. Root views read observable state from
  `@Environment`; business operations belong in an injected view model.
- Cross-module invalidations and navigation are infrastructure boundaries. Use
  the container-owned `AppEventPublisher` or environment-injected
  `AppRouteCoordinator`; never create a feature-local app bus, post an
  application-defined `Notification.Name`, or add a sibling root sheet.
- Raw Combine `.sink` is a reviewed lifetime boundary, not a default
  subscription style. SwiftUI views use lifecycle-owned `.onReceive`; Apple
  framework publishers with unknown executors use `sinkOnMainActor`. A new raw
  sink must document weak/strong capture intent, cancellable ownership,
  cancellation, delivery ordering, and actor isolation before its exact file is
  admitted by the event-routing guard.
- Pass managers from a View to a child Component via closure callbacks, not by
  passing the DI container.

### What is injected via `@Environment` vs `AppDIContainer`

| Access pattern                               | Used for                                                                                                 |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `@Environment(CameraManager.self)`           | Managers that Views read directly for display state (e.g. `cameraManager.session` for the preview layer) |
| `@Environment(AppRouteCoordinator.self)`     | Root observation and typed route requests that must compose with global presentation state               |
| `diContainer.managerName` inside a ViewModel | All business logic calls                                                                                 |
| `diContainer.appEventPublisher`              | Small loss-tolerant invalidations; reference subscribers own cancellables and capture themselves weakly  |
| `@Environment(\.modelContext)`               | SwiftData context, passed explicitly to methods that need it                                             |

---

## Naming Conventions

| Element                          | Convention                                                | Example                                                    |
| -------------------------------- | --------------------------------------------------------- | ---------------------------------------------------------- |
| Feature root view                | `<Feature>RootView`                                       | `CaptureWorkspaceView`                                     |
| Primary ViewModel                | `<Feature>ViewModel`                                      | `CaptureWorkspaceViewModel`, `ScansManager`                |
| ViewModel extensions             | Root type plus responsibility                             | `CaptureWorkspaceViewModel+PhotoCapture.swift`             |
| Root presentation destination    | `ActiveSheet` plus an identified envelope                 | `CaptureWorkspaceViewModel.PresentedRoute`                 |
| Feature-local presentation state | Owner-scoped typed item; Boolean only for one destination | `ExplorePostDetailPresentation`, staged-description editor |
| Reusable components              | Descriptive noun                                          | `CaptureFlashButton`, `ScanThumbnail`                      |
| View modifiers                   | Modifier suffix                                           | `CropSheetModifier`, `ScansSheetPresentationModifier`      |
| Local feature models             | No suffix                                                 | `ImageFileWrapper`, `SearchableScan`                       |
| Utility helpers                  | Manager/Processor suffix                                  | `InsightMediaExportManager`, `ImageCropProcessor`          |

---

## SwiftData Access Pattern

ViewModels never hold a `ModelContext` directly. The `ModelContext` is owned by
the SwiftUI environment (injected via `@Environment(\.modelContext)`) and passed
explicitly to methods that need it.

```swift
// In the View
.onChange(of: viewModel.selectedPhotoItems) { _, newItems in
    viewModel.handlePhotoPickerSelection(newItems: newItems, modelContext: modelContext)
}

// In the ViewModel
func handlePhotoPickerSelection(newItems: [PhotosPickerItem], modelContext: ModelContext) {
    // ...
}
```

Heavy SwiftData work (bulk fetches, ingest, reconciliation) is always delegated
to a `@ModelActor` actor — see `docs/backend-and-data/03-database-actors.md`.

---

## Sheet Routing Pattern

Root navigation and feature-local editing are separate presentation domains. Do
not force every editor, picker, or review cover into a global enum.

Cross-module destinations are requested as typed `AppRoute` values. The root
coordinator claims one stable envelope at a time, and
`CaptureWorkspaceViewModel` maps a presenting route to an identified
`PresentedRoute`:

```swift
enum ActiveSheet: String, Identifiable {
    case insight, paywall, scans, profile, explore, achievement
    var id: String { rawValue }
}

struct PresentedRoute: Identifiable {
    let id: UUID
    let destination: ActiveSheet
    let routeRequestID: UUID?
}
```

`CameraSheetRouter` owns the one root `.sheet(item:)` host:

```swift
.cameraSheetRouter(viewModel: viewModel)  // defined in CameraSheetRouter.swift
```

Feature-local sheets and covers stay with their product owner when they do not
represent cross-module navigation. Capture's description editor, guided
questions, video review, cropper, and feedback survey are examples. While any of
those is mounted or interactively dismissing, the root reports the UIKit
presentation slot as occupied. A claimed route resolves as deferred and resumes
from that presentation's exact `onDismiss` callback.

Presentation rules:

- Never mount sibling root sheets for Paywall, Insight, Scans, Profile, Explore,
  achievement detail, or the notification prompt.
- A feature-local view with several sheet/cover destinations owns one optional
  typed presentation value. Filter sheet and full-screen bindings from that same
  value so they cannot mount together. Async preparation is stored and
  cancellable, and may commit only while its request/subject identity is still
  current and the slot is empty; retain at most one explicitly bounded follow-up
  when product flow requires a post-dismiss handoff.
- Never use `Task.sleep` to guess when UIKit has finished tearing down a sheet
  or full-screen cover. Use `onDismiss` and match the request/presentation ID.
  The legacy feature-local compatibility delays inventoried in the canonical
  routing guide are migration work, not examples for new code.
- A non-presenting route must resolve terminally; a presentation-backed route
  remains in flight until that exact presentation dismisses. Invalid or missing
  targets must reject rather than block the queue.
- Toasts and progress capsules use alignment-scoped overlays. Only visible
  controls receive hit testing; do not add an invisible full-screen blocker.
- See the canonical
  [event and presentation routing contract](../system-architecture/10-event-and-presentation-routing.md)
  before adding an event, route, root destination, framework notification, or
  global feedback host.

---

## Adding a New Feature

1. Create `apps/ios/Merian/Features/<FeatureName>/` with the subdirectories
   above.
2. Add `<FeatureName>RootView.swift` in `Views/`.
3. Add `<FeatureName>ViewModel.swift` in `ViewModels/` —
   `@Observable @MainActor final class`.
4. Initializer-inject `AppDIContainer` into the ViewModel, with `.shared` only
   as the production default. Tests and previews must pass an isolated container
   instead of inheriting process-global event or route state.
5. If the feature needs Core managers exposed to the view layer, register them
   in `MerianApp.swift`'s `.environment()` chain.
6. If the feature introduces a new Core manager, add it as a `var` in
   `AppDIContainer.swift`, add `.environment(container.managerName)` to
   `DIContainerModifier.body()`, and document it in
   `docs/development-guides/09-core-managers.md`.
7. If the feature introduces a hardware/OS resource manager scoped only to that
   feature, place it in `Managers/` (not `AppDIContainer`).
8. Classify cross-module signals before implementation: reload hints use
   `AppEvent`; navigation uses `AppRoute`; durable work stays in its owning
   store; Apple callbacks remain at a reviewed framework boundary.
9. Run `xcodegen generate` after adding any new Swift file or subdirectory —
   `project.yml` uses a directory wildcard (`sources: [apps/ios/Merian]`) so no
   `project.yml` edit is required, but the `.xcodeproj` must be regenerated.
10. Update `docs/development-guides/07-ai-agent-guidelines.md` Section 2 if the
    directory structure changes. Synchronize the canonical routing guide for any
    event, route, presentation, feedback-host, or framework-boundary change.

## Test Mirroring

Unit tests mirror the production owner:

```text
MerianTests/
  Core/<CoreArea>/
  Features/<FeatureName>/<ProductArea>/
```

If a test primarily exercises a Core service, manager, actor, or infrastructure
policy, place it under `MerianTests/Core` even when the behavior appears in a
feature screen. If it primarily exercises product-area logic, view models,
presentation policies, or local helpers, place it under the matching
`MerianTests/Features/<FeatureName>/<ProductArea>/` folder.
