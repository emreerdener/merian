# Audio Listen Mode — Bioacoustic Capture Pipeline

The Audio page is the second page of `CaptureWorkspaceView`'s horizontal pager. It records a 12-second ambient audio clip, runs a live spectrogram and SNR analysis on-device in real time, and submits the clip for bioacoustic species identification via the `audio_spec` Supabase Edge Function.

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

**File**: `merian/Core/Hardware/SpectrogramActor.swift`

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

**File**: `merian/Core/Hardware/AudioCaptureManager.swift`

`@MainActor @Observable` class. Registered in `AppDIContainer.shared.audioCaptureManager` and injected via `DIContainerModifier`.

### Published State

| Property | Type | Description |
|---|---|---|
| `isRecording` | `Bool` | Whether a recording session is active |
| `recordingProgress` | `Double` | 0.0 → 1.0 over `maxDuration` (12 s) |
| `spectrogramColumns` | `[SpectrogramColumn]` | Rolling display buffer (120 columns ≈ 10 s) |
| `snrLevel` | `SNRLevel` | Most recent noise level classification |
| `pendingPlaybackPath` | `String?` | Non-nil after recording finishes, before user confirms or discards. Drives the review UI state in `AudioRecordingView`. |
| `isPlaying` | `Bool` | Whether `AVAudioPlayer` is currently playing back a pending recording |
| `audioFilePath` | `String?` | Non-nil only when the user explicitly confirms via the review UI. Setting this triggers `onChange(of: audioFilePath)` → `submitAudio`. |

### `startRecording() async throws`

Mirrors `SpeechManager.startDictation`'s `Task.detached` pattern to prevent `@MainActor` IPC deadlock against `mediaserverd`:

```
requestRecordPermission()   ← async, off main actor
    ↓ Task.isCancelled check
teardownEngine()            ← clears any prior session
    ↓
Task.detached {
    AVAudioSession.setCategory(.record, mode: .measurement)
    AVAudioSession.setActive(true)
    inputNode.outputFormat(forBus: 0)   ← IPC: never call on @MainActor
    AVAudioFile(forWriting: fileURL)    ← creates PCM WAV in tmp/
    inputNode.installTap(...)           ← file write + DSP dispatch per buffer
    audioEngine.start()
}.value
    ↓
isRecording = true
recordingTask = Task { 100 ticks × 0.12 s → finishRecording() }
```

**Buffer tap (per 4096-frame buffer ≈ 85 ms)**:
1. `file.write(from: buffer)` — synchronous PCM write to `AVAudioFile` on the audio thread.
2. `Task.detached { await actor.process(buffer:) → snrLevel → Task { @MainActor [weak self] in update UI } }` — DSP is actor-isolated; spawning detached prevents the audio thread from blocking on actor hops.

The `[weak manager]` capture in the inner `@MainActor` task breaks the retain cycle: `AudioCaptureManager → audioEngine → inputNode → tap closure → manager`.

### Teardown

`teardownEngine()` calls `audioEngine.stop()` then `inputNode.removeTap(onBus: 0)` **unconditionally** (both are no-ops if already stopped) — identical to `SpeechManager.teardownAudioEngine()`. This prevents an orphaned-tap crash if `start()` throws after `installTap` has already been called. The `AVAudioSession` is deactivated asynchronously via `Task.detached` to avoid `mediaserverd` IPC blocking `@MainActor`.

### Recording Lifecycle

| Method | Effect |
|---|---|
| `startRecording()` | Acquires permission, calls `discardPending()` to clear leftover review state, spins up engine, starts 12 s countdown |
| `cancelRecording()` | Cancels countdown task, tears down engine, deletes partial file from `tmp/`, calls `discardPending()` to also clear review state |
| `finishRecording()` (private) | Tears down engine, sets `pendingPlaybackPath = pendingFileName` — routes to review state instead of direct submission |
| `playPendingRecording()` | Creates `AVAudioPlayer`, activates `.playback` session in `Task.detached`, sets `isPlaying = true`. Duration-based timer clears `isPlaying` at end-of-file; reference equality guards against stop→replay races. |
| `stopPlayback()` | Stops `AVAudioPlayer`, clears `isPlaying` |
| `confirmAndSubmit()` | Stops playback, sets `audioFilePath = pendingPlaybackPath`, clears `pendingPlaybackPath` — triggers `onChange` in `CaptureWorkspaceView` |
| `discardPending()` | Stops playback, deletes file from `tmp/`, clears `pendingPlaybackPath`, `spectrogramColumns`, `snrLevel` |
| `reset()` | Calls `stopPlayback()`, cancels task, clears all published state including `pendingPlaybackPath`, calls `spectrogram.reset()` |

