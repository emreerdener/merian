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
because workspace-scoped dictation writes `observationContext.freeText` from
outside `DescribeInputView`. `DescribeInputViewModel` receives transcription
through an injected `SpeechManager` adapter, generation-fences it, and returns a
composed string to `DescribeInputLifecycleObserver`; the observer alone mutates
the binding. `DescribeInputView` receives the context as
`@Binding var context: ObservationContext`.

The context is intentionally not reset after submission, so users can swipe back
to the Describe page and refine their input without losing their text.

Describe is organized by responsibility:

- `Models/` owns prompt/subject values, deterministic text composition, and tag
  ranking.
- `Services/` owns live `UserDefaults`, haptic, UIKit keyboard, subject-delay,
  and speech-manager adapters.
- `ViewModels/` owns prompt state plus delayed-inference and dictation session
  generations.
- `Views/` owns the page, workspace observer, focus, and sheet presentation.
- `Components/` owns the UIKit scroll host, prompt navigation/tags, and editor.

Presentation files resolve no singleton or platform action. Cross-feature speech
hardware lives in `Core/Hardware`, not under Capture Describe.

### Submission Routing (`CaptureWorkspaceViewModel.submitDescribe`)

`submitDescribe(observationContext:modelContext:)` is an extension on
`CaptureWorkspaceViewModel` in
`CaptureWorkspaceViewModel+DescribeSubmission.swift`. It routes based on what
else is staged:

| Condition                                   | Path                                                                                                                               |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `isMultiCaptureEnabled == true`             | Stages the description in `stagedCapture.observationContexts`, preserving chronological order against any staged image/audio items |
| Images already staged + single-capture mode | Stages the description into the shared mixed-media toolbar state, then `submitStagedCapture` owns the final send                   |
| Nothing else staged                         | Solo non-visual path via `submitDescribeSolo`, which delegates to `submitNonVisualCapture`                                         |

`submitDescribeSolo` mirrors the resilience pattern of the other capture paths:
it always inserts a zero-byte `.staged` nonvisual queue row before any provider
dispatch. A still-online foreground route persists and carries a foreground
inference UUID into `InferenceEngine.analyzeNonVisual`; an offline or typed
queue-only route retains the same durable row, skips the live engine, and
surfaces a queued toast. Because Describe shares `submitNonVisualCapture`, it
also consumes an existing environment prefetch or starts a lookup from the
pinned cached location. Cached telemetry is persisted first; only after queue
acceptance does the optional context receive a 150 ms live-request grace, with a
later result merged locally and through `/update-scan-context`. A branch with no
foreground consumer cancels the lookup. A description-only scan can therefore
produce the same privacy-filtered Explore location label as a visual or audio
scan without making WeatherKit or geocoding a durability dependency.

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

Tags with a non-nil `imageName` render as 96×112 pt
`RoundedRectangle(cornerRadius: 16)` tiles (image above label). All others
render as `Capsule` text chips. The subject question (index 0) uses image tiles
for all 9 entries (Bird, Insect, Spider, Reptile, Plant, Mushroom, Mammal, Fish,
Other). The `Other` tag has `aiText: ""` — selecting it appends nothing to
`freeText`, leaving the AI prompt unchanged.

The global `guidedQuestions: [GuidedQuestion]` array has 10 entries:

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
4–6 question subject-specific funnel. When a subject is selected,
`DescribePromptViewModel.activateFunnel(for:)` prepends the subject question
(index 0), inserts the funnel, and appends three shared telemetry questions
(environment, location, open-ended) to form the `activeQuestions` array.

Defined funnels:

| `tagId`      | Subject  | Funnel questions                                          |
| ------------ | -------- | --------------------------------------------------------- |
| `subj_bird`  | Bird     | Type of bird · Size · Beak shape · Plumage · Behavior     |
| `subj_insec` | Insect   | Insect type · Wing visibility · Body texture · Markings   |
| `subj_plan`  | Plant    | Plant type · Leaf shape · Flower presence · Habitat       |
| `subj_mush`  | Mushroom | Cap shape · Color · Habitat · Stalk                       |
| `subj_spid`  | Spider   | Body size · Web presence · Color · Leg count              |
| `subj_rept`  | Reptile  | Type · Scale pattern · Limb presence · Behavior           |
| `subj_mamm`  | Mammal   | Size · Fur color · Tail · Behavior                        |
| `subj_fish`  | Fish     | Body shape · Fin pattern · Scale color · Habitat          |
| `subj_othr`  | Other    | Size · Shape · Details · Colors · Action · Social context |

