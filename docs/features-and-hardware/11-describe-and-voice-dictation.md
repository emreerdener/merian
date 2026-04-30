# Describe Mode & Voice Dictation

The Describe capture mode is the third page of `CaptureWorkspaceView`'s horizontal pager. It allows users to identify a biological subject through free-text description or live voice dictation instead of a photograph. The shipped path now routes through the same shared non-visual `/identify-multimodal` flow used by audio-only captures, via `CaptureWorkspaceViewModel.submitNonVisualCapture(...)` and `InferenceEngine.analyzeNonVisual(...)`.

---

## 1. Architecture Overview

### State Ownership

`ObservationContext` is a `Codable, Equatable, Sendable` struct with a single `freeText: String` property and a computed `isEmpty` guard (trims whitespace). It is the value type that carries the user's input from the UI to `InferenceEngine`.

`@State private var observationContext = ObservationContext()` lives in **`CaptureWorkspaceView`**, not in `DescribeInputView`. This lift is required because `SpeechManager` writes `observationContext.freeText` from outside `DescribeInputView` during live dictation. `DescribeInputView` receives the context as `@Binding var context: ObservationContext`.

The context is intentionally not reset after submission, so users can swipe back to the Describe page and refine their input without losing their text.

### Submission Routing (`CaptureWorkspaceViewModel.submitDescribe`)

`submitDescribe(observationContext:modelContext:)` is an extension on `CaptureWorkspaceViewModel` in `DescribeAnalysis.swift`. It routes based on what else is staged:

| Condition | Path |
|---|---|
| `isMultiCaptureEnabled == true` | Stages the description in `stagedCapture.observationContexts`, preserving chronological order against any staged image/audio items |
| Images already staged + single-capture mode | Stages the description into the shared mixed-media toolbar state, then `submitStagedCapture` owns the final send |
| Nothing else staged | Solo non-visual path via `submitDescribeSolo`, which delegates to `submitNonVisualCapture` |

`submitDescribeSolo` mirrors the resilience pattern of the other capture paths: if online, opens the insight sheet and fires `InferenceEngine.analyzeNonVisual`; if offline, enqueues through the durable non-visual queue path with cached GPS telemetry and surfaces a toast.

**Submission rule**: descriptions participate in the same 2-item total capacity as images and audio clips. Supported combinations are any one- or two-item mixture across those three modalities.

---

## 2. Guided Question System

### `GuidedQuestion` & `GuidedQuestion.Tag` (`Features/Describe/Models/GuidedQuestion.swift`)

`GuidedQuestion` is the primitive that drives the tag-sheet carousel. Each question has a `prompt: String` and a `tags: [Tag]` array. A `Tag` carries:

| Field | Type | Purpose |
|---|---|---|
| `tagId` | `String` | Stable identifier used for funnel keying and selection state |
| `label` | `String` | Display text on the tag chip |
| `aiText` | `String` | Natural-language fragment appended to `freeText` when tapped |
| `defaultWeight` | `Int` | Sort priority within the question |
| `imageName` | `String?` | Asset catalog name for image-tile rendering (non-nil on the subject question only) |

Tags with a non-nil `imageName` render as 96×104 pt `RoundedRectangle(cornerRadius: 16)` tiles (image above label). All others render as `Capsule` text chips. The subject question (index 0) uses image tiles for all 9 entries (Bird, Insect, Spider, Reptile, Plant, Mushroom, Mammal, Fish, Other). The `Other` tag has `aiText: ""` — selecting it appends nothing to `freeText`, leaving the AI prompt unchanged.

The global `guidedQuestions: [GuidedQuestion]` array has 9 entries:

| Index | Prompt |
|---|---|
| 0 | "What did you find?" — subject selector (image tiles, activates species funnel) |
| 1 | "What was the surrounding environment like?" |
| 2 | "Where exactly did you spot it?" |
| 3 | "Roughly how big was it?" |
| 4 | "How would you describe its overall shape?" |
| 5 | "Did you notice any distinct features, like wings or a shell?" |
| 6 | "Did it have any distinct colors or patterns?" |
| 7 | "What was it doing when you observed it?" |
| 8 | "Was it alone, or in a group?" |
| 9 | "Are there any other interesting details you noticed?" — text-only (`tags: []`) |

---

### `SubjectFunnels` (`Features/Describe/Models/SubjectFunnels.swift`)

`let subjectFunnels: [String: [GuidedQuestion]]` maps each subject `tagId` to a 4–5 question species-specific funnel. When a subject is selected, `DescribePromptManager.activateFunnel(for:)` prepends the subject question (index 0), inserts the funnel, and appends three shared telemetry questions (environment, location, open-ended) to form the `activeQuestions` array.

Defined funnels:

| `tagId` | Subject | Funnel questions |
|---|---|---|
| `subj_bird` | Bird | Type of bird · Size · Beak shape · Plumage · Behavior |
| `subj_insec` | Insect | Insect type · Wing visibility · Body texture · Markings |
| `subj_plan` | Plant | Plant type · Leaf shape · Flower presence · Habitat |
| `subj_mush` | Mushroom | Cap shape · Color · Habitat · Stalk |
| `subj_spid` | Spider | Body size · Web presence · Color · Leg count |
| `subj_rept` | Reptile | Type · Scale pattern · Limb presence · Behavior |
| `subj_mamm` | Mammal | Size · Fur color · Tail · Behavior |
| `subj_fish` | Fish | Body shape · Fin pattern · Scale color · Habitat |

(`subj_othr` has no entry in `subjectFunnels` — `activateFunnel(for: "subj_othr")` silently no-ops.)

---

### `SubjectKeywordMatcher` (`Features/Describe/Models/SubjectKeywordMatcher.swift`)

A pure static struct. `infer(from: String) -> String?` lowercases and tokenizes the input, then looks each word up in a static `[String: String]` keyword table. Returns the first matching subject `tagId` or `nil`. Covers ~50 common-name keywords across all 8 subject types (e.g. `"hawk"` → `"subj_bird"`, `"beetle"` → `"subj_insec"`, `"frog"` → `"subj_rept"`). Used by `DescribeInputView` to auto-activate a funnel from typed or dictated text.

---

### `DescribePromptManager` — Funnel State (`Features/Describe/Managers/DescribePromptManager.swift`)

New funnel-state properties added alongside the existing `activeQuestionIndex` and `interactedQuestionIndices`:

| Property | Type | Purpose |
|---|---|---|
| `activeSubjectId` | `String?` | `tagId` of the currently selected subject (`nil` = no funnel) |
| `activeQuestions` | `[GuidedQuestion]` | The live question list — either `guidedQuestions` or a funnel-customized subset |
| `isFunnelActive` | `Bool` (computed) | `activeSubjectId != nil` |

**`activateFunnel(for subjectId: String)`**: guards `subjectFunnels[subjectId]` exists, sets `activeSubjectId`, builds `activeQuestions` as `[guidedQuestions[0]] + funnel + [guidedQuestions[1], guidedQuestions[2], guidedQuestions.last!]`, resets `interactedQuestionIndices`, and advances `activeQuestionIndex` to 1 (stepping past the subject question the user just answered).

**`resetFunnel()`**: sets `activeSubjectId = nil`, restores `activeQuestions = guidedQuestions`, resets `interactedQuestionIndices`, and resets `activeQuestionIndex = 0`.

---

## 3. `DescribeInputView`

Lives at `merian/Features/Describe/Views/DescribeInputView.swift`.

**Layout contract**: fills the full page frame. The fixed `MediaModeToggle` overlay sits above it in the `CaptureWorkspaceView` Z-stack and must remain interactive — no content above `safeAreaInsets.top + 64` pt.

**Key properties**:
- `@Binding var context: ObservationContext` — two-way binding to `CaptureWorkspaceView`'s lifted state.
- `let onSubmit: (ObservationContext) -> Void` — called when the user taps "Identify" / "Add description".
- `@FocusState private var isTextFieldFocused: Bool` — drives the text area border highlight and `.scrollDismissesKeyboard(.interactively)`.
- `@State private var inferenceDebounceTask: Task<Void, Never>?` — holds the 1.5-second debounce task for keyword-based funnel auto-activation.
- Auto-rotating prompts (`promptIndex`) cycle every 3 seconds only when `context.freeText.isEmpty && captureMode == .describe`, preventing animation noise while the user is typing.

The `TextEditor` binds to `$context.freeText`. The placeholder is a separate `Text` view rendered when `context.freeText.isEmpty`, with `.allowsHitTesting(false)` so it doesn't intercept taps.

### Tag Rendering

The tag strip iterates `promptManager.activeQuestions` (not the static `guidedQuestions`). Each tag is rendered conditionally:
- **Non-nil `imageName`** → 96×104 pt tile (`RoundedRectangle(cornerRadius: 16)`): `Image(imageName)` (56×56 pt `.scaledToFit`) above the label. Background is `.primary` / foreground `.systemBackground` when selected as the active funnel subject; otherwise `.secondarySystemBackground` / `.primary`.
- **Nil `imageName`** → standard `Capsule` chip. Same selection-state colour logic applies.

The tag scroll view carries `.id("tags_scroll_\(promptManager.activeQuestionIndex)")` so `ScrollViewReader` can snap to the correct tag row when the question advances.

### Funnel Lifecycle in `DescribeInputView`

**Subject tap → funnel activation**: On the subject question (index 0), tapping a tag checks `promptManager.activeSubjectId == tag.tagId`. If the tag is already the active subject (toggle-off), `promptManager.resetFunnel()` is called and the tags are re-sorted. Otherwise, the normal `appendTag` path runs, then `promptManager.activateFunnel(for: tag.tagId)` is called, advancing to the first funnel question. Auto-advance is suppressed when `isSelectedFunnel == true` to prevent double-stepping.

