# Describe Mode & Voice Dictation

The Describe capture mode is the third page of `CameraRootView`'s horizontal pager. It allows users to identify a biological subject through free-text description or live voice dictation instead of a photograph, routing through the `/identify-describe` Supabase Edge function via `InferenceEngine.analyzeDescribe`.

---

## 1. Architecture Overview

### State Ownership

`ObservationContext` is a `Codable, Equatable, Sendable` struct with a single `freeText: String` property and a computed `isEmpty` guard (trims whitespace). It is the value type that carries the user's input from the UI to `InferenceEngine`.

`@State private var observationContext = ObservationContext()` lives in **`CameraRootView`**, not in `DescribeInputView`. This lift is required because `SpeechManager` writes `observationContext.freeText` from outside `DescribeInputView` during live dictation. `DescribeInputView` receives the context as `@Binding var context: ObservationContext`.

The context is intentionally not reset after submission, so users can swipe back to the Describe page and refine their input without losing their text.

### Submission Routing (`CameraViewModel.submitDescribe`)

`submitDescribe(observationContext:modelContext:)` is an extension on `CameraViewModel` in `DescribeAnalysis.swift`. It routes based on what else is staged:

| Condition | Path |
|---|---|
| `isMultiCaptureEnabled == true` | Stages context in `stagedCapture.observationContext`, auto-submits if count reaches limit |
| Images staged + multi-capture off | Attaches context to staged capture, calls `submitStagedCapture` |
| No images staged | Solo describe path via `submitDescribeSolo` |

`submitDescribeSolo` mirrors the resilience pattern of the image capture path: if online, opens the insight sheet and fires `InferenceEngine.analyzeDescribe`; if offline, enqueues via `OfflineQueueManager.enqueueDescribe` with cached GPS telemetry and surfaces a toast.

---

## 2. `DescribeInputView`

Lives at `merian/Features/Describe/Views/DescribeInputView.swift`.

**Layout contract**: fills the full page frame. The fixed `MediaModeToggle` overlay sits above it in the `CameraRootView` Z-stack and must remain interactive — no content above `safeAreaInsets.top + 64` pt.

**Key properties**:
- `@Binding var context: ObservationContext` — two-way binding to `CameraRootView`'s lifted state.
- `let onSubmit: (ObservationContext) -> Void` — called when the user taps "Identify" / "Add description".
- `@FocusState private var isTextFieldFocused: Bool` — drives the text area border highlight and `.scrollDismissesKeyboard(.interactively)`.
- Auto-rotating prompts (`promptIndex`) cycle every 3 seconds only when `context.freeText.isEmpty && captureMode == .describe`, preventing animation noise while the user is typing.

The `TextEditor` binds to `$context.freeText`. The placeholder is a separate `Text` view rendered when `context.freeText.isEmpty`, with `.allowsHitTesting(false)` so it doesn't intercept taps.

---

## 3. `SpeechManager`

Lives at `merian/Features/Describe/Managers/SpeechManager.swift`. Registered as `var speechManager = SpeechManager()` in `AppDIContainer` and distributed via `.environment(container.speechManager)` in `DIContainerModifier.body()`. Accessed in `CameraRootView` as `@Environment(SpeechManager.self) var speechManager`.

### Class declaration

```swift
@MainActor @Observable final class SpeechManager
```

`@MainActor` aligns with `AppDIContainer` and all other heavy singletons. All property mutations are on the main actor — no explicit `DispatchQueue.main` dispatches are needed for `isRecording` or `onResult` callbacks.

### `PermissionError`

```swift
struct PermissionError: LocalizedError { ... }
```

Thrown exclusively when speech recognition authorization or microphone permission is denied. The `LocalizedError` description is "Microphone access required. Check Settings." — surfaced at the `CameraRootView` call site as `viewModel.offlineToastMessage`.

### `startDictation` lifecycle

```
SFSpeechRecognizer() guard (nil / !isAvailable → silent no-op)
    ↓
SFSpeechRecognizer.requestAuthorization (async continuation)
    ↓ Task.isCancelled check
AVAudioApplication.requestRecordPermission() (async continuation)
    ↓ Task.isCancelled check
teardownAudioEngine()          ← clears any prior session
AVAudioSession configure + activate
    ↓ Task.isCancelled check (deactivates session before returning if true)
SFSpeechAudioBufferRecognitionRequest + recognitionTask
AVAudioEngine installTap → prepare → start()
    ↓
isRecording = true             ← assigned only here, as the final line
```

All operations after the last `await` (microphone permission) are synchronous on `@MainActor`. The `onChange(of: captureMode)` swipe-away handler cannot interleave with this stretch — it is queued on `@MainActor` and runs only at `await` suspension points.

### `teardownAudioEngine` (private)

```swift
audioEngine.stop()                        // no-op if not running
audioEngine.inputNode.removeTap(onBus: 0) // no-op if no tap installed
recognitionRequest?.endAudio()
recognitionTask?.cancel()
recognitionRequest = nil
recognitionTask = nil
try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
```

Both `stop()` and `removeTap(onBus:)` are called **unconditionally**. This prevents an `NSException` crash when `audioEngine.start()` throws after `installTap` was already called — a subsequent `startDictation` call would otherwise attempt to install a second tap on a node that still holds the first.

### Auto-termination

