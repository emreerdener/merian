# Describe Mode & Voice Dictation

The Describe capture mode is one of the user-orderable pages in
`CaptureWorkspaceView`'s horizontal pager. It allows users to identify a
biological subject through free-text description or live voice dictation instead
of a photograph. The shipped path now routes through the same shared non-visual
`/identify-multimodal` flow used by audio-only captures, via
`CaptureWorkspaceViewModel.submitNonVisualCapture(...)` and
`InferenceEngine.analyzeNonVisual(...)`. `/identify-describe` remains deployed
only as a compatibility route and writes the same ingestion ledger so text-only
legacy rows can recover through `/identify-multimodal`.

---

## 1. Architecture Overview

### State Ownership

`ObservationContext` is a `Codable, Equatable, Sendable` struct with a single
`freeText: String` property and a computed `isEmpty` guard (trims whitespace).
It is the value type that carries the user's input from the UI to
`InferenceEngine`.

`@State private var observationContext = ObservationContext()` lives in
**`CaptureWorkspaceView`**, not in `DescribeInputView`. This lift is required
because `SpeechManager` writes `observationContext.freeText` from outside
`DescribeInputView` during live dictation. `DescribeInputView` receives the
context as `@Binding var context: ObservationContext`.

The context is intentionally not reset after submission, so users can swipe back
to the Describe page and refine their input without losing their text.

### Submission Routing (`CaptureWorkspaceViewModel.submitDescribe`)

`submitDescribe(observationContext:modelContext:)` is an extension on
`CaptureWorkspaceViewModel` in `DescribeAnalysis.swift`. It routes based on what
else is staged:

| Condition                                   | Path                                                                                                                               |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `isMultiCaptureEnabled == true`             | Stages the description in `stagedCapture.observationContexts`, preserving chronological order against any staged image/audio items |
| Images already staged + single-capture mode | Stages the description into the shared mixed-media toolbar state, then `submitStagedCapture` owns the final send                   |
| Nothing else staged                         | Solo non-visual path via `submitDescribeSolo`, which delegates to `submitNonVisualCapture`                                         |

`submitDescribeSolo` mirrors the resilience pattern of the other capture paths:
it always inserts a zero-byte `.staged` nonvisual queue row before any provider
dispatch. An eligible online request persists and carries a foreground inference
UUID into `InferenceEngine.analyzeNonVisual`; an offline request retains the
same durable row, skips the live engine, and surfaces a queued toast. Because
Describe shares `submitNonVisualCapture`, it also consumes an existing
environment prefetch or resolves the pinned cached location before persistence;
a description-only scan can therefore produce the same privacy-filtered Explore
location label as a visual or audio scan.

**Submission rule**: descriptions participate in the same 2-item total capacity
as images and audio clips. Supported combinations are any one- or two-item
mixture across those three modalities.

---

## 2. Guided Question System

### `GuidedQuestion` & `GuidedQuestion.Tag` (`Features/Capture/Describe/Models/GuidedQuestion.swift`)

`GuidedQuestion` is the primitive that drives the tag-sheet carousel. Each
question has a `prompt: String` and a `tags: [Tag]` array. A `Tag` carries:

| Field           | Type      | Purpose                                                                            |
| --------------- | --------- | ---------------------------------------------------------------------------------- |
| `tagId`         | `String`  | Stable identifier used for funnel keying and selection state                       |
| `label`         | `String`  | Display text on the tag chip                                                       |
| `aiText`        | `String`  | Natural-language fragment appended to `freeText` when tapped                       |
| `defaultWeight` | `Int`     | Sort priority within the question                                                  |
| `imageName`     | `String?` | Asset catalog name for image-tile rendering (non-nil on the subject question only) |

Tags with a non-nil `imageName` render as 96×104 pt
`RoundedRectangle(cornerRadius: 16)` tiles (image above label). All others
render as `Capsule` text chips. The subject question (index 0) uses image tiles
for all 9 entries (Bird, Insect, Spider, Reptile, Plant, Mushroom, Mammal, Fish,
Other). The `Other` tag has `aiText: ""` — selecting it appends nothing to
`freeText`, leaving the AI prompt unchanged.

