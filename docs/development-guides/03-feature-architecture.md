# Feature Architecture Guide

This document defines the canonical structure for every feature in Merian and explains how ViewModels wire to Core managers, where DI injection happens, and the naming conventions that prevent structural drift across the codebase.

---

## Directory Layout

Every feature lives under `merian/Features/<FeatureName>/` and follows this folder structure:

```
Features/
└── Camera/
    ├── Components/         # Reusable sub-views that accept value-type inputs
    │   └── ShutterButton.swift
    ├── Managers/           # @Observable @MainActor hardware/service managers scoped to the feature
    │   └── SpeechManager.swift
    ├── Modifiers/          # ViewModifier and custom modifier structs
    │   ├── CameraSheetRouter.swift
    │   └── CropSheetModifier.swift
    ├── Models/             # Feature-local data types (not SwiftData models)
    │   └── ImageFileWrapper.swift
    ├── Utilities/          # Feature-local helpers (e.g. ImageCropProcessor)
    ├── ViewModels/         # @Observable @MainActor classes
    │   ├── CameraViewModel.swift    # Primary ViewModel
    │   ├── Capture.swift            # Extension with capture logic
    │   └── Analysis.swift           # Extension with analysis logic
    └── Views/              # SwiftUI View structs only
        ├── CameraRootView.swift     # Root view, owns @State private var viewModel
        └── PostProcessing/
            └── ImageCropperView.swift
```

**Rules:**
- `Views/` contain only SwiftUI `View` structs. Zero business logic.
- `ViewModels/` contain `@Observable @MainActor final class` ViewModels. Split large ViewModels into extensions in separate files (e.g. `Capture.swift`, `Analysis.swift`) rather than growing one file.
- `Components/` are passive — they receive data via `let` properties and closures. They must not access `AppDIContainer.shared` directly.
- `Models/` are local to the feature and never `@Model` (SwiftData models live in `merian/Models/`).
- `Modifiers/` implement `ViewModifier` or provide `.modifier(...)` call-site helpers.
- `Managers/` hold `@Observable @MainActor final class` service objects that own a hardware or OS resource scoped to the feature (e.g. `SpeechManager` owns `AVAudioEngine`). Managers that must be shared across multiple features belong in `AppDIContainer` instead.

---

## ViewModel Pattern

### Declaration

```swift
@Observable
@MainActor
final class CameraViewModel {
    // Dependencies — injected via AppDIContainer, not passed through views
    @ObservationIgnored let diContainer = AppDIContainer.shared

    // UI state only — no business logic in stored properties
    var activeSheet: ActiveSheet? = nil
}
```

**Key rules:**
- Always `@Observable @MainActor final class` — never `ObservableObject`.
- Access Core managers via `diContainer.managerName`, not via global singletons in business logic methods.
- Use `@ObservationIgnored` for any stored property that should not trigger SwiftUI redraws (tasks, cancellables, the DI container reference itself).
- Use `private var tooltipTask: Task<Void, Never>?` (not `@ObservationIgnored`) only when the task IS part of observable state. Most tasks should be `@ObservationIgnored`.

### Instantiation in Views

```swift
struct CameraRootView: View {
    @State private var viewModel = CameraViewModel()
    // ...
}
```

The root view for a feature owns the ViewModel via `@State`. Child views receive it as a parameter or via closures — never via `@EnvironmentObject`.

---

## Dependency Injection

All Core managers are accessed through `AppDIContainer.shared` (singleton, statically bound at app startup).

```swift
// In a ViewModel method
func executeCapture() {
    diContainer.cameraManager.startSession()
    diContainer.hapticManager.triggerMediumPulse()
}
```

**Rules:**
- Never inject managers via `@EnvironmentObject`. Use `@Environment(ManagerType.self)` only for types provided through `MerianApp.swift`'s `.environment()` chain.
- Never call `AppDIContainer.shared` from inside a `View` body. All DI access belongs in ViewModels.
- Pass managers from a View to a child Component via closure callbacks, not by passing the DI container.

### What is injected via `@Environment` vs `AppDIContainer`

| Access pattern | Used for |
|---|---|
| `@Environment(CameraManager.self)` | Managers that Views read directly for display state (e.g. `cameraManager.session` for the preview layer) |
| `diContainer.managerName` inside a ViewModel | All business logic calls |
| `@Environment(\.modelContext)` | SwiftData context, passed explicitly to methods that need it |

---

## Naming Conventions

| Element | Convention | Example |
|---|---|---|
| Feature root view | `<Feature>RootView` | `CameraRootView` |
| Primary ViewModel | `<Feature>ViewModel` | `CameraViewModel`, `ScansManager` |
| ViewModel extensions | Verb-noun grouping | `Capture.swift`, `Analysis.swift` |
| Sheet/modal enum | `ActiveSheet` inside the ViewModel | `CameraViewModel.ActiveSheet` |
| Reusable components | Descriptive noun | `ShutterButton`, `ScanThumbnail` |
| View modifiers | Modifier suffix | `CropSheetModifier`, `ScansToolbarModifier` |
| Local feature models | No suffix | `ImageFileWrapper`, `SearchableScan` |
| Utility helpers | Manager/Processor suffix | `InsightMediaExportManager`, `ImageCropProcessor` |

---

## SwiftData Access Pattern

ViewModels never hold a `ModelContext` directly. The `ModelContext` is owned by the SwiftUI environment (injected via `@Environment(\.modelContext)`) and passed explicitly to methods that need it.

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

Heavy SwiftData work (bulk fetches, ingest, reconciliation) is always delegated to a `@ModelActor` actor — see `docs/backend-and-data/05-database-actors.md`.

---

## Sheet Routing Pattern

All modals and sheets are driven by a single `activeSheet` enum on the ViewModel.

```swift
enum ActiveSheet: String, Identifiable {
    case insight, paywall, scans, profile
    var id: String { rawValue }
}
```

Complex sheet routing logic (multiple `.sheet`, `.fullScreenCover`, custom modifier stacks) is extracted into a `ViewModifier` and applied as a single `.modifier(...)` call on the root view:

```swift
.cameraSheetRouter(viewModel: viewModel)  // defined in CameraSheetRouter.swift
```

---

## Adding a New Feature

1. Create `merian/Features/<FeatureName>/` with the subdirectories above.
2. Add `<FeatureName>RootView.swift` in `Views/`.
3. Add `<FeatureName>ViewModel.swift` in `ViewModels/` — `@Observable @MainActor final class`.
4. Wire DI access via `let diContainer = AppDIContainer.shared` inside the ViewModel.
5. If the feature needs Core managers exposed to the view layer, register them in `MerianApp.swift`'s `.environment()` chain.
6. If the feature introduces a new Core manager, add it as a `var` in `AppDIContainer.swift`, add `.environment(container.managerName)` to `DIContainerModifier.body()`, and document it in `docs/development-guides/09-core-managers.md`.
7. If the feature introduces a hardware/OS resource manager scoped only to that feature, place it in `Managers/` (not `AppDIContainer`).
8. Run `xcodegen generate` after adding any new Swift file or subdirectory — `project.yml` uses a directory wildcard (`sources: [Merian]`) so no `project.yml` edit is required, but the `.xcodeproj` must be regenerated.
9. Update `docs/development-guides/09-ai-agent-guidelines.md` Section 2 if the directory structure changes.
