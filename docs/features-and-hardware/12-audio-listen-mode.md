# Audio Listen Mode — Bioacoustic Capture Pipeline

The Audio page is the second page of `CaptureWorkspaceView`'s horizontal pager.
It records a 15-second ambient audio clip, runs a live spectrogram plus
ambient-noise and clipping guidance on-device in real time, and submits the clip
for bioacoustic species identification via the unified `/identify-multimodal`
Supabase Edge Function.

---

## 1. Architecture Overview

The audio pipeline is split across explicit ownership and isolation boundaries:

| Layer                  | Owner                                                                                   | Isolation                           |
| ---------------------- | --------------------------------------------------------------------------------------- | ----------------------------------- |
| DSP / FFT              | `Core/Hardware/SpectrogramActor`                                                        | Swift actor                         |
| Recording and playback | `Core/Hardware/AudioCaptureManager`                                                     | `@MainActor` observable state       |
| Audio-session leases   | `Core/Hardware/AudioSessionCoordinator`                                                 | Swift actor                         |
| Raster policy          | `Core/Media/AudioSpectrogramRenderer`                                                   | Deterministic value operations      |
| Shared rendering       | `Core/UI/Components/AudioSpectrogramView`                                               | `@MainActor` SwiftUI                |
| Record presentation    | `Capture/Record/{Models,Services,ViewModels,Views,Components}`                          | Value Models; `@MainActor` UI/state |
| Controls and submit    | `Capture/Shell`, `Core/UI/Components/CaptureControlBar.swift`, and `Capture/Submission` | `@MainActor` orchestration          |

This matches the camera pipeline's `CameraManager` → `ViewfinderIntelligence` →
`CameraPreviewView` separation and avoids the IPC deadlock pattern that would
occur if `AVAudioSession` were configured on `@MainActor`.

Short visual video scans can also contribute companion audio. That extraction is
owned by `CaptureWorkspaceViewModel.extractVideoAudioTrack(...)`, not
`AudioCaptureManager`: it uses `AVAssetReader` and `AVAssetWriter` to copy the
video track's audio into an Int16 WAV sidecar for the multimodal request. The
reader loop wraps each `copyNextSampleBuffer()` result in a per-sample
`autoreleasepool` and invalidates the `CMSampleBuffer` after append, so native
CoreMedia buffers are released continuously rather than accumulating until the
clip finishes.

---

## 2. `SpectrogramActor` — DSP Worker

**File**: `apps/ios/Merian/Core/Hardware/SpectrogramActor.swift`

A Swift `actor` that runs all FFT and mel-scale arithmetic off the main thread,
keeping `@MainActor` free for 60fps SwiftUI rendering.

### FFT Pipeline

```
AVAudioPCMBuffer → [zero-pad to 2048] → Hann window → Real FFT → power magnitude → dB → clamp → mel-scale → SpectrogramColumn
```

| Parameter       | Value          | Rationale                                                                         |
| --------------- | -------------- | --------------------------------------------------------------------------------- |
| FFT size        | 2048 points    | 42.67 ms window at 48 kHz — enough frequency resolution to resolve bird harmonics |
| mel bins        | 128            | Dense enough for species differentiation without memory pressure                  |
| Frequency range | 80 Hz – 16 kHz | Covers the bioacoustically relevant range for birds, insects, and frogs           |
| dB floor        | −80 dB         | Clamps below-noise-floor energy to zero before normalization                      |

The public web renderer mirrors these constants and `SpectrogramPalette` in the
server-side `audioSpectrogram.ts` processor. Approved standalone WAV shares are
rendered once to a deterministic PNG in R2; web Explore cards, post detail, and
social metadata reuse that image instead of running FFT work in every browser.

**`processColumns(buffer:) -> [SpectrogramColumn]`**\
Wrapped in `autoreleasepool` to prevent Obj-C `AVAudioPCMBuffer` objects from
accumulating across repeated tap callbacks. Emits one spectrogram column per
2048-frame FFT window, so the live 4096-frame tap buffer contributes two visual
columns instead of dropping half of the buffer. The returned `SpectrogramColumn`
values carry:

- `magnitudes: [Float]` — 128 mel-scaled bins, 0.0–1.0 normalized
- `rms: Float` — pre-window RMS (used for ambient-noise classification)
- `peak: Float` — pre-window peak (used for clipping detection)

`process(buffer:) -> SpectrogramColumn?` remains as a compatibility helper that
returns the first processed column.

### Ambient-Noise Classification (Legacy SNR Naming)

**`snrLevel(from:) -> SNRLevel`** maintains a rolling history of the last 48 RMS
values (~2 seconds at 4096-sample tap buffers). The minimum of this window is
used as the estimated noise floor.

Despite the historical `SNRLevel` name, the non-clipping cases classify an
absolute rolling noise floor rather than a computed signal-to-noise ratio in
decibels:

| Level       | Condition                     | Meaning                            |
| ----------- | ----------------------------- | ---------------------------------- |
| `.clipping` | `peak > 0.95`                 | Mic overloaded — move away         |
| `.warning`  | rolling minimum RMS `> 0.08`  | High background noise — shield mic |
| `.caution`  | rolling minimum RMS `> 0.015` | Some ambient noise                 |
| `.clear`    | rolling minimum RMS `≤ 0.015` | Environment is quiet enough        |

**`reset()`** clears the noise floor history. Called by
`AudioCaptureManager.reset()` between sessions to prevent prior noise estimates
from contaminating the next recording.

---

## 3. `AudioCaptureManager` — Recording Pipeline

**File**: `apps/ios/Merian/Core/Hardware/AudioCaptureManager.swift`

`@MainActor @Observable` class. `AppDIContainer` constructs the long-lived
instance with an injected maximum-duration feedback closure and distributes it
through `DIContainerModifier`. The manager does not resolve the haptic singleton
itself.

### Published State

| Property              | Type                  | Description                                                                                                                                                                                                                                                                                                                                                   |
| --------------------- | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `isRecording`         | `Bool`                | Whether a recording session is active (set `true` only after `audioEngine.start()` succeeds)                                                                                                                                                                                                                                                                  |
| `isPaused`            | `Bool`                | Whether the engine is paused mid-recording (tap preserved, countdown halted)                                                                                                                                                                                                                                                                                  |
| `recordingProgress`   | `Double`              | 0.0 → 1.0 over `maxDuration` (15 s)                                                                                                                                                                                                                                                                                                                           |
| `spectrogramColumns`  | `[SpectrogramColumn]` | Rolling display buffer (360 columns ≈ 15 s)                                                                                                                                                                                                                                                                                                                   |
| `snrLevel`            | `SNRLevel`            | Most recent noise level classification                                                                                                                                                                                                                                                                                                                        |
| `pendingPlaybackPath` | `String?`             | Non-nil after recording finishes, before user confirms or discards. Drives the review UI state in `AudioRecordingView`.                                                                                                                                                                                                                                       |
| `isPlaying`           | `Bool`                | Whether `AVAudioPlayer` is currently playing back a pending recording                                                                                                                                                                                                                                                                                         |
| `playbackProgress`    | `Double`              | 0.0 → 1.0 playhead position during review playback; preserved across play/stop cycles for scrub-resume                                                                                                                                                                                                                                                        |
| `audioFilePath`       | `String?`             | Non-nil after the user explicitly confirms in review, or after a maximum-duration recording auto-confirms when confirmation is disabled. Setting this triggers `onChange(of: audioFilePath)`, which either stages the clip into `stagedCapture.audios` (mixed-media / confirmation flows) or calls `submitAudio` directly for the standalone audio-only flow. |