The global `guidedQuestions: [GuidedQuestion]` array has 9 entries:

| Index | Prompt                                                                          |
| ----- | ------------------------------------------------------------------------------- |
| 0     | "What did you find?" — subject selector (image tiles, activates species funnel) |
| 1     | "What was the surrounding environment like?"                                    |
| 2     | "Where exactly did you spot it?"                                                |
| 3     | "Roughly how big was it?"                                                       |
| 4     | "How would you describe its overall shape?"                                     |
| 5     | "Did you notice any distinct features, like wings or a shell?"                  |
| 6     | "Did it have any distinct colors or patterns?"                                  |
| 7     | "What was it doing when you observed it?"                                       |
| 8     | "Was it alone, or in a group?"                                                  |
| 9     | "Are there any other interesting details you noticed?" — text-only (`tags: []`) |

---

### `SubjectFunnels` (`Features/Capture/Describe/Models/SubjectFunnels.swift`)

`let subjectFunnels: [String: [GuidedQuestion]]` maps each subject `tagId` to a
4–5 question species-specific funnel. When a subject is selected,
`DescribePromptManager.activateFunnel(for:)` prepends the subject question
(index 0), inserts the funnel, and appends three shared telemetry questions
(environment, location, open-ended) to form the `activeQuestions` array.

Defined funnels:

| `tagId`      | Subject  | Funnel questions                                        |
| ------------ | -------- | ------------------------------------------------------- |
| `subj_bird`  | Bird     | Type of bird · Size · Beak shape · Plumage · Behavior   |
| `subj_insec` | Insect   | Insect type · Wing visibility · Body texture · Markings |
| `subj_plan`  | Plant    | Plant type · Leaf shape · Flower presence · Habitat     |
| `subj_mush`  | Mushroom | Cap shape · Color · Habitat · Stalk                     |
| `subj_spid`  | Spider   | Body size · Web presence · Color · Leg count            |
| `subj_rept`  | Reptile  | Type · Scale pattern · Limb presence · Behavior         |
| `subj_mamm`  | Mammal   | Size · Fur color · Tail · Behavior                      |
| `subj_fish`  | Fish     | Body shape · Fin pattern · Scale color · Habitat        |

(`subj_othr` has no entry in `subjectFunnels` —
`activateFunnel(for: "subj_othr")` silently no-ops.)

---

### `SubjectKeywordMatcher` (`Features/Capture/Describe/Models/SubjectKeywordMatcher.swift`)

A pure static struct. `infer(from: String) -> String?` lowercases and tokenizes
the input, then looks each word up in a static `[String: String]` keyword table.
Returns the first matching subject `tagId` or `nil`. Covers ~50 common-name
keywords across all 8 subject types (e.g. `"hawk"` → `"subj_bird"`, `"beetle"` →
`"subj_insec"`, `"frog"` → `"subj_rept"`). Used by `DescribeInputView` to
auto-activate a funnel from typed or dictated text.

---

### `DescribePromptManager` — Funnel State (`Features/Capture/Describe/Managers/DescribePromptManager.swift`)

New funnel-state properties added alongside the existing `activeQuestionIndex`
and `interactedQuestionIndices`:

| Property          | Type               | Purpose                                                                         |
| ----------------- | ------------------ | ------------------------------------------------------------------------------- |
| `activeSubjectId` | `String?`          | `tagId` of the currently selected subject (`nil` = no funnel)                   |
| `activeQuestions` | `[GuidedQuestion]` | The live question list — either `guidedQuestions` or a funnel-customized subset |
| `isFunnelActive`  | `Bool` (computed)  | `activeSubjectId != nil`                                                        |

**`activateFunnel(for subjectId: String)`**: guards `subjectFunnels[subjectId]`
exists, sets `activeSubjectId`, builds `activeQuestions` as
`[guidedQuestions[0]] + funnel + [guidedQuestions[1], guidedQuestions[2], guidedQuestions.last!]`,
resets `interactedQuestionIndices`, and advances `activeQuestionIndex` to 1
(stepping past the subject question the user just answered).

**`resetFunnel()`**: sets `activeSubjectId = nil`, restores
`activeQuestions = guidedQuestions`, resets `interactedQuestionIndices`, and
resets `activeQuestionIndex = 0`.

