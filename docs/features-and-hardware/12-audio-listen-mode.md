# Audio Listen Mode — Bioacoustic Capture Pipeline

The Audio page is the second page of `CaptureWorkspaceView`'s horizontal pager. It records a 15-second ambient audio clip, runs a live spectrogram and SNR analysis on-device in real time, and submits the clip for bioacoustic species identification via the unified `/identify-multimodal` Supabase Edge Function.

---

## 1. Architecture Overview

The audio pipeline is split across three isolation boundaries:

| Layer | Class | Thread |
|---|---|---|
| DSP / FFT | `SpectrogramActor` | Background actor |
| Recording & state | `AudioCaptureManager` | `@MainActor` |
| UI rendering | `AudioRecordingView`, `SpectrogramView`, `SNRGaugeView` | `@MainActor` (SwiftUI) |

This matches the camera pipeline's `CameraManager` → `ViewfinderIntelligence` → `CameraPreviewView` separation and avoids the IPC deadlock pattern that would occur if `AVAudioSession` were configured on `@MainActor`.

---

## 2. `SpectrogramActor` — DSP Worker

**File**: `apps/ios/Merian/Core/Hardware/SpectrogramActor.swift`

A Swift `actor` that runs all FFT and mel-scale arithmetic off the main thread, keeping `@MainActor` free for 60fps SwiftUI rendering.

### FFT Pipeline

```
AVAudioPCMBuffer → [zero-pad to 2048] → Hann window → Real FFT → power magnitude → dB → clamp → mel-scale → SpectrogramColumn
```

| Parameter | Value | Rationale |
|---|---|---|
| FFT size | 2048 points | 42.67 ms window at 48 kHz — enough frequency resolution to resolve bird harmonics |
| mel bins | 64 | Dense enough for species differentiation without memory pressure |
| Frequency range | 80 Hz – 16 kHz | Covers the bioacoustically relevant range for birds, insects, and frogs |
| dB floor | −80 dB | Clamps below-noise-floor energy to zero before normalization |

**`process(buffer:) -> SpectrogramColumn?`**  
Wrapped in `autoreleasepool` to prevent Obj-C `AVAudioPCMBuffer` objects from accumulating across repeated tap callbacks. Returns `nil` if the FFT setup is unavailable or the buffer is empty. The returned `SpectrogramColumn` carries:
- `magnitudes: [Float]` — 64 mel-scaled bins, 0.0–1.0 normalized
- `rms: Float` — pre-window RMS (used for SNR estimation)
- `peak: Float` — pre-window peak (used for clipping detection)

### SNR Estimation

**`snrLevel(from:) -> SNRLevel`** maintains a rolling history of the last 96 RMS values (~2 seconds at 4096-sample tap buffers). The minimum of this window is used as the estimated noise floor.

| Level | Condition | Meaning |
|---|---|---|
| `.clipping` | `peak > 0.95` | Mic overloaded — move away |
| `.warning` | SNR < 10 dB | High background noise — shield mic |
| `.caution` | 10 – 20 dB | Some noise present |
| `.clear` | SNR ≥ 20 dB | Clean signal |

**`reset()`** clears the noise floor history. Called by `AudioCaptureManager.reset()` between sessions to prevent prior noise estimates from contaminating the next recording.

---

## 3. `AudioCaptureManager` — Recording Pipeline

**File**: `apps/ios/Merian/Core/Hardware/AudioCaptureManager.swift`

`@MainActor @Observable` class. Registered in `AppDIContainer.shared.audioCaptureManager` and injected via `DIContainerModifier`.

### Published State