### `startRecording() async throws`

The explicit red-button action first calls
`requestMicrophonePermissionForRecording()`. `startRecording()` then fails
closed unless permission is already granted and uses a detached setup task plus
the token-aware audio-session coordinator to prevent `@MainActor` IPC deadlock
against `mediaserverd`:

```
guard !isRecording, !isStartingRecording   ← re-entry guard (set before any await)
    ↓
discardPending()            ← clears leftover review state
verify permission already granted  ← never opens a prompt
    ↓ cancellation check
teardownEngine()            ← clears any prior engine session
    ↓
transition = transitionState.begin()  ← generation fence for all async commits
Task.detached {
    AudioSessionCoordinator.activate(.recordMeasurement(...))
    accept lease only if transition + engine identity still match
    inputNode.outputFormat(forBus: 0)     ← IPC: never call on @MainActor
    if zero-rate/zero-channel:
        retry 4 × 75 ms with engine.reset()  ← bounded route-settle recovery
    AVAudioFormat(.pcmFormatInt16, ...)   ← canonical Int16 PCM — wav.ts compatible
    AVAudioFile(forWriting: fileURL, settings: int16Fmt.settings)
    inputNode.removeTap(onBus: 0)         ← defensive: prevents nullptr == Tap() crash
    inputNode.installTap(...)             ← file write + DSP dispatch per buffer
    audioEngine.start()
}.value
    ↓ verify task, transition, and engine are still current
isRecording = true
recordingTask = Task { 100 generation-checked ticks × 0.15 s → finishRecording() }
```

**Re-entry guard**: `isStartingRecording` is set to `true` before detached
session/engine setup and cleared in `defer`. This prevents a second
`startRecording()` call from slipping through the `!isRecording` guard during
the asynchronous setup window — the condition that triggered the
`nullptr == Tap()` AVAudioEngine crash.

**Camera-to-audio handoff**: the center-button action owns one cancellable
audio-start task. Before calling `startRecording()`, it awaits
`CameraManager.stopSessionAndWait()`, which returns only after
`AVCaptureSession.stopRunning()` has completed on the camera queue. This keeps a
fast Camera → Audio → Record gesture from asking two capture pipelines to own
the hardware simultaneously. Leaving Audio or removing the control bar cancels
the pending task; cancellation is treated as an expected lifecycle event and
does not show an error toast. The task is not cleared until its `defer` runs, so
a rapid Audio → Camera → Audio sequence cannot overlap two startup tasks.
Cancellation is forwarded into the detached AVFoundation setup task; that task
checks cancellation after session activation and again before engine start, and
the manager also invalidates the operation's generation. A late or
cancellation-ignoring activation releases its newly acquired lease without
starting the engine or publishing DSP/countdown state. Normal failure cleanup
then removes the tap, stops the engine, deletes the partial file, and releases
any accepted audio-session lease.

**Input-route recovery**: even after `AVAudioSession.setActive(true)`, iOS can
briefly expose an input format with a zero sample rate or zero channels while
the new route settles. Startup retries that format read four times at 75 ms
intervals, resetting the engine between reads. The 300 ms bound prevents a
transient handoff from becoming a false “Audio hardware unavailable” error
without hiding a persistent device or route failure.

**WAV file format**: The recording uses an explicit
`AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate:, channels:, interleaved: true)`
to write canonical Int16 PCM WAV (`audioFormat = 1`). Writing with the
hardware's native `fmt.settings` may produce WAVEFORMATEXTENSIBLE
(`audioFormat = 0xFFFE`) — a variant the edge audio parsers do not handle —
causing 400 errors on submission. `AVAudioFile` converts Float32→Int16
automatically on each write.

**Buffer tap (per 4096-frame buffer ≈ 85 ms)**:

1. `file.write(from: buffer)` — synchronous PCM write to `AVAudioFile` on the
   audio thread.
2. `copyPCMBuffer(buffer)` copies the tap-owned PCM data synchronously, then
   yields it into a bounded `AsyncStream(bufferingNewest: 2)` so reused engine
   buffers never cross the async boundary.
3. A detached DSP consumer drains that bounded stream, calls
   `SpectrogramActor.processColumns(buffer:)`, derives the legacy-named
   `SNRLevel` ambient-noise/clipping classification for each emitted 2048-frame
   column, and hops back to `@MainActor` only for the small UI update.

The `[weak manager]` capture in the inner `@MainActor` task breaks the retain
cycle: `AudioCaptureManager → audioEngine → inputNode → tap closure → manager`.

### Teardown

`teardownEngine()` calls `inputNode.removeTap(onBus: 0)` **first**, then
`audioEngine.stop()` — both are no-ops if already stopped/untapped. Removing the
tap before stopping prevents the audio thread from writing into a stopped engine
and avoids AVAudioEngine assertion failures. Lease release is scheduled in a
short inherited task that awaits `AudioSessionCoordinator`; the actor performs
the `AVAudioSession` work outside the main actor and ignores stale or already
consumed leases.

### Recording Lifecycle

| Method                                      | Effect                                                                                                                                                                                                                                                                                                |
| ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `requestMicrophonePermissionForRecording()` | Requests permission only from the explicit red-button action; throws on denial before camera handoff                                                                                                                                                                                                  |
| `startRecording()`                          | Guards with `!isRecording && !isStartingRecording`, fails closed unless permission is already granted, calls `discardPending()`, spins up the engine, and starts the 15-second countdown. The caller selects whether reaching the cap enters review or auto-confirms when confirmation is disabled.   |
| `stopRecordingEarly()`                      | Cancels the countdown and always routes the partial clip to review; only a maximum-duration capture may auto-confirm when confirmation is disabled                                                                                                                                                    |
| `pauseRecording()`                          | Invalidates transition work, cancels countdown, calls `audioEngine.pause()`, sets `isPaused = true`, resets `snrLevel`                                                                                                                                                                                |
| `resumeRecording()`                         | Retains one manager-owned task, coalesces duplicate taps, awaits a new coordinator lease, generation-checks the late result, then starts the engine and rebuilds the countdown from `recordingProgress`                                                                                               |
| `cancelPendingRecordingTransition()`        | Invalidates and cancels pending startup/resume work without concurrently mutating an engine that its startup owner is still configuring                                                                                                                                                               |
| `cancelRecording()`                         | Cancels countdown task, tears down engine, deletes partial file from `tmp/`, calls `discardPending()` to also clear review state                                                                                                                                                                      |
| `finishRecording()` (private)               | Tears down the engine. Early completion or confirmation-enabled capture sets `pendingPlaybackPath`; a maximum-duration capture with confirmation disabled sets `audioFilePath` for the established Shell handoff.                                                                                     |
| `playPendingRecording()`                    | Saves `resumeProgress = playbackProgress` (preserves scrubbed position), creates `AVAudioPlayer`, and uses one stored task to await a `.playback` coordinator lease, seek, play, and clear `isPlaying` after the remaining duration; cancellation and player-reference checks guard stop→replay races |
| `stopPlayback()`                            | Stops `AVAudioPlayer`, clears `isPlaying` and `playbackProgress`                                                                                                                                                                                                                                      |
| `seekPlayback(to:)`                         | Sets `audioPlayer.currentTime = duration * clamped` and updates `playbackProgress` — works while playing or stopped                                                                                                                                                                                   |
| `confirmAndSubmit()`                        | Stops playback, sets `audioFilePath = pendingPlaybackPath`, clears `pendingPlaybackPath` — triggers `onChange` in `CaptureWorkspaceView`                                                                                                                                                              |
| `discardPending()`                          | Stops playback, deletes file from `tmp/` if `pendingPlaybackPath` is set, clears `pendingPlaybackPath`, **always** clears `spectrogramColumns`, `snrLevel`, `snrHoldTicks`                                                                                                                            |
| `reset()`                                   | Calls `stopPlayback()`, cancels tasks, tears down the engine/tap/session lease, deletes any unsubmitted pending temp file, clears all published state including `pendingPlaybackPath`, calls `spectrogram.reset()`                                                                                    |