---

## 3. `DescribeInputView`

Lives at
`apps/ios/Merian/Features/Capture/Describe/Views/DescribeInputView.swift`.

**Layout contract**: fills the full page frame. The fixed `MediaModeToggle`
overlay sits above it in the `CaptureWorkspaceView` Z-stack and must remain
interactive — no content above `safeAreaInsets.top + 64` pt.

**Key properties**:

- `@Binding var context: ObservationContext` — two-way binding to
  `CaptureWorkspaceView`'s lifted state.
- `@FocusState private var isTextFieldFocused: Bool` — drives the text area
  border highlight.
- `let promptManager: DescribePromptManager` — workspace-owned prompt state used
  to render and edit the guided question funnel.

The multiline `TextField` binds to `$context.freeText` and exposes the stable
`DescribeTextInput` UI-test identifier. Its intrinsic content sits at the top of
the flexible rounded `DescribeTextArea`; the container's explicit rounded
interaction shape forwards taps into `isTextFieldFocused`, so the empty space
below the field remains a typing target instead of becoming a dead zone.

`DescribeInputView` is deliberately render-only. Its full-page vertical content
uses `DescribeVerticalScrollView`, a UIKit `UIScrollView` containing a
`UIHostingController`. That boundary preserves vertical scrolling and drag-to-
dismiss keyboard behavior without putting a nested SwiftUI vertical scroll graph
inside the workspace's horizontal SwiftUI pager. Replacing it requires strict
AttributeGraph cold-launch testing for all three configurable first modes.

### Tag Rendering

The tag strip iterates `promptManager.activeQuestions` (not the static
`guidedQuestions`). Each tag is rendered conditionally:

- **Non-nil `imageName`** → 96×104 pt tile
  (`RoundedRectangle(cornerRadius: 16)`): `Image(imageName)` (56×56 pt
  `.scaledToFit`) above the label. Background is `.primary` / foreground
  `.systemBackground` when selected as the active funnel subject; otherwise
  `.secondarySystemBackground` / `.primary`.
- **Nil `imageName`** → standard `Capsule` chip. Same selection-state colour
  logic applies.

The tag scroll view carries
`.id("tags_scroll_\(promptManager.activeQuestionIndex)")` so `ScrollViewReader`
can snap to the correct tag row when the question advances.

### Funnel Lifecycle

**Subject tap → funnel activation**: On the subject question (index 0), tapping
a tag checks `promptManager.activeSubjectId == tag.tagId`. If the tag is already
the active subject (toggle-off), `promptManager.resetFunnel()` is called and the
tags are re-sorted. Otherwise, the normal `appendTag` path runs, then
`promptManager.activateFunnel(for: tag.tagId)` is called, advancing to the first
funnel question. Auto-advance is suppressed when `isSelectedFunnel == true` to
prevent double-stepping.

**Text-driven auto-activation (1.5s debounce)** is owned by the zero-sized
`DescribeInputLifecycleObserver` mounted in `CaptureWorkspaceView`, outside the
pager:

1. If `freeText` is empty → `promptManager.resetFunnel()` and early return.
2. If `isFunnelActive` → no-op (funnel already running).
3. Otherwise: the text-keyed SwiftUI task sleeps 1.5 seconds, then calls
   `SubjectKeywordMatcher.infer(from: freeText)`. If a subject is inferred,
   `promptManager.activateFunnel(for: subjectId)` activates the funnel. Useful
   when the user dictates "I saw a hawk" before tapping any tags — the funnel
   activates automatically after typing settles.

SwiftUI automatically cancels the keyed task when the text changes again. The
same observer configures reanalysis prompt flow, owns dictation start/stop, and
requests the questions sheet. `CaptureWorkspaceView` owns the prompt manager and
sheet presentation so those state transitions do not occur inside the pager's
layout graph.

---

## 4. `SpeechManager`

Lives at
`apps/ios/Merian/Features/Capture/Describe/Managers/SpeechManager.swift`.
Registered as `var speechManager = SpeechManager()` in `AppDIContainer` and
distributed via `.environment(container.speechManager)` in
`DIContainerModifier.body()`. `DescribeInputLifecycleObserver` reads it through
`@Environment(SpeechManager.self)` outside the horizontal pager.