The `subj_othr` fallback reuses six general morphology and behavior questions
instead of a taxon-specific prompt set.

---

### `SubjectKeywordMatcher` (`Features/Capture/Describe/Models/SubjectKeywordMatcher.swift`)

A pure static struct. `infer(from: String) -> String?` lowercases and tokenizes
the input, then looks each word up in a static `[String: String]` keyword table.
Returns the first matching subject `tagId` or `nil`. Covers ~50 common-name
keywords across all 8 subject types (e.g. `"hawk"` → `"subj_bird"`, `"beetle"` →
`"subj_insec"`, `"frog"` → `"subj_rept"`). Used by `DescribeInputViewModel` to
auto-activate a funnel from typed or dictated text.

---

### `DescribePromptViewModel` — Funnel State (`Features/Capture/Describe/ViewModels/DescribePromptViewModel.swift`)

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
- `let promptViewModel: DescribePromptViewModel` — workspace-owned prompt state
  used to render and edit the guided question funnel.
- `DescribePresentationDependencies` — narrow tag-frequency, selection feedback,
  and keyboard-dismiss actions constructed by Describe Services.

The multiline `TextField` binds to `$context.freeText` and exposes the stable
`DescribeTextInput` UI-test identifier. Its intrinsic content sits at the top of
the flexible rounded `DescribeTextArea`; the container's explicit rounded
interaction shape forwards taps into `isTextFieldFocused`, so the empty space
below the field remains a typing target instead of becoming a dead zone.

`DescribeInputView` is deliberately render-only. Its full-page vertical content
uses `DescribeVerticalScrollView`, a UIKit `UIScrollView` containing a
`UIHostingController`. That boundary preserves vertical scrolling and drag to
dismiss keyboard behavior without putting a nested SwiftUI vertical scroll graph
inside the workspace's horizontal SwiftUI pager. Replacing it requires strict
AttributeGraph cold-launch testing for all three configurable first modes.

The former aggregate view is split without changing layout ownership:

- `DescribeQuestionNavigationView` owns dots and previous/next controls.
- `DescribePromptTagsView` owns prompt/tag rendering and the UI-only 350 ms
  auto-advance task.
- `DescribeTextEditorView` owns the flexible rounded text region and receives a
  focus binding from the page.
- `DescribeVerticalScrollView` owns the existing UIKit hosting controller and
  exact constraint topology.

### Tag Rendering

The tag strip iterates `promptViewModel.activeQuestions` (not the static
`guidedQuestions`). Each tag is rendered conditionally:

- **Non-nil `imageName`** → 96×112 pt tile
  (`RoundedRectangle(cornerRadius: 16)`): `Image(imageName)` (64×64 pt
  `.scaledToFit`) above the label. Background is `.primary` / foreground
  `.systemBackground` when selected as the active funnel subject; otherwise
  `.secondarySystemBackground` / `.primary`.
- **Nil `imageName`** → standard `Capsule` chip. Same selection-state colour
  logic applies.

`DescribeTagRanking` orders tags by persisted frequency, then default weight,
then original source order. `DescribePresentationDependencies` performs the
preference read and records each tap; the component receives only closures.
`DescribeTextComposer` owns exact append, removal, capitalization, punctuation,
and dictation-baseline composition instead of embedding string mutation in the
view.

### Funnel Lifecycle

**Subject tap → funnel activation**: On the subject question (index 0), tapping
a tag checks `promptViewModel.activeSubjectId == tag.tagId`. If the tag is
already the active subject (toggle-off), `DescribeTextComposer` removes its
prior fragment and `promptViewModel.clearSubjectSelection()` restores the
general questions. Otherwise, the composer appends the fragment and
`promptViewModel.applySubjectSelection(for:)` activates the matching funnel,
advancing to its first question. Auto-advance is suppressed when the subject was
already selected to prevent double-stepping.