**Submission state machine:**
```
startRecording() → [recording] → finishRecording() → [review: pendingPlaybackPath set]
                                                           ↓ confirmAndSubmit()
                                                      [submitted: audioFilePath set]
                                                           ↓ CaptureWorkspaceView.onChange → submitAudio + reset()
                                                           
                                       [review] → discardPending() → [idle]
```

`CaptureWorkspaceView.onChange(of: audioCaptureManager.audioFilePath)` fires only when the user explicitly confirms; this replaces the previous auto-submit that fired immediately when recording finished.

### File Format

Audio is written to `FileManager.default.temporaryDirectory/<uuid>.wav` in the native `AVAudioEngine` input format (Float32 PCM at 48 kHz, typically mono on iPhone). `OfflineQueueManager.enqueueAudio` moves the file from `tmp/` to `URL.documentsDirectory` for persistence.

---

## 4. Submission Flow — `AudioAnalysis.swift`

**File**: `merian/Features/CaptureWorkspace/Core/ViewModels/AudioAnalysis.swift`

`extension CaptureWorkspaceViewModel { func submitAudio(audioFileName:modelContext:) }` — mirrors `submitDescribeSolo` structurally.

```
debounce check (1.5 s, CFAbsoluteTimeGetCurrent)
    ↓
cameraManager.resetZoom()
    ↓ Task { await preFetchTask?.value }   ← resolves GPS + WeatherKit from pre-warm
    ↓
OfflineQueueManager.enqueueAudio(audioFileName:telemetry:scanId:)
offlineToastMessage = "Audio captured. Queued for analysis."
stagedCapture.clearAll()
```

**Live + offline dual-path**: `submitAudio` always calls `enqueueAudio` first (moves WAV to Documents, creates `.staged` queue record). When offline it shows a toast and stops. When online it eagerly opens the insight sheet (`activeSheet = .insight`) and fires `analyzeAudio`. On live success, `flushOfflineQueuedScan` + `deleteQueuedScan` immediately clean up the queue record — preventing the background replay cycle from making a redundant Gemini call on the same file.

---

## 5. `OfflineQueueManager.enqueueAudio` — Queue Record

**File**: `merian/Core/Data/OfflineSync/OfflineQueueManager+AudioQueue.swift`

Mirrors `enqueueDescribe` but moves the audio file to `Documents/` (parallel to image files) and populates `OfflineQueuedScan.audioFilePath` instead of `observationContextJSON`.

```
move tmp/<uuid>.wav → Documents/<uuid>.wav
    ↓ quota check (UsageManager.canPerformScan / consumeScan)
OfflineQueuedScan(
    localImagePaths: [],
    scanState: .staged,         ← no R2 upload phase for audio
    audioFilePath: audioFileName
)
modelContext.insert(scan)
modelContext.save()
updateUnsyncedItemCount()
AppTelemetry.trackOfflineQueued()
```

Audio-only `.staged` records are **skipped** by `replayInferenceStagedScans` via a `guard scan.audioFilePath == nil else { continue }` guard at the top of the dispatch loop. Without this guard, the existing image/describe replay pipeline would attempt to call the inference endpoint with empty `localImagePaths` and no `observationContextJSON`, producing a 400 error and eventually tombstoning the record. When `audio_spec` ships, a dedicated dispatch path in `replayInferenceStagedScans` will handle these records.

**Cleanup on delete**: Audio files stored in `Documents/` should be cleaned up when the `OfflineQueuedScan` is deleted. `deleteQueuedScan(scanId:)` iterates `scan.localImagePaths` for image cleanup; audio file cleanup should be added to that path when the full pipeline is wired.

---

## 6. `InferenceEngine+Audio.swift` — Backend Stub

**File**: `merian/Core/AI/InferenceEngine+Audio.swift`

Stub ready for the `audio_spec` edge function. When the endpoint is live, this function will:
1. Upload `Documents/<uuid>.wav` to Cloudflare R2 staging.
2. Call the `audio_spec` Supabase Edge Function with the R2 key.
3. Parse the `EdgeResponse` and call `InferenceProcessingActor.shared.parseAndSave`.