### Class declaration

```swift
@MainActor @Observable final class SpeechManager
```

`@MainActor` aligns with `AppDIContainer` and all other heavy singletons. All
property mutations are on the main actor — no explicit `DispatchQueue.main`
dispatches are needed for `isRecording` or `onResult` callbacks.

### Startup errors

```swift
struct PermissionError: LocalizedError { ... }
struct DictationUnavailableError: LocalizedError { ... }
```

Thrown when speech-recognition or microphone permission is denied, and when the
audio input reports an unusable zero-Hz format. Its localized description is
"Microphone access required. Check device settings." The lifecycle observer
returns the dictation control to idle after any startup failure.

`DictationUnavailableError` is thrown when five bounded recognizer checks,
spaced 200 ms apart, cannot obtain an available speech recognizer. Its localized
description is "Dictation is temporarily unavailable. Please try again." This is
distinct from permission denial and remains retryable without changing Settings.

### `startDictation` lifecycle

```
SFSpeechRecognizer.requestAuthorization (async continuation)
    ↓ Task.isCancelled check
availableSpeechRecognizer() (bounded availability retry)
    ↓
AVAudioApplication.requestRecordPermission() (async continuation)
    ↓ Task.isCancelled check
teardownAudioEngine()          ← clears any prior session
AudioSessionCoordinator.activate(.recordMeasurement) in detached setup
    ↓ lease stored on SpeechManager
AVAudioEngine input/tap negotiation → prepare → start()
    ↓ Task.isCancelled check (deactivates session before returning if true)
SFSpeechAudioBufferRecognitionRequest + recognitionTask
    ↓
isRecording = true             ← assigned only here, as the final line
```

The detached setup prevents AVAudioSession/input negotiation from blocking the
main actor. Cancellation is checked after every permission/availability await
and again after detached engine startup; cancellation cleanup releases only the
lease owned by this dictation attempt.

### `teardownAudioEngine` (private)

```swift
audioEngine.stop()                        // no-op if not running
audioEngine.inputNode.removeTap(onBus: 0) // no-op if no tap installed
recognitionRequest?.endAudio()
recognitionTask?.finish()
recognitionRequest = nil
recognitionTask = nil
audioSessionLease = nil
Task { await AudioSessionCoordinator.shared.deactivate(ifCurrent: lease) }
```

Both `stop()` and `removeTap(onBus:)` are called **unconditionally**. This
prevents an `NSException` crash when `audioEngine.start()` throws after
`installTap` was already called — a subsequent `startDictation` call would
otherwise attempt to install a second tap on a node that still holds the first.

### Auto-termination

`SFSpeechRecognitionTask` self-terminates after an extended silence (typically
~60 seconds). The result handler detects
`error != nil || result.isFinal == true` and calls `stopDictation()` internally,
resetting `isRecording = false` without user action.

---

## 5. Workspace Dictation and Sheet Wiring

`CaptureActionCoordinator` is the intent boundary between fixed capture chrome
and Describe lifecycle state:

- `CaptureControlBar` toggles `isDictationRequested` and assigns a new
  `tocRequestID`; it does not own speech tasks or sheet presentation.
- `DescribeInputLifecycleObserver` observes those intents outside the pager. It
  captures the existing text as a baseline, starts `SpeechManager`, appends live
  cumulative transcription, and mirrors automatic speech termination back to the
  coordinator.
- Leaving Describe, removing the workspace, or toggling dictation off calls the
  shared stop path. It stops the speech engine, cancels setup, clears task
  state, and resets the coordinator flag, including the mid-permission-dialog
  case.
- `CaptureWorkspaceView` owns `isDescribeQuestionsSheetPresented` and applies
  `DescribeQuestionsSheet` at workspace scope. Reanalysis suppresses that sheet.

This split is part of the startup stability contract: the Describe page renders
prompt state but does not attach reactive tasks or sheet hosts to the nested
page hierarchy.

---

## 6. Permissions

Both required `Info.plist` strings are already present:

| Key                                   | Value                                                                                    |
| ------------------------------------- | ---------------------------------------------------------------------------------------- |
| `NSMicrophoneUsageDescription`        | "Naturebook needs microphone access for aviary and insect sound classification."         |
| `NSSpeechRecognitionUsageDescription` | "Naturebook uses speech recognition to quickly search your Scans using voice dictation." |

Permission requests happen inside `startDictation` — not at app launch or
onboarding. First-time users see both iOS system permission dialogs on their
first mic tap. Subsequent taps skip the dialogs (already authorized). Denial on
either dialog causes `startDictation` to throw `PermissionError`; the lifecycle
observer clears the dictation request so the control returns to its idle state.

---

## 7. AVAudioSession Lifecycle

| Event                                              | Action                                                                                            |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `startDictation` called                            | Acquires a `.recordMeasurement` lease from `AudioSessionCoordinator`                              |
| `stopDictation()` called                           | Tears down recognition and asks the coordinator to deactivate only if this lease is still current |
| Task cancelled mid-setup (after session activated) | `handleCancelledStartup()` tears down and releases the owned lease                                |
| `SFSpeechRecognitionTask` auto-terminates          | `stopDictation()` → `teardownAudioEngine()` → token-aware deactivation                            |

The lease prevents delayed teardown from one mode from deactivating a newer
audio owner. This lets `AudioCaptureManager` acquire its own recording lease
cleanly after the user leaves Describe, even when stop/start work overlaps.

---

## 8. Swift 6 Concurrency

`SpeechManager` is `@MainActor`. All stored properties (`isRecording`,
`audioEngine`, `recognitionRequest`, `recognitionTask`) are
`@MainActor`-isolated. The `onResult` callback is typed
`@MainActor @escaping (String) -> Void` — this guarantees the closure (which
captures `@MainActor`-isolated `@State` from `CaptureWorkspaceView`) executes on
`@MainActor` without a `@Sendable` actor-crossing, eliminating Swift 6 strict
concurrency warnings at the capture site.

The `AVAudioEngine` tap callback (`installTap`) fires on a private audio thread
and appends buffers to `recognitionRequest` — this is safe because
`SFSpeechAudioBufferRecognitionRequest.append(_:)` is documented as thread-safe.
The recognition result handler dispatches back to `@MainActor` via
`Task { @MainActor [weak self] in ... }`.

## 2026-04 Hardening Updates

- `startDictation` cancellation now always tears the engine back down, even if
  cancellation happens after the audio session was activated and the tap was
  installed.
- `handleCancelledStartup()` now resets `audioLevel` and `isRecording` in
  addition to calling `teardownAudioEngine()`, so a failed startup cannot leave
  stale level-meter or recording UI behind.
- The dictation lifecycle contract is now "activate late, teardown on every
  failure path, and never rely on the happy-path stop call to release engine
  resources."

## 2026-07 Workspace and Startup Hardening

- `DescribeInputView` is render-only inside the lazy horizontal pager; UIKit
  owns its vertical scroll container.
- `DescribeInputLifecycleObserver`, prompt state, and prompt-sheet presentation
  live at workspace scope so their reactive tasks cannot participate in page
  layout.
- Leaving Describe or removing the workspace stops both live and still-starting
  dictation, cancels the task, and clears the requested state.
- `DescribePrompts` is the stable UI-test identifier for the prompt-list button.
  `merianUITests.testDescribeFirstLaunchRendersAndOpensPrompts` verifies the
  Description-first render and sheet route. It also verifies that prompt,
  submit, and dictation controls share a centerline and that the rounded editor
  retains 8...32 pt of rendered clearance above them. The editor reserves the
  row's fixed 204 pt `CaptureControlBarLayout.describeContentBottomClearance`
  inside its UIKit-hosted scroll content and flexes to consume the remaining
  height. At the top, the hosted page reserves only a fixed 60 pt selector band
  because its origin is already safe-area adjusted. UI coverage requires an
  8...32 pt gap from `CaptureModeToggle` to `DescribeQuestionNavigation`,
  preventing duplicate top-safe-area padding.
- `merianUITests.testDescribeTextAreaFocusesFromLowerRegion` taps below the
  multiline field's intrinsic frame and types through the newly focused input,
  locking the full rounded editor as the interaction target.