**`discardPending()` clears display state unconditionally**: The spectrogram
column and noise-guidance reset run outside the `if let pendingPlaybackPath`
branch so that calling `discardPending()` during an active recording (e.g.
immediately before `startRecording()`) also wipes the previous session's visual
state. The prior `guard let name = pendingPlaybackPath else { return }`
early-exit pattern leaked these columns into the next recording's UI.

**Submission state machine:**

```
startRecording() → [recording] ─────────────────────────────────────── pauseRecording()
                       │                                                     ↓
                       │                                        [paused] ── resumeRecording()
                       │                                                     ↓
                       ├─ stopRecordingEarly() ─────────────────────────→ [review]
                       │                                                        ↓ confirmAndSubmit()
                       └─ 15-second maximum                                     │
                            ├─ confirmation enabled ───────────────────────→ [review]
                            └─ confirmation disabled ─────────────────────→ [submitted]
                                                                                 ↓
                                               CaptureWorkspaceOrchestrationModifier.onChange
                                                                                 ↓
                                                    [stage into toolbar OR submitAudio] → reset()

                  [review] → discardPending() → [idle]
```

`CaptureWorkspaceOrchestrationModifier.onChange(of:
audioCaptureManager.audioFilePath)`
fires after the user explicitly confirms a reviewed clip, or after a recording
reaches the 15-second maximum while confirmation is disabled. Early completion
and every confirmation-enabled recording enter review first. If the user already
has staged images, videos, or descriptions, if multi-capture mode is enabled, or
if explicit confirmation is required, the confirmed clip is appended to
`stagedCapture.audios` and shares the same 2-item total mixed-media cap as
images, videos, and descriptions. Otherwise the audio-only path calls
`submitAudio(...)` immediately.

When recording begins, `CaptureWorkspaceOrchestrationModifier` asks the
workspace view model to `prepareNonVisualCaptureContext()`. This starts the same
pinned environment lookup used by camera captures while the user is still
recording, hiding the reverse-geocoding and WeatherKit latency behind the
recording/review flow. Each new recording replaces an abandoned lookup.
Submission snapshots that task and uses `lastKnownLocation` for immediate queue
telemetry. Only after the WAV and queue row are durable does the prefetched or
fallback lookup receive a 150 ms live-request grace. A late result merges
locally and through `/update-scan-context`; a queue-only, queue-rejected,
superseded, or unavailable-owner branch cancels an unconsumed lookup. This
prevents audio scans with valid GPS from losing `locationName` without making
WeatherKit or reverse geocoding a durability dependency.

### File Format

Audio is written to `FileManager.default.temporaryDirectory/<uuid>.wav` as
**Int16 PCM WAV** (`audioFormat = 1`, interleaved) using an explicit
`AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: fmt.sampleRate, channels: fmt.channelCount, interleaved: true)`.
The hardware's native Float32 format may produce WAVEFORMATEXTENSIBLE
(`audioFormat = 0xFFFE`), which the edge audio parsers do not support and
returns 400. `AVAudioFile` performs the Float32→Int16 conversion automatically
per write. The shared non-visual queue path (`enqueueNonVisualCapture`) moves
the file from `tmp/` to `URL.documentsDirectory` for persistence.

**Historical reanalysis boundary**: A persisted audio reference is playback
metadata, not an inference file path. `InferenceAudioPreparer` resolves local
references or downloads credential-free HTTPS references with an ephemeral,
cookie-free, no-cache session and the same 2.7 MB input/output budget. Remote
bytes are written through a bounded stream; declared and actual length are
checked and an unknown-length response is cancelled as soon as it crosses the
ceiling. Any AVFoundation/Core Audio-readable historical recording, including
durable M4A, is decoded through a bounded streaming converter into a new
Documents-owned mono 44.1 kHz Int16 PCM WAV. The original local or remote
playback reference is retained unchanged. Cancellation and failed validation
remove only the uncommitted sidecar. Refinement stages the sidecar's local
filename; it never places an `https://` string into `StagedAudio`. Candidate
order is usable image, standalone audio, legacy extracted video-companion audio,
then saved description; repeated audio references are deduplicated without
discarding the companion compatibility fallback.

---

## 4. Submission Flow — `CaptureWorkspaceViewModel+NonVisualSubmission.swift`

**File**:
`apps/ios/Merian/Features/Capture/Submission/ViewModels/CaptureWorkspaceViewModel+NonVisualSubmission.swift`

`extension CaptureWorkspaceViewModel { func submitAudio(audioFileName:modelContext:) }`
now routes through the shared non-visual submission path rather than a dedicated
audio-only analyzer.

```
debounce check (1.5 s, CFAbsoluteTimeGetCurrent)
    ↓
submitNonVisualCapture(
    audioFileNames: [audioFileName],
    observationContexts: [],
    mediaTimeline: [.audio(audioFileName)],
    modelContext: modelContext
)
    ↓ caller-scoped admission preview selects foreground or queue-only
    ↓ reset zoom + snapshot recording-time preFetchTask
    ↓ enqueue WAV and cached telemetry durably
    ↓ if foreground-owned, race prefetched/fallback context against 150 ms
    ↓ analyze with available telemetry
    ↓ if context finishes late, merge locally and through /update-scan-context
```

**Live + offline dual-path**: audio-bearing captures always enqueue durably
first (moving the WAV into `Documents/` and creating a `.pending` queue record
for R2 staging). An offline or typed queue-only route shows a toast and stops
without calling `InferenceEngine.prepareForNewScan()`. A still-online foreground
route also persists a foreground inference UUID, then prepares the live engine,
opens the insight sheet, and passes that UUID to
`InferenceEngine.analyzeNonVisual(...)`. On live success, `deleteQueuedScan`
preserves audio adopted by the final local scan and requires a matching
`ForegroundInferenceGenerationExpectation`, preventing stale cleanup or a
redundant background Gemini call on the same file. If no live request can own
the scan, the captured context task is cancelled. A timeout-losing task retains
only the deferred-context service and bounded telemetry values for its late
merge, not the workspace view model.

---

## 5. `OfflineQueueManager.enqueueNonVisualCapture` — Queue Record

**Files**:
`apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager+Queue.swift`,
`OfflineQueueManager+URLSession.swift`

Audio now uses the same ordered queue shape as every other mixed-media
submission. The queue record stores the serialized media timeline in
`capturedMediaJSON`, and V41 also materializes that timeline into the
`capturedMediaEntries` relationship mirror.

