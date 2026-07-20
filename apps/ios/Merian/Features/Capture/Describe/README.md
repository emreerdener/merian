# Capture Describe

The `Describe` directory contains the logic and UI for text-based ecological observation.

## Purpose
This area allows users to describe an organism using text when a photo or audio recording isn't viable (e.g., the bird flew away). It supports both manual typed input and live voice dictation through `SpeechManager`. These text descriptions can be submitted for identification or staged alongside visual/audio media.

`DescribeInputView` is intentionally render-only inside the horizontal capture
pager. `DescribeInputLifecycleObserver`, the shared `DescribePromptManager`, and
the questions-sheet presentation state are owned by `CaptureWorkspaceView`
outside that pager. The page's vertical content is hosted in a UIKit
`UIScrollView`; do not replace it with a nested SwiftUI vertical `ScrollView`
without rerunning strict AttributeGraph traces for Camera-, Audio-, and
Description-first cold launches.

That scroll view disables UIKit's automatic content-inset adjustment, and its
hosted page reserves a fixed 60 pt top band for the overlaid mode selector. The
hosted page already begins in safe-area coordinates: do not add the window's
top safe-area inset to this spacer or the Description screen gains a second,
roughly 59 pt empty band. `CaptureModeToggle` and
`DescribeQuestionNavigation` are stable UI-test identifiers; rendered spacing
between them must remain within 8...32 pt.

The scroll content reserves
`CaptureControlBarLayout.describeContentBottomClearance` (204 pt) below the
rounded editor, matching the fixed capture row's actual reserved height. The
editor is the flexible child and absorbs the remaining viewport height inside
its rounded background; its 24 pt bottom padding supplies the intended visual
gap instead of exposing blank page space. Keep the editor's `DescribeTextArea`
accessibility identifier and the UI assertion requiring 8...32 pt between its
rendered bottom and the control row.

The lifecycle observer stops dictation when the user leaves Describe or the
workspace disappears, including while permissions or audio-session startup are
still pending. Permission failures and temporary recognizer unavailability both
clear the coordinator request so the capture control returns to idle.
