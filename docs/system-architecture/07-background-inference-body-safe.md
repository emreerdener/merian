# Background Inference: Body-Safe Pattern (TODO)

## What This Document Is

A reference design for making all inference POST requests fully safe for background
`URLSession` transfer. The current implementation works in practice but relies on
undocumented behaviour. This document captures the correct two-phase approach so it
can be implemented when warranted.

---

## Current Architecture (works in practice, not "by the book")

Every inference path — image identify, describe, and audio — dispatches inference via
a background `URLSessionDownloadTask` with the full JSON payload in `httpBody`:

```swift
// OfflineQueueManager+URLSession.swift — dispatchInferenceDownloadTask
let task = backgroundSession.downloadTask(with: request)   // request.httpBody = full JSON
task.taskDescription = "inference_\(scanId)"
task.resume()
```

For audio specifically, `httpBody` contains the base64-encoded WAV (~400 KB for a
12-second clip at 48 kHz, ~170 KB after 16 kHz resampling on the server).

### Why it works today

Apple serialises the entire `URLRequest` — including `httpBody` — into the background
session store at `task.resume()`. Because `dispatchInferenceDownloadTask` is only ever
called from active-phase foreground transitions (`handleActivePhase` →
`replayInferenceForUploadedScans`), the app is always in the foreground when `resume()`
is called. There is no suspension boundary between task creation and `resume()`, so the
body is always durably owned by the OS before the app can be suspended.

### Why it is not "by the book"

Apple's URL Session Programming Guide states that for background sessions you should
provide the request body as a **file on disk** using `uploadTask(with:fromFile:)` rather
than setting `request.httpBody`. The documented guarantee for background download tasks
is only that the `URLRequest` is serialised at `resume()` time; there is no explicit
guarantee that large `httpBody` payloads survive an OS-level task restart (which can
happen if the device reboots while the task is in-flight — unlikely in practice but
theoretically possible).

The concern is not about the common path. It is about this edge case:

1. User captures audio, is online, `dispatchInferenceDownloadTask` fires, `resume()` is
   called — task is in-flight.
2. Device reboots (crash, power-off) before the edge function responds.
3. iOS restarts the background session and replays in-flight tasks.
4. When the OS replays the task it reads the serialised `URLRequest` from disk. If the
   `httpBody` was not durably persisted (implementation-defined for large bodies), the
   replayed request arrives at the edge function with an empty body.
5. Edge function returns HTTP 400 "Missing audio_base64".
6. `handleInferenceTaskNetworkFailure` → `handleInferenceRetry` → scan reset to
   `.staged` → next active-phase sync retries correctly.

Step 6 means **no data is lost** — the retry cycle recovers. The consequence is one
wasted retry and a delayed result, not a silent failure. This is why the current
approach is acceptable for the current scale.

---

## Fully Correct Solution: Two-Phase R2 Upload

The canonical fix is to stop embedding large bodies in background `downloadTask`
requests entirely. Instead, use the same pattern already in place for images:

```
Phase 1: upload body → R2 staging        (uploadTask with fromFile: — fully safe)
Phase 2: call inference with R2 key      (downloadTask with tiny JSON body — safe)
```

Image identify already works this way. Audio is the only path that currently bypasses
R2. The reference implementation below shows how to bring audio into the same pattern.

### iOS changes required

#### 1. `OfflineQueueManager+AudioQueue.swift` — enqueueAudio

Change the scan state from `.staged` to `.pending`, mirroring `enqueueCapture`:

```swift
// TODO: Replace .staged with .pending and set scanState to trigger R2 upload
let scan = OfflineQueuedScan(
    id: resolvedScanId,
    // ...
    scanState: .pending,          // was .staged — now goes through upload phase
    audioFilePath: audioFileName
)
```

#### 2. `OfflineQueueManager+Sync.swift` — syncPendingScans

Extend the upload path to handle audio scans. Currently it only uploads image WebP
files. Audio scans have `localImagePaths.isEmpty && audioFilePath != nil` — this
condition routes them to a new audio upload task:

```swift
// TODO: Add audio upload branch in syncPendingScans
private func uploadAudioScan(_ scan: OfflineQueuedScan) async throws {
    guard let audioPath = scan.audioFilePath else { return }
    let audioURL = URL.documentsDirectory.appendingPathComponent(audioPath)

    // Generate a pre-signed R2 PUT URL for the audio file.
    // Reuse the existing generateUploadURLs endpoint or add audio support there.
    let r2Key = "staging/\(userId)/\(scan.id)_\(audioPath)"
    let putURL = try await MerianNetworkClient.shared.generateAudioUploadURL(r2Key: r2Key)

    // Build the upload request — body comes from file, fully safe for background session.
    var uploadRequest = URLRequest(url: putURL)
    uploadRequest.httpMethod = "PUT"
    uploadRequest.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
    // NO httpBody — body is provided as fromFile: below.

    let task = backgroundSession.uploadTask(with: uploadRequest, fromFile: audioURL)
    task.taskDescription = "\(scan.id)_audio"   // matches existing naming convention
    task.resume()
}
```

#### 3. `OfflineQueueManager+URLSession.swift` — processUploadCompletion

Add an audio-upload completion branch before the existing `guard urlPath.contains("staging/")` check:

```swift
// TODO: Route audio upload completion to inference dispatch
// Detect audio upload tasks by their taskDescription suffix "_audio"
if taskDesc.hasSuffix("_audio") {
    // Audio file is now in R2. Transition scan to .staged so
    // dispatchInferenceDownloadTask can pick it up with audio_r2_key.
    let r2Key = "staging/\(userId)/\(scanId)_\(audioFileName)"
    let inferenceActor = resolvedInferenceDbActor(container: extracted.container)
    await inferenceActor.markScanAsStaged(scanId: scanId, r2Keys: [r2Key])
    guard await inferenceActor.tryClaimForInference(scanId: scanId) else { return }

    let extractedWithKey = ExtractedScanData(
        telemetry: extracted.telemetry,
        localImagePaths: [],
        r2Keys: [r2Key],
        container: extracted.container,
        originalTimestamp: extracted.originalTimestamp,
        description: nil,
        observationContextJSON: nil,
        audioFilePath: audioFileName   // kept so dispatchInferenceDownloadTask routes correctly
    )
    await dispatchInferenceDownloadTask(scanId: scanId, extracted: extractedWithKey)
    return
}
```

#### 4. `OfflineQueueManager+URLSession.swift` — dispatchInferenceDownloadTask audio branch

Replace the inline base64 path with the R2 key path:

```swift
// TODO: Replace buildAudioRequest (base64 inline) with buildAudioR2Request (R2 key)
if let audioPath = extracted.audioFilePath {
    // r2Keys[0] is the R2 staging key written in step 3 above.
    // The inference request body is now tiny (~500 bytes) — just the key + telemetry.
    // A 500-byte httpBody on a background downloadTask is well within the safe range.
    guard let r2Key = extracted.r2Keys.first else {
        await handleInferenceRetry(scanId: scanId)
        return
    }
    request = try await MerianNetworkClient.shared.buildAudioR2Request(
        r2Key: r2Key,
        telemetry: finalTelemetry,
        clientScanId: scanId
    )
}
```

#### 5. `MerianNetworkClient.swift` — buildAudioR2Request

```swift
// TODO: Add this alongside buildAudioRequest
func buildAudioR2Request(
    r2Key: String,
    telemetry: CaptureTelemetry,
    clientScanId: String
) async throws -> URLRequest {
    // Body is identical to buildAudioRequest but uses audio_r2_key instead of audio_base64.
    // Body size is ~500 bytes — safe for httpBody on background download tasks.
    let payload: [String: Any?] = [
        "user_id": userId,
        "audio_r2_key": r2Key,          // ← R2 key, not base64
        "client_scan_id": clientScanId,
        // ... telemetry fields unchanged
    ]
    // Build URLRequest identically to buildAudioRequest but with 90s timeout
    // and the R2 key payload.
}
```

#### 6. `InferenceEngine.swift` — analyzeAudio live path

The live path (`submitAudio` → `analyzeAudio`) runs on a foreground `URLSession`
(via `performAuthenticatedRequest`), not the background session, so httpBody is
always safe there. However, to keep the live and replay paths consistent, the live
path can also be changed to upload to R2 first:

```swift
// TODO (optional): Change analyzeAudio to upload WAV to R2 then call inference
// with audio_r2_key. Currently uses base64 inline (safe on foreground session).
// The main benefit of switching is a single code path for both live and replay.
```

### Edge function changes required

The `/audio-spec` edge function already supports `audio_r2_key` — no changes needed.
The R2 cleanup in the background task already runs when `audio_r2_key` is set.

### What stays the same

- `deleteQueuedScan` audio file cleanup — unchanged, WAV still lives in Documents
  until inference succeeds
- `purgeSoftDeletedRecords` audio cleanup — unchanged
- `replayInferenceStagedScans` — unchanged, audio scans with R2 keys are already
  routed correctly via `dispatchInferenceDownloadTask`
- All unit tests in `OfflineQueueManagerAudioTests` — the observable behaviour
  (`.staged` record, file in Documents, replay dispatch) is unchanged; only the
  internal path to `.staged` changes (via R2 upload rather than direct enqueue)

---

## When to implement

| Trigger | Action |
|---|---|
| Audio WAV body > 1 MB (e.g., longer recordings, higher quality) | Implement two-phase R2 |
| Apple explicitly deprecates httpBody on background download tasks | Implement two-phase R2 |
| Inference retry rate > 1% due to empty-body 400 errors (observable via PostHog `audio_spec/wav_parse_failed`) | Investigate and implement if confirmed |
| Current approach works cleanly at scale | Defer indefinitely |

The PostHog event to watch is `audio_spec/wav_parse_failed` with
`error: "WAV: file too small"` — that is the signature of an empty-body replay.
If that event appears, this plan is the fix.

---

## Summary of changes from current to correct

| Component | Current | Correct |
|---|---|---|
| Audio scan enters queue as | `.staged` (skips upload) | `.pending` (goes through R2 upload) |
| Inference body | base64 WAV in `httpBody` (~170 KB) | `audio_r2_key` in `httpBody` (~500 B) |
| Upload task type | n/a | `uploadTask(with:fromFile:)` |
| Inference task type | `downloadTask(with:)` | `downloadTask(with:)` (unchanged) |
| R2 cleanup | n/a | background task in edge function (already implemented) |
| Live path | `identifyAudio` → base64 inline | unchanged (foreground session, safe) |
