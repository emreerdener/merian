# Capture Describe

`Capture/Describe` owns typed and dictated ecological observations. It prepares
an `ObservationContext` for Capture staging or submission; it does not own
network dispatch, persistence, or offline recovery.

## Ownership

- `Models/` owns guided-question values, curated funnels, prompt copy and flow,
  taxonomy-to-subject resolution, deterministic tag ranking, and exact text
  composition.
- `Services/` is the only Describe owner that constructs live adapters for tag
  frequency preferences, haptic feedback, the UIKit keyboard action, subject
  inference delay, or `SpeechManager`. Views and components receive narrow
  closures and do not resolve global services; view models remain independent of
  concrete hardware owners.
- `ViewModels/` owns prompt/funnel state and asynchronous Describe lifecycle
  state. `DescribeInputViewModel` generation-fences delayed subject inference
  and dictation callbacks so an older text or speech session cannot mutate a
  replacement session, and serializes a replacement dictation start behind
  canceled startup teardown.
- `Views/` owns the page, workspace-scoped lifecycle observer, prompt sheet,
  focus, and exact presentation timing.
- `Components/` owns the UIKit vertical-scroll host, prompt navigation, tag
  presentation, and flexible text editor.

Shared speech recognition is not feature-owned. `Core/Hardware/SpeechManager`
owns the `AVAudioEngine`, Speech framework, permission, audio-session lease, and
teardown lifecycle consumed by Describe, Field Notes, Insight media, and the
shared capture bar. `AppDIContainer` supplies that one manager to
`CaptureWorkspaceView`, which passes it explicitly to the workspace observer.
The Services-owned `DescribeInputViewModel.Dependencies.live` factory converts
it into narrow closures; the view model never stores or constructs the concrete
hardware owner.

## Layout and presentation invariants

`DescribeInputView` remains render-only inside the horizontal capture pager.
`DescribeInputLifecycleObserver`, `DescribePromptViewModel`, and questions-sheet
presentation remain owned by `CaptureWorkspaceView` outside the pager.

The page's vertical content must stay inside the UIKit `UIScrollView` hosting
boundary. Do not replace it with a nested SwiftUI vertical `ScrollView` without
rerunning strict AttributeGraph traces for Camera-, Audio-, and
Description-first cold launches. UIKit automatic content-inset adjustment stays
disabled. The hosted page begins in safe-area coordinates and reserves only
`CaptureModeSelectorStyle.describeContentClearance`; adding another top safe
area recreates the duplicated empty band.

The flexible rounded editor retains the stable `DescribeTextArea` and
`DescribeTextInput` accessibility identifiers and reserves
`CaptureControlBarLayout.describeContentBottomClearance` beneath it. Its entire
rounded region remains tappable, including the space below the multiline field.
`DescribeQuestionNavigation` and `CaptureModeToggle` remain stable UI-test
identifiers with their documented 8...32 pt rendered spacing.

## Lifecycle and cancellation

- Each text change invalidates the previous 1.5-second subject-inference
  generation. Empty standard text resets the funnel immediately; reanalysis and
  an already active funnel do not schedule inference.
- A prompt-flow change invalidates pending standard inference. Leaving Describe
  stops dictation but preserves off-page prompt inference, matching the existing
  pager behavior. Removing the workspace cancels both.
- Each requested dictation owns a generation across permission negotiation,
  audio startup, partial results, automatic recognition termination, and
  teardown. Stop/restart overlap invalidates the old generation without tearing
  down an engine that is still being configured, then serializes replacement
  startup behind the canceled startup task. If cancellation-ignoring startup
  reports success, the stale session is stopped before the replacement enters
  `SpeechManager`. The live adapter returns a verified-start result; a busy
  shared manager or a start that never reaches recording ends the request
  instead of leaving the control active.
- Presentation-only 350 ms tag auto-advance and text focus remain view-owned so
  animation and keyboard timing are unchanged.

## Verification

`MerianTests/Features/Capture/Describe` mirrors this owner with prompt-state,
text-composition, ranking, delayed-inference, stale-transcription, overlap, and
architecture suites. `MerianTests/Core/Hardware/SpeechManagerTests.swift` owns
shared speech lifecycle coverage. The architecture guard requires
Models/Services/ViewModels/Views/Components, rejects the retired `Managers`
folder and direct live-service resolution in presentation files, keeps Models
platform-neutral, forbids concrete hardware-adapter construction in ViewModels,
and caps every production Describe Swift file at 600 lines.

The canonical behavior contract is
[`11-describe-and-voice-dictation.md`](../../../../../../docs/features-and-hardware/11-describe-and-voice-dictation.md).
