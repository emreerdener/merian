# Direct audio staging — September 27, 2026

## Scope and source state

Finished recordings now join the capture draft directly after the checkmark or
15-second limit. The staged node owns playback, scrubbing, boost, and removal.
Recorder review remains only for a current recording that cannot join the draft;
its retry is manual. The draft remains the only Auto-submit eligibility owner.

The implementation is uncommitted working-tree work based on
`681d291e0cdd10b0d22201783436e1d39cccacbd`, alongside unrelated concurrent
changes. That SHA identifies the base, not the implementation. No implementation
commit or distributed build is claimed by this record.

The handoff checks recording identity and draft generation, transfers the
original WAV into draft ownership before resetting the recorder, and resolves
the operation after insertion. Failed or stale completion cannot restore
cancelled content. Recording-start boost preference is ephemeral preview
metadata; original audio, network payloads, queue data, and schemas are
unchanged.

Current behavior and ownership are documented in the
[audio contract](../features-and-hardware/12-audio-listen-mode.md) and
[staged-review contract](../features-and-hardware/29-staged-capture-review.md).

## Local validation

All native builds and tests use `make ios-local-build` and its shared cache.
Simulator validation uses iPhone 17 Pro on iOS 27.0.

- Focused recorder, recovery playback/boost, capture handoff, and UI checks:
  **86 passed, zero failed or skipped**. Result bundle:
  `.artifacts/local-ios/3bbf2eff4a7d46c79bd6373ec0daf49d.xcresult`.
- The final complete `merianTests` run passed **1,415 XCTest cases and 3,075
  Swift Testing cases**. The direct-finish UI selector also passed again in that
  run, exercising both recording and paused completion. Result bundle:
  `.artifacts/local-ios/3bc8bfdf2686439aa61d70a5f2aec86d.xcresult`.
- The new UI selector
  `merianUITests/merianUITests/testFinishedRecordingJoinsTrayWithoutIntermediateReview`
  exercises both recording and paused completion, direct tray insertion, preview
  boost selection, removal, and restored recording capacity. The existing staged
  audio playback UI selector also passed.
- Project validation, affected-source SwiftLint, iOS CI tooling contract tests,
  Markdown formatting, and whitespace checks passed.

Screenshots exported from the focused result bundle are retained locally under
`.artifacts/local-ios/direct-audio-staging/` with an attachment manifest:

- `859C8712-201F-42A9-A913-0444AC4BBFF2.png`: completion from recording.
- `313BA9F1-4383-41FD-8A22-B4D740E7B95E.png`: completion from paused recording.
- `B91B12EC-EE67-4EEF-96C5-26213E639B66.png`: compact audio tray before opening
  playback review.

Both direct-completion screenshots were visually inspected: Record shows idle
artwork, the audio node is staged, submission is available, and the
full-capacity draft has no additional recording control or intermediate
confirmation screen.

## Outstanding validation

Physical-device microphone/session verification has not been performed for this
change. Check real 15-second timing, pause/resume, mode switching, background
and interruption recovery, speaker/headphone routing, scrubbing, boost, removal,
and Auto-submit with and without existing context. Deterministic simulator
fixtures do not establish those hardware outcomes.

This record does not authorize deployment or TestFlight distribution. Release
validation must bind the integrated implementation to its exact commit and
preserve the existing provider, provenance, and migration release gates.