```
move tmp/<uuid>.wav → Documents/<uuid>.wav
    ↓ advisory local meter (UsageManager.canPerformScan / consumeScan)
OfflineQueuedScan(
    scanState: .pending,        ← audio uploads through R2 before replay
    capturedMediaJSON: ...,
    capturedMediaEntries: ...
)
modelContext.insert(scan)
modelContext.save()
updateUnsyncedItemCount()
AppTelemetry.trackOfflineQueued()
syncPendingScans()
    ↓ authoritative reserve_ai_quota(scan_audio_identification, scan UUID)
    ↓ commit immediately before Gemini audio dispatch
```

Audio-bearing inference records upload PCM WAV via background
`URLSession.uploadTask(with:fromFile:)` and persist the resulting staging key in
`stagedR2Keys`. `dispatchInferenceDownloadTask` splits those keys into image
`r2ObjectKeys` and audio `audioR2ObjectKeys`, so queued replay never builds a
large inline audio request body. New queue admission rejects non-WAV and
URL-scheme audio paths. M4A remains an accepted durable playback/legacy Explore
restore format only; it is never signed as ordinary inference input.

Installed queues can still contain local M4A references written by an older
build. Before pending upload or staged replay, the queue serializes an upgrade
claim, clears any stale staged keys, and persists a negative
`queueSchemaRepairGeneration` latch while Core Audio creates Documents-owned WAV
replacements outside the database transaction. One atomic commit rewrites both
`capturedMediaJSON` and relationship entries, preserves timeline order and
source indices, advances the repair generation, and returns the row to
`.pending` for fresh signing. A crash leaves the original M4A and persisted
latch, so the next pass safely repeats the conversion; a deterministic decode
failure becomes `queued_audio_upgrade_failed` needs-attention work rather than a
signing/inference retry loop. The original compressed source is retained because
another historical playback row may still reference it.

**Cleanup on delete**: Audio files stored in `Documents/` are cleaned up through
the same canonical media snapshot walk used for images. Delete and purge paths
no longer special-case image arrays and therefore do not lose audio cleanup.

---

## 6. Inference Path

There is no longer a dedicated `InferenceEngine+Audio.swift` path. Audio uses
the same non-visual entry point as description-only captures:

1. `CaptureWorkspaceViewModel.submitAudio(...)` delegates to
   `submitNonVisualCapture(...)`.
2. `InferenceEngine.analyzeNonVisual(...)` forwards `audioFilePaths`, any
   `observationContexts`, and the ordered `mediaTimeline`.
3. `MerianNetworkClient.buildMultiModalRequest(...)` sends live foreground WAVs
   as size-preflighted `audioBase64s`; queued replay sends R2-backed
   `audioR2ObjectKeys`.
4. `InferenceProcessingActor.parseAndSave(...)` routes the result through
   `BackgroundDatabaseActor.saveNonVisualRecord(...)`.

Replay uses the same endpoint and payload shape through the offline queue’s
shared non-visual branch.

---

## 7. UI Layer

### `AudioRecordingView`

**File**:
`apps/ios/Merian/Features/Capture/Record/Views/AudioRecordingView.swift`

Full-screen content view for the `.audio` pager page. All persistent controls
(capture button, `MediaModeToggle`, tab bar, flanking action buttons) live in
`CaptureWorkspaceView`'s fixed overlay layers.

| State     | Condition                                    | Content                                                                                                              |
| --------- | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Idle      | `!isRecording && pendingPlaybackPath == nil` | Rotating animal illustration carousel · persistent **Record nearby sounds** material badge above the capture control |
| Recording | `isRecording`                                | Shared live `AudioSpectrogramView` · `AudioSNRGuidanceView` below the spectrogram                                    |
| Review    | `pendingPlaybackPath != nil`                 | Shared static, seekable `AudioSpectrogramView` · no lower guidance badge                                             |

**Spectrogram sizing**: The spectrogram height is computed symmetrically from
`composingCenter` (the vertical center of the composing area between
`MediaModeToggle` and the control bar):

```swift
let centerY = proxy.size.height * composingCenter
let bottomClearance = CaptureControlBarLayout.fullScreenOverlayClearance
let halfHeight = min(centerY - 100, proxy.size.height - bottomClearance - centerY - 88)
let spectrogramHeight = max(180, halfHeight * 2)
```

The fixed `CaptureControlBarLayout.reservedHeight` is 80 pt for the primary
control plus a 124 pt bottom inset, totaling 204 pt relative to the safe area.
Because Audio is a full-screen page, its overlays use the separate fixed 250 pt
`fullScreenOverlayClearance` that preserves the position used before bar
measurement was removed. Audio does not read the full-bleed pager's zero bottom
safe-area inset, measure the rendered child bar, or write height into workspace
state.

This ensures the spectrogram clears the `MediaModeToggle` toolbar above and the
tooltip hint zone above the FAB below. The view uses
`.frame(width: proxy.size.width)` before `.position()` to correctly offer full
width to the spectrogram image (`.position()` detaches from layout flow and
would otherwise receive zero width from `maxWidth: .infinity`).

**Review state — playhead**: A vertical scrub line overlays the spectrogram
during review. It is visible only when
`isPlaying || isScrubbing || playbackProgress > 0`. This means it appears only
once the user has started playback or manually scrubbed — not by default when
the recording first enters review. If the user scrubs the playhead away from the
start position and stops, the playhead remains visible at the parked position.
On full-clip playback completion, `playbackProgress` resets to 0 and the
playhead disappears. A `DragGesture` on the spectrogram image drives
`seekPlayback(to:)`, enabling scrub-to-any-position with live playhead tracking.

**Insight carousel playback**: Persisted audio pages use
`Media/Carousel/Pages/AudioPlaybackCarouselPage`. The page does not mount a 60
Hz Combine timer. Its generation-keyed playback monitor publishes durable
progress every 100 ms only while the concrete `AVAudioPlayer` remains active and
stops when playback stops, completes, is replaced, or the page disappears. The
render-only `AudioPlaybackCarouselContent` receives a live progress provider;
its `TimelineView` reads current player time for the thin playmarker on each
display tick without owning the player or mutating the raster-backed
spectrogram. This keeps idle Insight carousels from burning battery and prevents
the extracted component from freezing the playmarker at a parent snapshot.

**Staged multi-scan playback**: `ActiveScanToolbar` routes a waveform-badge tap
to a selected staged-audio index. `CaptureWorkspaceView` presents that clip in
`StagedAudioPreviewModal`, which reuses `AudioPlaybackCarouselPage` for bounded
local-source resolution, spectrogram decoding, playback, and seeking. Closing
the full-screen cover leaves the clip staged. **Remove** calls
`removeStagedAudio(at:)`, updates the ordered mixed-media timeline, and deletes
the temporary recording through `FileIOActor`. The cover is included in the
workspace presentation-occupancy fence, so camera or route restoration cannot
race its dismissal.

The `RecordingCountdownBadge` above the spectrogram is owned by
`Capture/Shared/Components` because Scan video uses the same finite-duration
treatment. Record supplies recording or playback progress, the 15-second
duration, and state-specific accessibility copy.

### `AudioSpectrogramView`

**Files**:

- `apps/ios/Merian/Core/UI/Components/AudioSpectrogramView.swift`
- `apps/ios/Merian/Core/Media/AudioSpectrogramRenderer.swift`

The domain-neutral renderer builds a compact RGBA bitmap from
`SpectrogramColumn` values, then the shared SwiftUI view scales that image with
high-quality interpolation so the display reads as a continuous spectrogram
instead of a grid of large rectangles. Frequency still increases bottom-to-top
(bin 0 = 80 Hz at bottom, bin 127 = 16 kHz at top). Record owns the review drag
gesture and playhead overlay, not the shared view.

**Display layouts**:

| Layout                    | Use                                       | Behavior                                                                                               |
| ------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `.liveHorizon(capacity:)` | Active recording                          | Renders against the full 360-column live horizon so early audio does not stretch into oversized blocks |
| `.fitToData`              | Review, Insight playback, scan thumbnails | Fits the captured columns edge-to-edge for static playback and saved previews                          |

**Colormap**: A smoothed perceptual palette maps near-black background values
through deep blue, cyan, green, warm yellow, and pale highlights. The same
palette is used for live capture, review, Insight audio playback, and scan
thumbnails.

### `AudioSNRGuidanceView`

**File**:
`apps/ios/Merian/Features/Capture/Record/Components/AudioSNRGuidanceView.swift`

Passive material capsule for recording guidance. It shows **Record 15 seconds**
once per process session for 3.5 seconds, then exposes the current non-clear
ambient-noise label when audio hints are enabled. The stored prompt task is
cancelled on unmount, the surface disables hit testing, and no delayed dispatch
chain or keyframe shake survives view teardown.

`AudioRecordingView` mounts `AudioSNRGuidanceView` only after recording starts,
so the initial guidance timer cannot expire invisibly while the page is idle.
Before recording, the same lower guidance slot instead shows the persistent,
non-interactive **Record nearby sounds** badge regardless of the Audio Hints
preference. Review hides the lower guidance slot.

All visible guidance uses the existing white text on a dark material capsule;
the level changes copy rather than color. `.clear` has stable **Clear** mapping
for deterministic presentation tests but is hidden after the initial prompt.

| `SNRLevel`  | Visible label after the initial prompt |
| ----------- | -------------------------------------- |
| `.clear`    | Hidden                                 |
| `.caution`  | **Some noise**                         |
| `.warning`  | **Shield mic**                         |
| `.clipping` | **Move mic away**                      |

---

## 8. `CaptureControlBar` — Audio Button Wiring

### Center capture button (`CaptureButton`)

The `.audio` case of `CaptureButton.onAction` in `CaptureControlBar` implements
a multi-state dispatch:

```swift
case .audio:
    if audioCaptureManager.pendingPlaybackPath != nil {
        audioCaptureManager.confirmAndSubmit()         // review → submit
    } else if audioCaptureManager.isRecording {
        if audioCaptureManager.isPaused {
            audioCaptureManager.resumeRecording()      // paused → recording
        } else {
            audioCaptureManager.pauseRecording()       // recording → paused
        }
                            } else {
                                guard audioRecordingStartTask == nil else { return }
                                audioRecordingStartTask = Task {
                                    defer { audioRecordingStartTask = nil }
                                    do {
                                        guard await viewModel.requestScanAdmission(...) != nil else {
                                            return
                                        }
                                        guard scenePhase == .active else { return }
                                        try await audioCaptureManager
                                            .requestMicrophonePermissionForRecording()
                                        try Task.checkCancellation()
                                        await cameraManager.stopSessionAndWait()
                                        try Task.checkCancellation()
                                        guard scenePhase == .active else { return }
                                        try await audioCaptureManager.startRecording(
                                            autoSubmitOnMaxDuration:
                                                !appSettings.requiresScanConfirmation
                                        )
                                    }
            catch is CancellationError { /* expected mode transition */ }
            catch { viewModel.offlineToastMessage = error.localizedDescription }
        }
    }
```

Errors (permission denied, hardware unavailable) surface via
`offlineToastMessage`.

### Center button visual state machine

The `CaptureButton` inner fill and icon encode the **available action**, not the
current state:

| Condition          | Fill                 | Icon         | Meaning         |
| ------------------ | -------------------- | ------------ | --------------- |
| Idle               | Red                  | None         | "Tap to record" |
| Paused             | Red                  | None         | "Tap to resume" |
| Recording (active) | Neutral (`.primary`) | `pause.fill` | "Tap to pause"  |
| Review             | Neutral (`.primary`) | `↑` or `+`   | "Tap to submit" |

Red always means "tap here to start or resume recording." Neutral with a pause
icon means "tap here to pause." The progress arc (red, sweeping clockwise) is
hidden during review so the ring resets to a clean submit-button appearance.

### Flanking buttons (left / right slots)

| State                        | Left button                                    | Right button                                        |
| ---------------------------- | ---------------------------------------------- | --------------------------------------------------- |
| Idle                         | —                                              | —                                                   |
| Recording (active or paused) | `AudioDeleteButton` (trash — cancel + discard) | `AudioDoneButton` (checkmark — stop early → review) |
| Review                       | `AudioDeleteButton` (trash — discard pending)  | `AudioReviewPlayButton` (play/stop toggle)          |

`AudioDeleteButton` calls `cancelRecording()` while recording and
`discardPending()` during review. `AudioDoneButton` calls
`stopRecordingEarly()`. `AudioReviewPlayButton` toggles `playPendingRecording()`
/ `stopPlayback()`, showing `play.fill` or `stop.fill` with a
`.symbolEffect(.replace)` transition.

All flanking buttons animate in/out with `.easeInOut(duration: 0.2)` keyed on
`captureMode`, `isRecording`, and `pendingPlaybackPath`.

---

## 9. Session Lifecycle

| Trigger                                                   | Action                                                                                                                                       |
| --------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| User taps Record immediately after entering `.audio`      | Await `cameraManager.stopSessionAndWait()`, then start audio; retry a transient zero input format for at most 300 ms                         |
| User leaves `.audio` while recording startup is pending   | Cancel the outer task and manager transition; reject late activation and do not show a cancellation toast                                    |
| Swipe from `.audio` to another mode                       | Invalidate pending startup/resume; pause an active unpaused recording so its clip and progress remain recoverable                            |
| App becomes inactive or backgrounds while `.audio` active | Apply the same transition invalidation and non-destructive pause contract                                                                    |
| 15 s countdown completes                                  | Heavy feedback, then review when confirmation is enabled or the established `audioFilePath` Shell handoff when confirmation is disabled      |
| User taps `AudioDoneButton` (checkmark) while recording   | `stopRecordingEarly()` → always enters review, including when a maximum-duration clip would auto-submit                                      |
| User taps center button while recording                   | `pauseRecording()` → engine paused, countdown halted                                                                                         |
| User taps center button while paused                      | `resumeRecording()` → engine and countdown resumed from current progress                                                                     |
| User taps `AudioDeleteButton` while recording/paused      | `cancelRecording()` → returns to idle                                                                                                        |
| User taps center button in review                         | `confirmAndSubmit()` → sets `audioFilePath` → `CaptureWorkspaceOrchestrationModifier.onChange` either stages the clip or calls `submitAudio` |
| User taps `AudioDeleteButton` in review                   | `discardPending()` → returns to idle                                                                                                         |
| User taps `AudioReviewPlayButton` in review               | Toggles `playPendingRecording()` / `stopPlayback()`                                                                                          |