`SFSpeechRecognitionTask` self-terminates after an extended silence (typically ~60 seconds). The result handler detects `error != nil || result.isFinal == true` and calls `stopDictation()` internally, resetting `isRecording = false` without user action.

---

## 4. `CameraRootView` Dictation Wiring

### State additions

```swift
@Environment(SpeechManager.self) var speechManager
@State private var observationContext = ObservationContext()
@State private var dictationTask: Task<Void, Never>?
```

`dictationTask` holds a strong reference to the active async setup task. It is the cancellation handle for the mid-permission-dialog swipe-away scenario.

### `onTranscribe` logic (at `CaptureButton` call site)

```swift
// Stop path — covers both active recording and mid-setup cancellation
if speechManager.isRecording || dictationTask != nil {
    speechManager.stopDictation()
    dictationTask?.cancel()
    dictationTask = nil
    return
}

// Start path
UIApplication.shared.sendAction(
    #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
)
let baseline = observationContext.freeText

dictationTask = Task {
    defer { dictationTask = nil }
    do {
        try await speechManager.startDictation(onResult: { text in
            let separator = baseline.isEmpty ? "" : " "
            observationContext.freeText = baseline + separator + text
        })
    } catch is PermissionError {
        viewModel.offlineToastMessage = "Microphone access required. Check Settings."
    } catch {
        // Silently swallow hardware/OS faults — no user-actionable recovery path
    }
}
```

**Keyboard dismissal**: `resignFirstResponder` fires before `startDictation` to prevent the `TextEditor` from accepting concurrent input while recognition results are streaming. Each `onResult` callback delivers the full cumulative transcription for the current session (not just new words) — `observationContext.freeText = baseline + separator + text` would overwrite anything typed after dictation started.

**Baseline capture**: `baseline` captures `observationContext.freeText` at the moment the mic is tapped. Recognition callbacks prepend it to every result, preserving text the user entered before starting dictation.

**`defer { dictationTask = nil }`**: Runs when the `Task` body exits (success, `PermissionError` catch, or hardware catch). `dictationTask == nil` after normal setup completes, which is why the stop-path guard checks `speechManager.isRecording || dictationTask != nil` — `isRecording` catches the active-recording case after `dictationTask` has already been cleared.

### Swipe-away teardown

Added to the existing `onChange(of: captureMode)` handler inside the `ScrollView`:

```swift
if newMode != .describe {
    dictationTask?.cancel()
    dictationTask = nil
    speechManager.stopDictation()
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
}
```

Cancelling `dictationTask` before calling `stopDictation()` ensures `startDictation` will see `Task.isCancelled == true` at its next check point even if it resumes from a permission prompt after the swipe has completed. `stopDictation()` then cleans up any engine state that managed to start before cancellation was observed.

### `CaptureButton` struct

`private struct CaptureButton: View` accepts four parameters:

| Parameter | Type | Purpose |
|---|---|---|
| `captureMode` | `CaptureMode` | Drives visual style |
| `isRecording` | `Bool` | Drives pulse animation on `mic.fill` |
| `onCapture` | `() -> Void` | Shutter tap in `.visual` mode |
| `onTranscribe` | `() -> Void` | Mic tap in `.describe` mode (toggle) |

---

## 5. Permissions

Both required `Info.plist` strings are already present:

| Key | Value |
|---|---|
| `NSMicrophoneUsageDescription` | "Merian needs microphone access for aviary and insect sound classification." |
| `NSSpeechRecognitionUsageDescription` | "Merian uses speech recognition to quickly search your Scans using voice dictation." |

Permission requests happen inside `startDictation` — not at app launch or onboarding. First-time users see both iOS system permission dialogs on their first mic tap. Subsequent taps skip the dialogs (already authorized). Denial on either dialog causes `startDictation` to throw `PermissionError`, which surfaces as the toast.

---

## 6. AVAudioSession Lifecycle

| Event | Action |
|---|---|
| `startDictation` called | `setCategory(.record, mode: .measurement)` + `setActive(true)` |
| `stopDictation()` called | `setActive(false, options: .notifyOthersOnDeactivation)` via `teardownAudioEngine` |
| Task cancelled mid-setup (after session activated) | `setActive(false, ...)` before returning from `startDictation` |
| `SFSpeechRecognitionTask` auto-terminates | `stopDictation()` → `teardownAudioEngine` → session deactivated |

`notifyOthersOnDeactivation` on deactivation signals the audio subsystem to restore any previously ducked audio (e.g., music playback) once dictation ends. This also ensures the future `AudioRecordingView` pipeline on the `.audio` page can acquire its own `AVAudioSession` cleanly after the user swipes away from `.describe`.

---

## 7. Swift 6 Concurrency

`SpeechManager` is `@MainActor`. All stored properties (`isRecording`, `audioEngine`, `recognitionRequest`, `recognitionTask`) are `@MainActor`-isolated. The `onResult` callback is typed `@MainActor @escaping (String) -> Void` — this guarantees the closure (which captures `@MainActor`-isolated `@State` from `CameraRootView`) executes on `@MainActor` without a `@Sendable` actor-crossing, eliminating Swift 6 strict concurrency warnings at the capture site.

The `AVAudioEngine` tap callback (`installTap`) fires on a private audio thread and appends buffers to `recognitionRequest` — this is safe because `SFSpeechAudioBufferRecognitionRequest.append(_:)` is documented as thread-safe. The recognition result handler dispatches back to `@MainActor` via `Task { @MainActor [weak self] in ... }`.