Until then, `submitAudio` routes all submissions through `enqueueAudio` and this function is never called.

---

## 7. UI Layer

### `AudioRecordingView`

**File**: `merian/Features/CaptureWorkspace/Modalities/Audio/Views/AudioRecordingView.swift`

Full-screen content view for the `.audio` pager page. All persistent controls (capture button, `MediaModeToggle`, tab bar) live in `CaptureWorkspaceView`'s fixed overlay.

| State | Condition | Content |
|---|---|---|
| Idle | `!isRecording && pendingPlaybackPath == nil` | Centered waveform icon + "Tap the button below to start listening" |
| Recording | `isRecording == true` | `SNRGaugeView` (top) · live `SpectrogramView` (middle, 240 pt) · progress ring + countdown (bottom) |
| Review | `!isRecording && pendingPlaybackPath != nil` | "Review Recording" label (top) · static `SpectrogramView` (middle) · play/stop toggle (52pt SF Symbol) · Discard / Identify action buttons (bottom) |

**Review state**: The static spectrogram uses the same `spectrogramColumns` array captured during the recording — it shows the complete acoustic signature of the take before the user commits. The `CaptureControlBar` capture button is **disabled** while in review state (guarded by `audioCaptureManager.pendingPlaybackPath != nil`), preventing accidental new recordings from overwriting the pending clip.

The countdown ring uses `Circle.trim(from: 0, to: recordingProgress)` with `.animation(.linear(duration: 0.12))` matching the 120 ms tick interval of the `recordingTask`.

### `SpectrogramView`

**File**: `merian/Features/CaptureWorkspace/Modalities/Audio/Views/SpectrogramView.swift`

Canvas-based 2D spectrogram. Draws one vertical strip per `SpectrogramColumn`, left (oldest) to right (newest), with frequency increasing bottom-to-top (bin 0 = 80 Hz at bottom, bin 63 = 16 kHz at top).

**Colormap** (5-stop inferno-style):

| Magnitude | Color |
|---|---|
| 0.0 – 0.2 | Black → dark blue |
| 0.2 – 0.5 | Dark blue → cyan |
| 0.5 – 0.75 | Cyan → yellow |
| 0.75 – 1.0 | Yellow → white |

Draws `columnCap × outputBinCount = 120 × 64 = 7,680` filled rects per frame. At 60fps this is ~460K path fills/second — acceptable for `Canvas` (no SwiftUI view allocations).

### `SNRGaugeView`

**File**: `merian/Features/CaptureWorkspace/Modalities/Audio/Views/SNRGaugeView.swift`

Rounded pill showing SNR level with a color-coded background and SF Symbol icon. Triggers a keyframe shake animation on `.clipping` events using sequential `DispatchQueue.main.asyncAfter` calls.

| `SNRLevel` | Color | Label |
|---|---|---|
| `.clear` | Green | "Clear" |
| `.caution` | Yellow | "Some noise" |
| `.warning` | Orange | "Shield mic" |
| `.clipping` | Red (shake) | "Move mic away" |

---

## 8. `CaptureControlBar` — Audio Button Wiring

The `.audio` case of `CaptureButton.onAction` in `CaptureControlBar`:

```swift
case .audio:
    if audioCaptureManager.isRecording {
        audioCaptureManager.cancelRecording()
    } else {
        Task {
            do { try await audioCaptureManager.startRecording() }
            catch { viewModel.offlineToastMessage = error.localizedDescription }
        }
    }
```

Errors (permission denied, hardware unavailable) surface via `offlineToastMessage` — consistent with `SpeechManager`'s permission error handling in the `.describe` path.

**Review state**: The `isSubmitDisabled` computation includes `(captureMode == .audio && audioCaptureManager.pendingPlaybackPath != nil)`. While the user is in the review state, the capture button is visually dimmed (`.opacity(0.5)`) and non-interactive (`.disabled(true)`). The review UI's "Identify" and "Discard" buttons in `AudioRecordingView` own the transition out of this state.

---

## 9. Session Lifecycle

