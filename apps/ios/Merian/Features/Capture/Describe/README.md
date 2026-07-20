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

The lifecycle observer stops dictation when the user leaves Describe or the
workspace disappears, including while permissions or audio-session startup are
still pending. Permission failures and temporary recognizer unavailability both
clear the coordinator request so the capture control returns to idle.