| Property | Type | Description |
|---|---|---|
| `isRecording` | `Bool` | Whether a recording session is active (set `true` only after `audioEngine.start()` succeeds) |
| `isPaused` | `Bool` | Whether the engine is paused mid-recording (tap preserved, countdown halted) |
| `recordingProgress` | `Double` | 0.0 → 1.0 over `maxDuration` (15 s) |
| `spectrogramColumns` | `[SpectrogramColumn]` | Rolling display buffer (180 columns ≈ 15 s) |
| `snrLevel` | `SNRLevel` | Most recent noise level classification |
| `pendingPlaybackPath` | `String?` | Non-nil after recording finishes, before user confirms or discards. Drives the review UI state in `AudioRecordingView`. |
| `isPlaying` | `Bool` | Whether `AVAudioPlayer` is currently playing back a pending recording |
| `playbackProgress` | `Double` | 0.0 → 1.0 playhead position during review playback; preserved across play/stop cycles for scrub-resume |
| `audioFilePath` | `String?` | Non-nil only when the user explicitly confirms via the review UI. Setting this triggers `onChange(of: audioFilePath)`, which either stages the clip into `stagedCapture.audios` (mixed-media / confirmation flows) or calls `submitAudio` directly for the standalone audio-only flow. |

### `startRecording() async throws`

Mirrors `SpeechManager.startDictation`'s `Task.detached` pattern to prevent `@MainActor` IPC deadlock against `mediaserverd`:

```
guard !isRecording, !isStartingRecording   ← re-entry guard (set before any await)
    ↓
discardPending()            ← clears leftover review state
requestRecordPermission()   ← async, off main actor
    ↓ Task.isCancelled check
teardownEngine()            ← clears any prior engine session
    ↓
Task.detached {
    AVAudioSession.setCategory(.record, mode: .measurement)
    AVAudioSession.setActive(true)
    inputNode.outputFormat(forBus: 0)     ← IPC: never call on @MainActor
    AVAudioFormat(.pcmFormatInt16, ...)   ← canonical Int16 PCM — wav.ts compatible
    AVAudioFile(forWriting: fileURL, settings: int16Fmt.settings)
    inputNode.removeTap(onBus: 0)         ← defensive: prevents nullptr == Tap() crash
    inputNode.installTap(...)             ← file write + DSP dispatch per buffer
    audioEngine.start()
}.value
    ↓
isRecording = true
recordingTask = Task { 100 ticks × 0.15 s → finishRecording() }
```

**Re-entry guard**: `isStartingRecording` is set to `true` before the first `await` (permission request) and cleared in `defer`. This prevents a second `startRecording()` call from slipping through the `!isRecording` guard during the async setup window — the condition that triggered the `nullptr == Tap()` AVAudioEngine crash.

**WAV file format**: The recording uses an explicit `AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate:, channels:, interleaved: true)` to write canonical Int16 PCM WAV (`audioFormat = 1`). Writing with the hardware's native `fmt.settings` may produce WAVEFORMATEXTENSIBLE (`audioFormat = 0xFFFE`) — a variant the edge audio parsers do not handle — causing 400 errors on submission. `AVAudioFile` converts Float32→Int16 automatically on each write.

**Buffer tap (per 4096-frame buffer ≈ 85 ms)**:
1. `file.write(from: buffer)` — synchronous PCM write to `AVAudioFile` on the audio thread.
2. `copyPCMBuffer(buffer)` copies the tap-owned PCM data synchronously, then yields it into a bounded `AsyncStream(bufferingNewest: 2)` so reused engine buffers never cross the async boundary.
3. A detached DSP consumer drains that bounded stream, calls `SpectrogramActor.process(buffer:)`, derives the SNR level, and hops back to `@MainActor` only for the small UI update.

The `[weak manager]` capture in the inner `@MainActor` task breaks the retain cycle: `AudioCaptureManager → audioEngine → inputNode → tap closure → manager`.

### Teardown

`teardownEngine()` calls `inputNode.removeTap(onBus: 0)` **first**, then `audioEngine.stop()` — both are no-ops if already stopped/untapped. Removing the tap before stopping prevents the audio thread from writing into a stopped engine and avoids AVAudioEngine assertion failures. The `AVAudioSession` is deactivated asynchronously via `Task.detached` to avoid `mediaserverd` IPC blocking `@MainActor`.