**Text-driven auto-activation (1.5s debounce)** is owned by the zero-sized
`DescribeInputLifecycleObserver` mounted in `CaptureWorkspaceView`, outside the
pager:

1. If `freeText` is empty → `promptViewModel.resetFunnel()` and early return.
2. If `isFunnelActive` → no-op (funnel already running).
3. Otherwise, `DescribeInputViewModel` starts its injected 1.5-second delay,
   then calls `SubjectKeywordMatcher.infer(from:)`. If a subject is inferred and
   no manual funnel has become active, the observer asks the prompt view model
   to activate it. This supports text such as "I saw a hawk" before any tag tap.

Every text or prompt-flow change cancels and invalidates the previous inference
generation. Even if the older delay ignores cancellation and later returns, it
cannot publish into the replacement text or reanalysis flow. Leaving Describe
stops only dictation and preserves the established off-page prompt-inference
behavior; removing the workspace cancels both. `CaptureWorkspaceView` owns the
prompt view model and sheet presentation so these transitions do not enter the
pager's layout graph.

---

## 4. `SpeechManager`

Lives at `apps/ios/Merian/Core/Hardware/SpeechManager.swift`. Registered as
`var speechManager = SpeechManager()` in `AppDIContainer` and distributed via
`.environment(container.speechManager)` in `DIContainerModifier.body()`. The
manager is Core-owned because Capture Describe, Insight Field Notes, Insight
media coordination, and the shared capture bar consume it.
`CaptureWorkspaceView` reads the environment-owned instance and explicitly
passes it to `DescribeInputLifecycleObserver`; that observer constructs
`DescribeInputViewModel.Dependencies.live` rather than letting the paged
Describe view resolve hardware. `FieldNotesSheet` follows the same boundary: its
thin wrapper reads the shared environment instance and constructs
`FieldNotesEditorDependencies.live`, while Field Notes Views, Components, and
the editor view model resolve no hardware singleton.

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
AVAudioApplication.requestRecordPermission() (async continuation)
    ↓ Task.isCancelled check
SFSpeechRecognizer.requestAuthorization (async continuation)
    ↓ Task.isCancelled check
availableSpeechRecognizer() (bounded availability retry)
    ↓
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

Whenever an audio engine exists, both `stop()` and `removeTap(onBus:)` run
during teardown. This prevents an `NSException` crash when `audioEngine.start()`
throws after `installTap` was already called — a subsequent `startDictation`
call would otherwise attempt to install a second tap on a node that still holds
the first.

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
  captures the existing text as a baseline and forwards the intent to
  `DescribeInputViewModel`. The view model starts the injected speech action,
  generation-fences cumulative transcription, composes it against that baseline,
  and mirrors startup failure or automatic termination back to the coordinator.
- Leaving Describe, removing the workspace, or toggling dictation off calls the
  dictation stop path. It invalidates the generation before stopping the speech
  engine, cancels startup, clears task state, and resets the coordinator flag,
  including the mid-permission-dialog case. An engine still being configured is
  not torn down concurrently: its canceled startup owns cleanup, and a
  cancellation-ignoring successful return is stopped before the serialized
  replacement enters `SpeechManager`. The manager's `isStarting` guard therefore
  cannot silently discard the replacement. The live adapter also reports whether
  startup actually reached recording; a busy shared manager or an inactive
  return clears the request instead of leaving the control active. Removing the
  workspace additionally invalidates delayed subject inference.
- `CaptureWorkspaceView` owns `isDescribeQuestionsSheetPresented` and applies
  `DescribeQuestionsSheet` at workspace scope. Reanalysis suppresses that sheet.

This split is part of the startup stability contract: the Describe page renders
prompt state but does not attach reactive tasks or sheet hosts to the nested
page hierarchy.

### Field Notes editor wiring

`FieldNotesEditorViewModel` owns the Insight editor's draft, save state, inline
errors, and dictation generation. It composes cumulative transcription against
the stable note text captured when the session starts. Stop, automatic speech
termination, clear, save, and dismissal all invalidate that generation before an
older result can mutate the draft.