The camera session is **not** started when the user is on `.audio`. The mode
change still requests an eager stop, and the Record path independently awaits
`stopSessionAndWait()` as the correctness boundary before audio activation.

---

## 10. AVAudioSession Lifecycle

| Event                                      | Action                                                                                                                  |
| ------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------- |
| Camera → Audio record handoff              | Await camera-queue `stopRunning()` completion before activating the recording session                                   |
| `startRecording` called                    | `AudioSessionCoordinator.activate(.recordMeasurement(...))` from detached setup                                         |
| `cancelRecording()` or `finishRecording()` | Coordinator deactivates only the matching current lease with `notifyOthersOnDeactivation`                               |
| Task cancelled mid-setup                   | Startup cleanup stops the engine, removes the tap/file, and schedules lease deactivation                                |
| First activation fails                     | Coordinator deactivates any partial session and publishes no lease                                                      |
| Replacement activation fails               | Coordinator restores the prior configuration and lease; failed rollback deactivates and invalidates the partial session |

`notifyOthersOnDeactivation` signals the OS to restore ducked audio and ensures
`SpeechManager` can cleanly acquire its own session when the user swipes to
`.describe` mode.

---

## 11. Permissions

`NSMicrophoneUsageDescription` is already declared in `Info.plist` (shared with
`SpeechManager`). The red-button action calls
`AudioCaptureManager.requestMicrophonePermissionForRecording()` before waiting
for camera shutdown, so the first prompt remains visibly tied to the user tap.
`startRecording()` never prompts; it verifies the current authorization and
fails closed if permission is not granted. Denial throws
`AudioCaptureError.microphonePermissionDenied`, which is surfaced as a toast via
`viewModel.offlineToastMessage`.

### Physical-device acceptance

The focused simulator suites validate presentation, deterministic DSP policy,
state transitions, cancellation, and injected audio-session behavior. They do
not validate a real microphone input route, OS permission sheet, haptic, or
process-wide `AVAudioSession` handoff. Before release, use a signed
physical-device build to verify first-use permission, Camera-to-Audio startup,
record/pause/resume, early-stop review, mode/background preservation, the review
and auto-handoff maximum-duration branches, feedback, review playback/scrubbing,
and the Audio-to-Describe transition.

---

## 12. Audio Inference Backend

**Primary endpoint**: `services/supabase/functions/identify-multimodal/index.ts`

The active audio pipeline now routes through `/identify-multimodal`, not a
standalone `/audio-spec` endpoint. `/audio-spec` remains deployed only as a
compatibility route and writes the same ingestion ledger before returning
success. The multimodal handler:

1. Accepts exactly one typed audio transport: inline `audioBase64s` from live
   foreground requests or staged `audioR2ObjectKeys` from queued replay.
   Scalars, blank/non-string elements, or both nonempty arrays return a stable
   `400 invalid_audio_transport` / `ambiguous_audio_transport` response.
2. Requires a RIFF/WAVE container before `processWAV(...)` normalises the clip
   to mono 16 kHz WAV for Gemini ingestion. M4A or another container returns
   `400 unsupported_audio_codec`; malformed WAV returns
   `400 invalid_audio_content`. Neither case is silently discarded from a mixed
   request or promoted under an `audio/wav` label.
3. Chooses `BIOACOUSTIC_SYSTEM_INSTRUCTION` for audio-only requests or
   `MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION` when audio and images are combined.
4. Reuses the same `_shared/identify` DB, threshold, and moderation primitives
   as the image pipeline.

The combined image+audio branch does not currently reuse the complete image-only
whole-frame primary-subject instruction. Its blended prompt retains the
acoustic-versus-visual precedence policy. A still image with an accepted
`focusRegion` receives a separate tentative per-photo warning, but an unhinted
still or sampled video frame does not. Consequently, prompt behavior for an
incidental background organism is not yet identical between image-only and
combined requests, and no post-parser runtime classifier repairs that
difference. The shared base `is_biological_subject` field description also uses
visual-only wording when the blended provider schema is generated; this is a
known cross-modality contract gap.

Both the primary route and compatibility `/audio-spec` route import one shared
audio subject policy and private provider contract. The provider returns a
required internal `audio_subject_type` discriminator, which is validated and
removed before the server assembles the result. The public result still reuses
`is_biological_subject`, `common_name`, and `scientific_name`; there is no
audio-specific response field or client DTO. Audio-only subject precedence is:

1. Any confidently detected non-human animal sound, including a pet or livestock
   sound, outranks Human.
2. Confident non-human presence with unresolved taxonomy remains biological and
   displays as **Unidentified Wildlife** without candidates or species
   enrichment.
3. Human-only breathing, speech, coughing, snoring, or another unmistakable
   biological human sound returns **Human** / _Homo sapiens_. Handling noise by
   itself is not Human evidence.
4. Silence, weather, mechanical sound, handling noise, and indeterminate audio
   are non-biological and display as **No wildlife detected**.

The server normalizes the private structured discriminator and identity fields
after parsing and before dictionary or candidate work; it never infers the state
from free-form model reasoning. This makes a no-taxon Human breathing response
distinguishable from confidently unresolved wildlife. Mixed visual/audio scans
use the same non-human-over-Human acoustic tie-break without changing the
existing visual-versus-audio arbitration. Resolved non-human animals keep their
normal acoustic candidates. If a resolved non-human result has a blank,
placeholder, or incorrectly Human common name, the scientific name is used as a
safe display fallback without changing the selected taxon.

Human remains a durable biological result, but the existing Human presentation
policy suppresses candidate review, external reference imagery, Explore and
Community sharing, and Field Chat. An audio-only biological result without a
resolved taxon suppresses species-match confidence and sharing. Historical
`Unknown Subject` / `Taxonomy Unavailable` audio is displayed safely and may be
reanalyzed when its source recording is available; the client does not rewrite
the stored result or infer Human from old reasoning.

Owner-history sync selects and maps the existing `is_biological_subject` value
instead of defaulting imported audio records to biological. Explore eligibility
rejects non-biological, unresolved, and Human subjects in the shared local
predicate. The share endpoint independently rejects those states, missing
selected taxonomy, Human aliases/overrides, and unresolved sentinels; Ask the
Community reuses that validator. The `/insight-chat` endpoint also rejects
unresolved and Human taxonomy even when called directly, independently of the
iOS toolbar guard.

Malformed provider output remains retryable and is not persisted as a result.
Audio identification diagnostics may record bounded length, finish-reason, and
error classification, but never the raw provider response or a response preview.

For audio-only scans, `insertScan` persists `image_storage_urls: []`, durable
`audio_storage_urls`, and an audio item in the canonical `captured_media`
timeline. Standalone audio is promoted into durable scan storage and normalized
as a ready `scan_media_assets(kind = 'audio', role = 'audio')` row. Extracted
`video_audio` is inference-only only when a complete validated
`ownerMediaTimeline` proves that role; then it is deleted after finalization
because the shareable playback MP4 already contains its own audio track. The
timeline binds each standalone `sourceIndex` to its raw `audioInputIndex`, and
live submission plus offline replay produce paths, descriptors, and that
timeline from one chronological traversal. Missing legacy timeline metadata is
non-destructive: all resolved audio remains durable and ambiguous identity is
stripped rather than guessed.