### Recording Lifecycle

| Method | Effect |
|---|---|
| `startRecording()` | Guards with `!isRecording && !isStartingRecording`. Acquires permission, calls `discardPending()` to clear leftover review state, spins up engine, starts 15 s countdown |
| `stopRecordingEarly()` | Cancels countdown task, calls `finishRecording()` — same end state as timer completion |
| `pauseRecording()` | Cancels countdown task, calls `audioEngine.pause()`, sets `isPaused = true`, resets `snrLevel` |
| `resumeRecording()` | Re-activates `AVAudioSession` in `Task.detached`, calls `audioEngine.start()`, sets `isPaused = false`, rebuilds countdown from `recordingProgress` |
| `cancelRecording()` | Cancels countdown task, tears down engine, deletes partial file from `tmp/`, calls `discardPending()` to also clear review state |
| `finishRecording()` (private) | Tears down engine, sets `pendingPlaybackPath = pendingFileName` — routes to review state instead of direct submission |
| `playPendingRecording()` | Saves `resumeProgress = playbackProgress` (preserves scrubbed position), creates `AVAudioPlayer`, seeks to `duration * resumeProgress`, activates `.playback` session in `Task.detached`, sets `isPlaying = true`. Duration-based sleep (`remaining = duration * (1 - resumeProgress)`) clears `isPlaying` at end-of-file; reference equality guards against stop→replay races. |
| `stopPlayback()` | Stops `AVAudioPlayer`, clears `isPlaying` and `playbackProgress` |
| `seekPlayback(to:)` | Sets `audioPlayer.currentTime = duration * clamped` and updates `playbackProgress` — works while playing or stopped |
| `confirmAndSubmit()` | Stops playback, sets `audioFilePath = pendingPlaybackPath`, clears `pendingPlaybackPath` — triggers `onChange` in `CaptureWorkspaceView` |
| `discardPending()` | Stops playback, deletes file from `tmp/` if `pendingPlaybackPath` is set, clears `pendingPlaybackPath`, **always** clears `spectrogramColumns`, `snrLevel`, `snrHoldTicks` |
| `reset()` | Calls `stopPlayback()`, cancels tasks, tears down the engine/tap/session lease, deletes any unsubmitted pending temp file, clears all published state including `pendingPlaybackPath`, calls `spectrogram.reset()` |

**`discardPending()` clears display state unconditionally**: The spectrogram column clear and SNR reset run outside the `if let pendingPlaybackPath` branch so that calling `discardPending()` during an active recording (e.g. immediately before `startRecording()`) also wipes the previous session's visual state. The prior `guard let name = pendingPlaybackPath else { return }` early-exit pattern leaked these columns into the next recording's UI.

**Submission state machine:**
```
startRecording() → [recording] ──────────────────────────────────────── pauseRecording()
                       ↓ timer / stopRecordingEarly()                          ↓
                  finishRecording()                                       [paused] ── resumeRecording() → [recording]
                       ↓
                  [review: pendingPlaybackPath set]
                       ↓ confirmAndSubmit()
                  [submitted: audioFilePath set]
                       ↓ CaptureWorkspaceView.onChange
                  [stage into toolbar OR submitAudio] → reset()

                  [review] → discardPending() → [idle]
```

`CaptureWorkspaceView.onChange(of: audioCaptureManager.audioFilePath)` fires only when the user explicitly confirms; this replaces the previous auto-submit that fired immediately when recording finished. If the user already has staged images, videos, or descriptions, if multi-capture mode is enabled, or if explicit confirmation is required, the confirmed clip is appended to `stagedCapture.audios` and shares the same 2-item total mixed-media cap as images, videos, and descriptions. Otherwise the audio-only path calls `submitAudio(...)` immediately.

### File Format