If the user stops while permission or audio setup is pending and immediately
starts again, the replacement awaits the canceled startup's teardown before it
calls the injected start action. A cancellation-ignoring predecessor that
reaches recording is stopped before it releases the serialized slot. The live
adapter reports whether recording actually started, so a busy shared manager or
inactive return clears the Field Notes session rather than leaving its control
active. Stop calls shared teardown only when the editor owns the active session;
it cannot terminate unrelated speech work.

`FieldNotesEditorView` retains focus, keyboard dismissal, confirmation
animation, actual sheet dismissal, and interactive-disappearance task timing.
This keeps extraction from changing SwiftUI cancellation or focus behavior.

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
view model clears the dictation request through the observer so the control
returns to its idle state.

---

## 7. AVAudioSession Lifecycle

| Event                                              | Action                                                                                            |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `startDictation` called                            | Acquires a `.recordMeasurement` lease from `AudioSessionCoordinator`                              |
| `stopDictation()` called                           | Tears down recognition and asks the coordinator to deactivate only if this lease is still current |
| Describe request canceled during pending startup   | Cancels and retains startup; does not call shared teardown concurrently                           |
| Replacement requested after canceled startup       | Awaits prior completion; stops a stale successful session before starting                         |
| Task cancelled mid-setup (after session activated) | `handleCancelledStartup()` tears down and releases the owned lease                                |
| `SFSpeechRecognitionTask` auto-terminates          | `stopDictation()` → `teardownAudioEngine()` → token-aware deactivation                            |

The lease prevents delayed teardown from one mode from deactivating a newer
audio owner. This lets `AudioCaptureManager` acquire its own recording lease
cleanly after the user leaves Describe, even when stop/start work overlaps. The
coordinator publishes no lease for a failed first activation, restores the prior
configuration after a failed replacement, and deactivates the partial session if
that restoration also fails.

---

## 8. Swift 6 Concurrency

`SpeechManager` is `@MainActor`. All stored properties (`isRecording`,
`audioEngine`, `recognitionRequest`, `recognitionTask`) are
`@MainActor`-isolated. The `onResult` callback is typed
`@MainActor @escaping (String) -> Void`. The live dependency wraps it in a
`DescribeInputViewModel.DictationResultSink`, so session validation and text
composition execute on `@MainActor` before the observer mutates workspace state.
No `@Sendable` closure carries SwiftUI bindings across actors.

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

## 2026-08 Ownership and Session Hardening

- Describe now has explicit Models, Services, ViewModels, Views, and Components
  owners. The former `Managers` directory, aggregate input view, and
  `DescribeTagTracker.shared` were removed.
- Shared `SpeechManager` moved to `Core/Hardware` with its lifecycle tests under
  `MerianTests/Core/Hardware`; its API, environment injection, permission order,
  audio-session lease, and media behavior did not change.
- `DescribePromptViewModel` replaces the Manager label for feature presentation
  state. `DescribeInputViewModel` owns private inference and dictation tasks
  plus generation tokens.
- Text and prompt-flow replacement fence delayed inference even when injected
  work ignores cooperative cancellation. Stop/restart overlap fences old
  transcription callbacks, avoids shared teardown while startup is configuring,
  and serializes replacement startup behind canceled startup cleanup. A stale
  cancellation-ignoring success is stopped before a replacement enters the
  manager. Verified-start status also fails closed when another speech consumer
  is busy.
- `DescribeTextComposer` and `DescribeTagRanking` make exact text mutation and
  ordering deterministic. Live preferences, haptics, keyboard dismissal,
  subject-inference delay, and the speech-manager adapter are confined to
  Describe Services.
- `CaptureDescribeArchitectureTests` enforces the ownership tree, presentation
  dependency boundary, platform-neutral Models, concrete-hardware-free
  ViewModels, Core speech location, and a 600-line production-file ceiling.
  Focused view-model and composition suites cover cancellation, stale
  completion, overlap, and exact output behavior.
- Insight Field Notes now applies the same serialized stop/restart and stale-
  result fencing through `FieldNotesEditorViewModel` and a Services-only speech
  adapter. Its focused suite covers pending-start cancellation, replacement
  ordering, ownership-safe stop, automatic-termination late-result rejection,
  stable-baseline composition, and retryable startup failure without changing
  `SpeechManager`'s public contract.