New `captured_media` manifests preserve every audio and description item in its
submitted position. Owner-history sync supplements an incomplete or legacy
manifest from `audio_storage_urls` and `user_observation_context` before
replacing the local mixed-media timeline. This keeps a submitted audio plus
description scan playable and preserves its text provenance after reconciliation
or restore on another device. Intentional nonvisual results never display the
photo-specific `Original photo unavailable` carousel state. Legacy compatibility
columns do not store cross-modal positions, so missing audio is appended in
stored-array order and the stored description follows it. The compatibility
array is supplemental rather than deletion authority. History reconciliation
replaces a local standalone clip only on an exact path match or a unique
`sourceIndex` match. Legacy and restore references without that identity are
merged conservatively instead of consuming a local clip by ordinal guess, so an
ambiguous partial two-clip projection can duplicate an alias but cannot discard
the other recording. Unmatched local descriptions are retained because the scan
row stores only one context.

## 13. Explore Audio Publication

Standalone audio can be selected in the Explore composer. Audio publication is
separate from biological identification:

1. `/share-scan-to-explore` resolves the selected audio without writing or
   reactivating an Explore post.
2. `_shared/audioModeration.ts` fetches the bounded clip, computes SHA-256, and
   checks for an attestation with the same checksum, model, and derived policy
   contract. The share's UUID `Idempotency-Key` and checksum/policy version
   produce one deterministic, opaque quota reservation ID per audible item.
3. On a cache miss, the database atomically applies durable entitlement, daily
   quota, and per-user/IP rate limits, selects the moderation model (currently
   `gemini-2.5-flash`), and only then sends the clip inline to the structured
   classifier. Cache hits refund their provisional reservation.
4. An approved result allows the normal atomic post/media share write to run. A
   flagged result or provider/configuration failure returns an error and leaves
   the prior Explore state unchanged; failures never publish a post.
5. For standalone WAV media, the approved share/edit path generates or reuses a
   deterministic PNG spectrogram and snapshots its URL into both post-owned and
   normalized scan media. Thumbnail failure is non-blocking and retains the
   speaker fallback.
6. The Edge deployment reuses `GEMINI_PAID_API_KEY`. Transcripts and non-speech
   descriptions remain in function memory and are not written to Postgres, logs,
   or client payloads.

The classifier covers both speech and meaningful non-speech sounds, but no model
can guarantee complete detection; user reporting remains the post-publication
safety layer. The attestation row stores only checksum, decision, policy/model
identity, MIME type, byte size, and timestamp. It stores no audio, transcript,
URL, filename, or user identity.

Approved audio is available in the iOS Explore feed and public Next.js share
pages. Web playback uses native browser controls, requires user interaction, and
preloads metadata rather than the clip body. Audio-only WAV posts use their
persisted spectrogram on the post detail carousel and social metadata; the
public home grid uses the species reference thumbnail. Mixed posts expose every
approved audio item in canonical carousel order. Web detail offers an opt-in
fixed Boost Audio mode through an exact-host/public-path WAV stream, with local
gain, 35 Hz rumble filtering, peak limiting, per-post browser preference, and
original-playback fallback. Non-WAV legacy posts keep the speaker fallback. The
widget snapshot writer still filters out audio-only posts before applying its
12-item cap.

Legacy scans created before durable audio upload use an on-demand repair path.
When the original local WAV/M4A still exists, iOS validates the container and
rejects video-bearing or unsupported files before requesting an owner-scoped
audio staging URL. Restore names and MIME types are canonical (`.wav` with
`audio/wav`, `.m4a` with `audio/mp4`); M4A is accepted only with explicit
`scan_share_restore`. iOS uploads within the normal audio count/byte limits and
retries the share with `restored_audio_object_keys`. The backend promotes the
object, updates `audio_storage_urls` and canonical `captured_media`, refreshes
`scan_media_assets`, and only then runs publication moderation. Database-write
failure rolls back the promoted object. A legacy scan with no surviving local
recording cannot be reconstructed or shared as audio.

### Per-Post Explore Audio Boost

The iOS feed-card and post-detail ellipsis menus offer **Boost audio** when the
post's primary media item is standalone audio. Both surfaces share the same
device-local per-post preference and synchronize changes in process. This is a
listening aid, not a media transform: the canonical R2 object, scan media
record, public URL, checksum, and moderation attestation remain unchanged. Audio
playback remains user-initiated on both surfaces even when a saved boost
preference is restored.

Boost is opt-in and remembered independently for each immutable Explore `postId`
in device-local `UserDefaults`. New posts default to original audio. Entries are
touched when read, expire after 180 days, and are capped at the 500 most
recently accessed posts. The preference is not account-synced, sent to Supabase,
or restored after app deletion.

The shared `AudioBoostProcessor` performs a size-bounded download, analyzes RMS
and peak levels, and creates a temporary enhanced WAV. It targets quiet material
conservatively, caps gain at 18 dB, applies a gentle 35 Hz high-pass filter for
rumble, and clamps peaks near -1 dBFS. It deliberately avoids denoising because
broadband biological sounds must not be mistaken for noise. Enhanced files are
held in a bounded eight-item temporary cache and are never uploaded.

Changing mode preserves the current timestamp and whether playback was playing
or paused. After the user explicitly enables boost, the media surface shows
**Boosting audio…** while preparing. Saved-setting restoration and
notification-driven synchronization prepare silently. If user-initiated
download, decoding, or enhancement fails, the player continues with the original
recording and presents a concise fallback message; restoration failure falls
back without transient UI. Spectrogram, playhead, elapsed/total timestamp,
audio-session handling, interruption recovery, and one-active-player
coordination remain shared with original playback.

### Published and Insight Spectrogram Seeking

Standalone audio supports session-local seeking on focused listening surfaces.
Explore post detail accepts tap-to-jump and full-spectrogram horizontal
scrubbing. Insight audio pages accept tap-to-jump, but horizontal scrubbing must
begin within the playmarker's 44-point target so the surrounding native carousel
can still page normally. Both players pause during a drag and resume only when
they were playing before it began. Original and boosted sources use the same
normalized position, and VoiceOver adjusts playback in five-second steps.
Explore feed cards remain non-seekable to preserve their playback, like, and
navigation gesture contract. Feed and detail playheads sample the live AVPlayer
clock on SwiftUI's display-synchronized animation timeline while playback is
active, matching Insight playback without forcing the raster spectrogram or
timestamp badge to redraw every frame. Paused, waiting, and seeking states keep
the last stored progress so the line never advances ahead of audible playback.
`AudioSpectrogramSeekingPolicy` owns the shared clamping and display gate: live
time is eligible only when both UI playback intent and the concrete player say
they are playing. The players never extrapolate from a periodic observer tick.
Explore keeps its 100 ms observer for timestamp and lifecycle state, snapshots
the live clock immediately before a pause, and limits the display-rate update to
the thin playhead overlay.

Public web Explore playback is thumbnail-first. The home grid and post page use
the persisted audio media `thumbnail_url` when available, while the native audio
element remains the playback source. Blank or unsupported legacy formats keep a
speaker fallback. The service-role-only `backfill-explore-audio-spectrograms`
worker can repair historical WAV posts without changing the original recording
or moderation decision.