Audio is written to `FileManager.default.temporaryDirectory/<uuid>.wav` as **Int16 PCM WAV** (`audioFormat = 1`, interleaved) using an explicit `AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: fmt.sampleRate, channels: fmt.channelCount, interleaved: true)`. The hardware's native Float32 format may produce WAVEFORMATEXTENSIBLE (`audioFormat = 0xFFFE`), which the edge audio parsers do not support and returns 400. `AVAudioFile` performs the Float32→Int16 conversion automatically per write. The shared non-visual queue path (`enqueueNonVisualCapture`) moves the file from `tmp/` to `URL.documentsDirectory` for persistence.

---

## 4. Submission Flow — `AudioAnalysis.swift`

**File**: `apps/ios/Merian/Features/Capture/Submission/ViewModels/AudioAnalysis.swift`

`extension CaptureWorkspaceViewModel { func submitAudio(audioFileName:modelContext:) }` now routes through the shared non-visual submission path rather than a dedicated audio-only analyzer.

```
debounce check (1.5 s, CFAbsoluteTimeGetCurrent)
    ↓
cameraManager.resetZoom()
    ↓ Task { await preFetchTask?.value }   ← resolves GPS + WeatherKit from pre-warm
    ↓
submitNonVisualCapture(
    audioFileNames: [audioFileName],
    observationContexts: [],
    mediaTimeline: [.audio(audioFileName)],
    modelContext: modelContext
)
```

**Live + offline dual-path**: audio-bearing captures always enqueue durably first (moving the WAV into `Documents/` and creating a `.pending` queue record for R2 staging). When offline the flow shows a toast and stops without calling `InferenceEngine.prepareForNewScan()`. When online it prepares the live engine, opens the insight sheet, and fires `InferenceEngine.analyzeNonVisual(...)`. On live success, `flushOfflineQueuedScan` + `deleteQueuedScan` immediately clean up the queue record — preventing the background replay cycle from making a redundant Gemini call on the same file.

---

## 5. `OfflineQueueManager.enqueueNonVisualCapture` — Queue Record

**Files**: `apps/ios/Merian/Core/Data/OfflineSync/OfflineQueueManager+Queue.swift`, `OfflineQueueManager+URLSession.swift`

Audio now uses the same ordered queue shape as every other mixed-media submission. The queue record stores the serialized media timeline in `capturedMediaJSON`, and V41 also materializes that timeline into the `capturedMediaEntries` relationship mirror.

```
move tmp/<uuid>.wav → Documents/<uuid>.wav
    ↓ quota check (UsageManager.canPerformScan / consumeScan)
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
```

Audio-only records upload their WAV/M4A via background `URLSession.uploadTask(with:fromFile:)` and persist the resulting staging key in `stagedR2Keys`. `dispatchInferenceDownloadTask` splits those keys into image `r2ObjectKeys` and audio `audioR2ObjectKeys`, so queued replay never builds a large inline audio request body.

**Cleanup on delete**: Audio files stored in `Documents/` are cleaned up through the same canonical media snapshot walk used for images. Delete and purge paths no longer special-case image arrays and therefore do not lose audio cleanup.

---

## 6. Inference Path

There is no longer a dedicated `InferenceEngine+Audio.swift` path. Audio uses the same non-visual entry point as description-only captures:

1. `CaptureWorkspaceViewModel.submitAudio(...)` delegates to `submitNonVisualCapture(...)`.
2. `InferenceEngine.analyzeNonVisual(...)` forwards `audioFilePaths`, any `observationContexts`, and the ordered `mediaTimeline`.
3. `MerianNetworkClient.buildMultiModalRequest(...)` sends live foreground WAVs as size-preflighted `audioBase64s`; queued replay sends R2-backed `audioR2ObjectKeys`.
4. `InferenceProcessingActor.parseAndSave(...)` routes the result through `BackgroundDatabaseActor.saveNonVisualRecord(...)`.

Replay uses the same endpoint and payload shape through the offline queue’s shared non-visual branch.

