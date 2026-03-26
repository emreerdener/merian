# App Intents & OS Integration

Merian deeply integrates with Apple's `AppIntents` framework to surface core camera and discovery capabilities to Siri, Spotlight, and the Shortcuts app without requiring the user to manually launch the application.

## 1. Intent Routing

All App Intents in Merian are designed to execute seamlessly using a shared architectural pattern. To bridge the structured boundary between the background Intent execution and the `@MainActor` UI, Merian uses an `AppState` router singleton. 

When an Intent fires, it executes `AppState.shared.navigateTo(...)` or equivalent methods to mutate the global view hierarchy state, guaranteeing that the application is fully hydrated before the visual transition completes.

## 2. Supported Intents

### `IdentifyNatureIntent`
**Phrase**: "Identify Nature", "Open Merian camera", "Scan biology with Merian"  
**Behavior**: Immediately launches the application, prioritizes the `CameraRootView`, and prepares the `AVCaptureSession` layer.
- By setting `openAppWhenRun = true`, the Intent explicitly forces the OS to pull the app out of the background to provide a visual viewfinder.
- Triggers a tactile `HapticManager.shared.triggerFocusSnap()` upon execution.

### `RecallLastFindIntent`
**Phrase**: "Look Up My Last Find", "What was the last thing I scanned in Merian?"  
**Behavior**: Bypasses the camera and navigates directly to the user's most recent scan.
- Leverages `AppState.shared.navigateToLastScan()`.
- Provides an immediate transition into the `InsightSheetView` taxonomy readout.
- Triggers `HapticManager.shared.triggerSheetSpring()` logic.

## 3. Shortcuts Provider

Merian uses `AppShortcutsProvider` (`MerianShortcuts`) to automatically register these intents with Siri upon installation, requiring no manual shortcut construction by the user.

- **Tile Color**: The Shortcuts app uses Merian's `.teal` accent color for generating the shortcut visual tiles.
- **System Icons**: Integrates native SF Symbols (`leaf.fill` and `clock.arrow.circlepath`) for deep OS consistency.