**Text-driven auto-activation (1.5s debounce)**: `onChange(of: context.freeText)`:
1. If `freeText` is empty → `promptManager.resetFunnel()` and early return.
2. If `isFunnelActive` → no-op (funnel already running).
3. Otherwise: cancel any in-flight `inferenceDebounceTask`, start a new `Task` that sleeps 1.5 seconds, then calls `SubjectKeywordMatcher.infer(from: freeText)`. If a subject is inferred, `promptManager.activateFunnel(for: subjectId)` activates the funnel. Useful when the user dictates "I saw a hawk" before tapping any tags — the funnel activates automatically after typing settles.

**Funnel reset on submit**: `inferenceDebounceTask?.cancel()` is called before `onSubmit` fires, preventing a race where a pending debounce activates a funnel after the submission has already started.

---

## 4. `SpeechManager`

Lives at `merian/Features/Describe/Managers/SpeechManager.swift`. Registered as `var speechManager = SpeechManager()` in `AppDIContainer` and distributed via `.environment(container.speechManager)` in `DIContainerModifier.body()`. Accessed in `CaptureWorkspaceView` as `@Environment(SpeechManager.self) var speechManager`.

### Class declaration

```swift
@MainActor @Observable final class SpeechManager
```

`@MainActor` aligns with `AppDIContainer` and all other heavy singletons. All property mutations are on the main actor — no explicit `DispatchQueue.main` dispatches are needed for `isRecording` or `onResult` callbacks.

### `PermissionError`

```swift
struct PermissionError: LocalizedError { ... }
```

Thrown exclusively when speech recognition authorization or microphone permission is denied. The `LocalizedError` description is "Microphone access required. Check Settings." — surfaced at the `CaptureWorkspaceView` call site as `viewModel.offlineToastMessage`.

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

## 5. `CaptureWorkspaceView` Dictation Wiring

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

## 6. Permissions

Both required `Info.plist` strings are already present:

| Key | Value |
|---|---|
| `NSMicrophoneUsageDescription` | "Merian needs microphone access for aviary and insect sound classification." |
| `NSSpeechRecognitionUsageDescription` | "Merian uses speech recognition to quickly search your Scans using voice dictation." |

Permission requests happen inside `startDictation` — not at app launch or onboarding. First-time users see both iOS system permission dialogs on their first mic tap. Subsequent taps skip the dialogs (already authorized). Denial on either dialog causes `startDictation` to throw `PermissionError`, which surfaces as the toast.

---

## 7. AVAudioSession Lifecycle

| Event | Action |
|---|---|
| `startDictation` called | `setCategory(.record, mode: .measurement)` + `setActive(true)` |
| `stopDictation()` called | `setActive(false, options: .notifyOthersOnDeactivation)` via `teardownAudioEngine` |
| Task cancelled mid-setup (after session activated) | `setActive(false, ...)` before returning from `startDictation` |
| `SFSpeechRecognitionTask` auto-terminates | `stopDictation()` → `teardownAudioEngine` → session deactivated |

`notifyOthersOnDeactivation` on deactivation signals the audio subsystem to restore any previously ducked audio (e.g., music playback) once dictation ends. This also ensures `AudioCaptureManager` on the `.audio` page can acquire its own `AVAudioSession` cleanly after the user swipes away from `.describe`. Both `SpeechManager` and `AudioCaptureManager` use the same `.record` / `.measurement` session category and the same `Task.detached` activation pattern — whichever page the user is on last cleanly deactivates before the other activates.

---

## 8. Swift 6 Concurrency

`SpeechManager` is `@MainActor`. All stored properties (`isRecording`, `audioEngine`, `recognitionRequest`, `recognitionTask`) are `@MainActor`-isolated. The `onResult` callback is typed `@MainActor @escaping (String) -> Void` — this guarantees the closure (which captures `@MainActor`-isolated `@State` from `CaptureWorkspaceView`) executes on `@MainActor` without a `@Sendable` actor-crossing, eliminating Swift 6 strict concurrency warnings at the capture site.

The `AVAudioEngine` tap callback (`installTap`) fires on a private audio thread and appends buffers to `recognitionRequest` — this is safe because `SFSpeechAudioBufferRecognitionRequest.append(_:)` is documented as thread-safe. The recognition result handler dispatches back to `@MainActor` via `Task { @MainActor [weak self] in ... }`.

## 2026-04 Hardening Updates

- `startDictation` cancellation now always tears the engine back down, even if cancellation happens after the audio session was activated and the tap was installed.
- `handleCancelledStartup()` now resets `audioLevel` and `isRecording` in addition to calling `teardownAudioEngine()`, so a failed startup cannot leave stale level-meter or recording UI behind.
- The dictation lifecycle contract is now "activate late, teardown on every failure path, and never rely on the happy-path stop call to release engine resources."