---

## 7. UI Layer

### `AudioRecordingView`

**File**: `apps/ios/Merian/Features/Capture/Record/Views/AudioRecordingView.swift`

Full-screen content view for the `.audio` pager page. All persistent controls (capture button, `MediaModeToggle`, tab bar, flanking action buttons) live in `CaptureWorkspaceView`'s fixed overlay layers.

| State | Condition | Content |
|---|---|---|
| Idle | `!isRecording && pendingPlaybackPath == nil` | Rotating carousel of animal illustration images (6 s crossfade interval) |
| Recording / Review | `isRecording \|\| pendingPlaybackPath != nil` | Live or static `SpectrogramView` · `SNRGaugeView` below spectrogram (recording only) |

**Spectrogram sizing**: The spectrogram height is computed symmetrically from `composingCenter` (the vertical center of the composing area between `MediaModeToggle` and the control bar):
```swift
let centerY = proxy.size.height * composingCenter
let halfHeight = min(centerY - 100, proxy.size.height - controlBarHeight - centerY - 88)
let spectrogramHeight = max(180, halfHeight * 2)
```
This ensures the spectrogram clears the `MediaModeToggle` toolbar above and the tooltip hint zone above the FAB below. The view uses `.frame(width: proxy.size.width)` before `.position()` to correctly offer full width to the Canvas (`.position()` detaches from layout flow and would otherwise receive zero width from `maxWidth: .infinity`).

**Review state — playhead**: A vertical scrub line overlays the spectrogram during review. It is visible only when `isPlaying || isScrubbing || playbackProgress > 0`. This means it appears only once the user has started playback or manually scrubbed — not by default when the recording first enters review. If the user scrubs the playhead away from the start position and stops, the playhead remains visible at the parked position. On full-clip playback completion, `playbackProgress` resets to 0 and the playhead disappears. A `DragGesture` on the spectrogram canvas drives `seekPlayback(to:)`, enabling scrub-to-any-position with live playhead tracking.

**Insight carousel playback**: Persisted audio pages use
`AudioPlaybackCarouselPage`. The page does not mount a 60 Hz Combine timer.
Progress updates run inside `.task(id: isPlaying)` only while the
`AVAudioPlayer` is actively playing, polling every 100 ms and stopping when
playback stops, completes, or the page disappears. This keeps idle insight
carousels from burning battery just because an audio page is visible.

The countdown ring uses `Circle.trim(from: 0, to: recordingProgress)` with `.animation(.linear(duration: 0.15))` matching the 150 ms tick interval of the `recordingTask`.

### `SpectrogramView`

**File**: `apps/ios/Merian/Features/Capture/Record/Views/SpectrogramView.swift`

Canvas-based 2D spectrogram. Draws one vertical strip per `SpectrogramColumn`, left (oldest) to right (newest), with frequency increasing bottom-to-top (bin 0 = 80 Hz at bottom, bin 63 = 16 kHz at top). The canvas background is a fixed dark field (`Color(red: 0.06, green: 0.06, blue: 0.1)`) so the colormap's near-black low-magnitude cells blend seamlessly into the background.

**Column width**: `colWidth = size.width / CGFloat(columns.count)`. Dividing by the actual column count (not `columnCap`) ensures data always fills edge-to-edge regardless of whether the buffer is partially populated at early recording frames. At 44.1 kHz the engine produces ~161 columns at clip end — using `columnCap` (180) as the divisor would leave a ~40 px gap at the right edge.

**Colormap** (5-stop inferno-style, no magnitude threshold — all values rendered):

| Magnitude | Color |
|---|---|
| 0.0 – 0.2 | Black → dark blue (`rgb(0, 0, 0.8t)`) |
| 0.2 – 0.5 | Dark blue → cyan |
| 0.5 – 0.75 | Cyan → yellow |
| 0.75 – 1.0 | Yellow → white |