| Trigger | Action |
|---|---|
| Swipe from `.audio` to another mode | `cancelRecording()` if recording or `pendingPlaybackPath != nil` — clears both recording and review state |
| App backgrounds while `.audio` active | Same as above: `cancelRecording()` if recording or in review |
| 12 s countdown completes | `finishRecording()` → sets `pendingPlaybackPath` → transitions to review state |
| User taps "Identify" in review UI | `confirmAndSubmit()` → sets `audioFilePath` → `submitAudio` via `CaptureWorkspaceView.onChange` |
| User taps "Discard" in review UI | `discardPending()` → returns to idle |
| User taps capture button while recording | `cancelRecording()` |

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

## 12. `audio_spec` — Supabase Edge Function

**Files**: `supabase/functions/audio-spec/index.ts`, `db.ts`, `types.ts`, `wav.ts`

Follows the strict 3-file + helpers modular architecture defined in `docs/system-architecture/06-edge-modularization.md`.

### WAV Processing Pipeline (`wav.ts`)

Before Gemini ingestion, the raw `AVAudioEngine` recording is normalised to mono 16 kHz 16-bit PCM:

```
R2 download (staging/{userId}/uuid.wav)
    ↓ parseWavHeader()          — reads RIFF/WAVE header; supports PCM int16 (format=1) and IEEE float32 (format=3)
    ↓ extractSamplesAsFloat32() — normalises samples to −1.0…+1.0 Float32
    ↓ mixToMono()               — averages channels if stereo
    ↓ trimSilence()             — 20 ms RMS windows, −42 dBFS threshold, 2-window pad
    ↓ resampleLinear()          — 48 kHz → 16 kHz linear interpolation (~3× size reduction)
    ↓ encodeWav16()             — 44-byte header + Int16 PCM WAV
    ↓ encodeBase64()            — for Gemini inlineData
```

### Gemini Audio Call

Uses `gemini-2.5-flash` with `inlineData: { mimeType: "audio/wav", data: base64Audio }` for bioacoustic species identification. Response schema matches `AudioIdentification` (no `image_quality` field; `life_stage` defaults to `"unknown"` in the DB insert).

**Confidence threshold**: same `DIAGNOSTIC_TRIGGER = 0.95` as `identify`. Candidates are forwarded to the iOS client when `confidence_score < 0.95`.

### Response Contract

The `AudioClientPayload` type in `audio-spec/types.ts` is field-name compatible with the existing Swift `EdgeResponse` struct in `InferenceEdgeDTOs.swift` — the iOS client can decode audio-spec responses without changes.

### Post-Identification Background Tasks (mirrors `identify`)

1. `upsertGhostUserIfMissing` — ensures users FK constraint for scan insert
2. Species cache hit/miss — `fetchCachedSpecies` → taxonomy enrichment via `fetchExternalEnrichment` on miss
3. `insertScan` — upsert with `ignoreDuplicates: true` for idempotency; `image_storage_urls: []`, `blur_score: null`, `image_quality_score: null` for audio scans
4. **R2 staging cleanup** — deletes `staging/{userId}/uuid.wav` after successful scan insert (fire-and-forget)
5. Group tags Flash call — same as `identify`
6. PostHog `AudioScanCompleted` event

### IDOR Guard

`audio_r2_key` must start with `staging/{user.id}/` — verified before the R2 download. Violations are logged via `logStructuredError("audio_spec/idor_attempt")` and return 403.

### Error Status Semantics

Mirrors `identify`: Gemini API failures → 503 (transient, iOS offline queue retries); malformed JSON → 422 (permanent, tombstone after `maxUploadRetries`); IDOR/bad params → 400/403.

---

## 13. Implementation Status

| Item | Status |
|---|---|
| `audio_spec` Supabase Edge Function | **Complete** — deploy via `supabase functions deploy audio-spec` |
| `InferenceEngine.analyzeAudio` live path | **Complete** — in `InferenceEngine.swift`, mirrors `analyzeDescribe` |
| iOS audio request via `audio_base64` inline | **Complete** — `MerianNetworkClient.buildAudioRequest` / `identifyAudio` |
| `audio_spec` accepts `audio_base64` or `audio_r2_key` | **Complete** — inline base64 path in `index.ts` |
| `deleteQueuedScan` audio file cleanup | **Complete** — cleans Documents WAV on delete |
| `purgeSoftDeletedRecords` audio file cleanup | **Complete** — cleans Documents WAV on purge |
| `replayInferenceStagedScans` audio dispatch path | **Complete** — routes via `buildAudioRequest` through `dispatchInferenceDownloadTask` |
| Unit tests | **Complete** — `OfflineQueueManagerAudioTests.swift` (5 tests) |