Audio playback feedback is action-bound rather than state-bound. Play uses a
medium pulse; pause and mode-off actions use a light impact; discrete seek taps
use selection feedback; and dragging emits only at scrub begin and commit.
Automatic playback, playback progress, completion, saved boost restoration, and
remote preference synchronization remain silent. All events route through
`HapticManager`, so the user's haptics and expedition-mode settings are honored.

The user-facing terminology is deliberately specific: the action remains **Boost
audio**, preparation reads **Boosting audio…**, and successful playback shows
**Boosted audio**. Merian does not call this “enhancement” because the local DSP
does not perform denoising or AI restoration.

### Scan-Library Insight Audio Boost

Completed persisted Insights containing standalone audio expose the same **Boost
audio** action in the top ellipsis menu and as a direct bottom-left spectrogram
control. A bottom-right badge shows elapsed and total playback time; both badges
reuse the image-attribution inset and material treatment so the overlapping
result card does not cover them. Insight preferences use a separate device-local
namespace keyed by immutable `scanId`; they do not change the setting of an
Explore post created from that scan. Entries retain the same 180-day and
500-scan bounds. One scan setting applies to every standalone audio page in a
mixed-media carousel.

`AudioBoostProcessor` lives under `Core/Media` and accepts bounded local paths,
`file://` URLs, or HTTPS media. Explore and Insight reuse its RMS/peak analysis,
18 dB cap, 35 Hz rumble filter, peak limiting, download deduplication, and
eight-item temporary output cache. Insight swaps `AVAudioPlayer` sources while
preserving current time and play/pause state. The original spectrogram remains
visible and the source recording is never overwritten, uploaded, or
re-moderated.

Saved settings restore silently. Explicit toolbar or spectrogram activation
shows **Boosting audio…**; successful preparation transitions the direct control
to **Boosted audio**, which can be tapped again to restore original playback. A
user-initiated failure reports that original audio is playing, while restoration
failure falls back silently. Insight telemetry uses `InsightAudioBoostChanged`
with action, `surface = insight`, and an optional coarse gain band only—never
scan IDs, paths, URLs, or audio content. The direct control uses **Boosting…**
and **Reverting…** disabled transition states while the enhanced or original
player source is being prepared.

PostHog records `ExploreAudioBoostChanged` for enabled, disabled, restored,
preparation-failed, and boosted-playback-started transitions. Properties are
limited to the Explore surface and a coarse gain band; media URLs, filenames,
audio content, transcripts, and species/post identity are excluded.

### Error Status Semantics

A cache hit returns the prior decision without requiring Gemini. On a cache
miss, Gemini API failures produce 503; malformed or policy-rejected decisions
produce the endpoint's bounded validation/rejection response; malformed media
payloads produce 400-class errors. Cache read/write failures never approve by
default: reads fall back to live moderation and write failures leave the live
decision valid for that request.

---

## 14. Implementation Status

| Item                                             | Status                                                                                                                            |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
| `/identify-multimodal` audio path                | **Complete** — live and replay audio route here                                                                                   |
| `/audio-spec` compatibility ledger               | **Complete** — staged legacy audio rows can recover through `/identify-multimodal`; inline legacy audio remains client-retry only |
| `InferenceEngine.analyzeNonVisual` live path     | **Complete** — in `InferenceEngine.swift`; audio shares the non-visual path with describe captures                                |
| iOS live audio request via inline `audioBase64s` | **Complete** — byte-preflighted in `MerianNetworkClient.buildMultiModalRequest`                                                   |
| Offline replay audio dispatch path               | **Complete** — queued audio uploads to R2 and replays as `audioR2ObjectKeys`                                                      |
| Two-phase R2 audio upload                        | **Complete for queued replay** — foreground live audio remains inline by design                                                   |
| Historical refinement audio preparation          | **Complete** — bounded local/HTTPS references materialize as Documents-owned canonical WAV sidecars before reanalysis             |
| Pre-WAV installed-queue repair                   | **Complete** — durable latch, stale-key reset, active-PUT interception, atomic timeline rewrite, and central claim refusal        |
| Purpose-aware audio signing and byte validation  | **Complete** — ordinary inference is WAV-only; M4A is restore-only; Identify verifies RIFF and full WAV structure                 |
| `deleteQueuedScan` / purge audio cleanup         | **Complete** — cleans Documents WAV on delete/purge                                                                               |
| Durable standalone audio media                   | **Complete** — promoted into `audio_storage_urls`, `captured_media`, and ready normalized asset rows                              |
| Explore audio publication moderation             | **Complete** — a content-addressed attestation or fresh Gemini speech/non-speech decision is a synchronous share precondition     |
| Per-post iOS audio boost                         | **Complete** — reversible local DSP with per-post device preference, bounded temporary files, and original-playback fallback      |

## 2026-04 Hardening Updates

- Recording startup cancellation is now fully symmetric with normal stop: input
  tap removed, engine stopped, DSP task cancelled, spectrogram stream finished,
  session deactivated, and temp WAV deleted.
- Live spectrogram history and `SpectrogramActor` noise-floor tracking now use
  bounded circular buffers instead of repeated `removeFirst()` shifts in the hot
  path.
- WatchOS acoustic handoff now reads and base64-encodes the recorded file in a
  detached utility task. `WatchAcousticManager` returns to `@MainActor` only to
  update state and dispatch the `WCSession` payload, preventing main-thread
  stalls on Apple Watch.
- `AudioCaptureManager` now centralizes spectrogram reset through one helper so
  cancellation, discard, and full reset all clear identical UI/audio state.

## 2026-08 Record Ownership Pass

- `Capture/Record` now has explicit `Models`, `Services`, `ViewModels`, `Views`,
  and `Components` owners. Only Services reference the concrete audio and haptic
  managers; Shell supplies the immutable presentation and narrow actions.
- The token-aware `AudioSessionCoordinator` moved out of the recording manager
  aggregate into its own Core Hardware file. Maximum-duration feedback is
  initializer-injected from `AppDIContainer`.
- Manager-owned startup/resume handles and `AudioCaptureTransitionState` now
  generation-fence lease acceptance, engine start, DSP publication, and
  countdown completion. Mode/background/reset invalidation rejects late
  non-cooperative completion; duplicate resume taps coalesce. Coordinator leases
  advance only after successful activation and are consumed on deactivation, so
  failed replacement restores the prior configuration and preserves its owner.
  Failed rollback deactivates the partial session and invalidates that
  ownership; failed first activation likewise deactivates partial state without
  publishing a lease.
- Palette, raster, and display-layout policy moved to
  `Core/Media/AudioSpectrogramRenderer.swift`; the shared SwiftUI surface moved
  to `Core/UI/Components/AudioSpectrogramView.swift`. Record retains its mounted
  review gesture and playhead timing.
- `RecordingCountdownBadge` moved to `Capture/Shared/Components` because Record
  audio and Scan video both consume it. The obsolete Record-local spectrogram
  and signal-guidance aggregate files were removed.
- Focused verification is mirrored under `Features/Capture/Record`,
  `Core/Hardware`, and `Core/Media`. It covers deterministic presentation,
  scrubbing and feedback boundaries, maximum-duration feedback injection, FFT
  and ambient-noise policy, transition invalidation, duplicate/stale resume,
  successful session-lease replacement, failed-activation restoration,
  rollback-failure invalidation, first-activation cleanup, raster construction,
  shared-owner placement, and the 600-line production-file review guard.