Draws up to `columnCap × outputBinCount = 180 × 64 = 11,520` filled rects per frame. At 60fps this is ~690K path fills/second — acceptable for `Canvas` (no SwiftUI view allocations).

### `SNRGaugeView`

**File**: `apps/ios/Merian/Features/Capture/Record/Views/SNRGaugeView.swift`

Rounded pill showing SNR level with a color-coded background and SF Symbol icon. Triggers a keyframe shake animation on `.clipping` events using sequential `DispatchQueue.main.asyncAfter` calls.

| `SNRLevel` | Color | Label |
|---|---|---|
| `.clear` | Green | "Clear" |
| `.caution` | Yellow | "Some noise" |
| `.warning` | Orange | "Shield mic" |
| `.clipping` | Red (shake) | "Move mic away" |

---

## 8. `CaptureControlBar` — Audio Button Wiring

### Center capture button (`CaptureButton`)

The `.audio` case of `CaptureButton.onAction` in `CaptureControlBar` implements a multi-state dispatch:

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
        Task {
            do { try await audioCaptureManager.startRecording() }
            catch { viewModel.offlineToastMessage = error.localizedDescription }
        }
    }
```

Errors (permission denied, hardware unavailable) surface via `offlineToastMessage`.

### Center button visual state machine

The `CaptureButton` inner fill and icon encode the **available action**, not the current state:

| Condition | Fill | Icon | Meaning |
|---|---|---|---|
| Idle | Red | None | "Tap to record" |
| Paused | Red | None | "Tap to resume" |
| Recording (active) | Neutral (`.primary`) | `pause.fill` | "Tap to pause" |
| Review | Neutral (`.primary`) | `↑` or `+` | "Tap to submit" |

Red always means "tap here to start or resume recording." Neutral with a pause icon means "tap here to pause." The progress arc (red, sweeping clockwise) is hidden during review so the ring resets to a clean submit-button appearance.

### Flanking buttons (left / right slots)

| State | Left button | Right button |
|---|---|---|
| Idle | — | — |
| Recording (active or paused) | `AudioDeleteButton` (trash — cancel + discard) | `AudioDoneButton` (checkmark — stop early → review) |
| Review | `AudioDeleteButton` (trash — discard pending) | `AudioReviewPlayButton` (play/stop toggle) |

`AudioDeleteButton` calls `cancelRecording()` while recording and `discardPending()` during review. `AudioDoneButton` calls `stopRecordingEarly()`. `AudioReviewPlayButton` toggles `playPendingRecording()` / `stopPlayback()`, showing `play.fill` or `stop.fill` with a `.symbolEffect(.replace)` transition.

All flanking buttons animate in/out with `.easeInOut(duration: 0.2)` keyed on `captureMode`, `isRecording`, and `pendingPlaybackPath`.

---

## 9. Session Lifecycle

| Trigger | Action |
|---|---|
| Swipe from `.audio` to another mode | `cancelRecording()` if active or paused — clears engine, file, and review state |
| App backgrounds while `.audio` active | Same: `cancelRecording()` if recording or paused |
| 15 s countdown completes | `finishRecording()` → sets `pendingPlaybackPath` → transitions to review state |
| User taps `AudioDoneButton` (checkmark) while recording | `stopRecordingEarly()` → same end state as countdown completion |
| User taps center button while recording | `pauseRecording()` → engine paused, countdown halted |
| User taps center button while paused | `resumeRecording()` → engine and countdown resumed from current progress |
| User taps `AudioDeleteButton` while recording/paused | `cancelRecording()` → returns to idle |
| User taps center button in review | `confirmAndSubmit()` → sets `audioFilePath` → `CaptureWorkspaceView.onChange` either stages the clip or calls `submitAudio` |
| User taps `AudioDeleteButton` in review | `discardPending()` → returns to idle |
| User taps `AudioReviewPlayButton` in review | Toggles `playPendingRecording()` / `stopPlayback()` |

The camera session is **not** started when the user is on `.audio` (camera is stopped on `captureMode` change to `.audio`, same as `.describe`).

---

## 10. AVAudioSession Lifecycle

| Event | Action |
|---|---|
| `startRecording` called | `.setCategory(.record, mode: .measurement)` + `.setActive(true)` — in `Task.detached` |
| `cancelRecording()` or `finishRecording()` | `.setActive(false, options: .notifyOthersOnDeactivation)` — in `Task.detached` |
| Task cancelled mid-setup | Session deactivation fires before returning from `startRecording` |

`notifyOthersOnDeactivation` signals the OS to restore ducked audio and ensures `SpeechManager` can cleanly acquire its own session when the user swipes to `.describe` mode.

---

## 11. Permissions

`NSMicrophoneUsageDescription` is already declared in `Info.plist` (shared with `SpeechManager`). `AudioCaptureManager.startRecording()` calls `AVAudioApplication.requestRecordPermission()` at runtime — not at app launch. First-time users on the `.audio` page see the iOS microphone permission dialog. Denial throws `AudioCaptureError.microphonePermissionDenied`, which is surfaced as a toast via `viewModel.offlineToastMessage`.

---

## 12. Audio Inference Backend

**Primary endpoint**: `services/supabase/functions/identify-multimodal/index.ts`

The active audio pipeline now routes through `/identify-multimodal`, not a standalone `/audio-spec` endpoint. The handler:

1. Accepts inline `audioBase64s` from live foreground requests and staged `audioR2ObjectKeys` from queued replay.
2. Runs `processWAV(...)` to normalise the clip to mono 16 kHz WAV before Gemini ingestion.
3. Chooses `BIOACOUSTIC_SYSTEM_INSTRUCTION` for audio-only requests or `MULTIMODAL_BLENDED_SYSTEM_INSTRUCTION` when audio and images are combined.
4. Reuses the same `_shared/identify` DB, threshold, and moderation primitives as the image pipeline.

For audio-only scans, `insertScan` persists `image_storage_urls: []` and the same scan metadata contract used elsewhere. Staged audio keys are inference inputs only and are deleted from R2 after successful background ingestion.

### Error Status Semantics

Mirrors the other inference endpoints: Gemini API failures → 503 (transient, iOS offline queue retries); malformed JSON → 422 (permanent, tombstone after `maxUploadRetries`); malformed audio payloads → 400.

---

## 13. Implementation Status

| Item | Status |
|---|---|
| `/identify-multimodal` audio path | **Complete** — live and replay audio route here |
| `InferenceEngine.analyzeNonVisual` live path | **Complete** — in `InferenceEngine.swift`; audio shares the non-visual path with describe captures |
| iOS live audio request via inline `audioBase64s` | **Complete** — byte-preflighted in `MerianNetworkClient.buildMultiModalRequest` |
| Offline replay audio dispatch path | **Complete** — queued audio uploads to R2 and replays as `audioR2ObjectKeys` |
| Two-phase R2 audio upload | **Complete for queued replay** — foreground live audio remains inline by design |
| `deleteQueuedScan` / purge audio cleanup | **Complete** — cleans Documents WAV on delete/purge |

## 2026-04 Hardening Updates

- Recording startup cancellation is now fully symmetric with normal stop: input tap removed, engine stopped, DSP task cancelled, spectrogram stream finished, session deactivated, and temp WAV deleted.
- Live spectrogram history and `SpectrogramActor` noise-floor tracking now use bounded circular buffers instead of repeated `removeFirst()` shifts in the hot path.
- WatchOS acoustic handoff now reads and base64-encodes the recorded file in a detached utility task. `WatchAcousticManager` returns to `@MainActor` only to update state and dispatch the `WCSession` payload, preventing main-thread stalls on Apple Watch.
- `AudioCaptureManager` now centralizes spectrogram reset through one helper so cancellation, discard, and full reset all clear identical UI/audio state.
