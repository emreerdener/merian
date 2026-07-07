# Merian Developer Onboarding: The "Zero-OOM" Survival Guide

Welcome to the Merian core architecture. If you are used to building standard SwiftUI applications with high-level APIs like `UIImage(data:)`, standard `@EnvironmentObject`, or implicit `Task { }` blocks — **stop**.

Merian is engineered like a realtime low-level camera engine wrapped in SwiftUI. We ingest massive, uncompressed 12MP RAW buffer data locally on isolated NVMe SSDs to bypass iOS thermal throttling and Memory Pressure kills (JetSam OOMs).

This document is the source of truth for all Swift 6 concurrency bounds and memory pipelines. **Failure to adhere to these rules guarantees a memory leak or a silent iOS Watchdog crash.**

---

## Banned APIs & Architectural Constraints

To maintain strict bounds against the 2GB iPhone memory ceiling, **you may never use the following standard Apple APIs:**

| BANNED API / PATTERN | MERIAN APPROVED ALTERNATIVE | WHY IT'S FATAL |
| :--- | :--- | :--- |
| `UIImage(data:)` / `UIImage(contentsOfFile:)` on user-selected originals | `MediaPreparationActor.prepareStillImage(...)` / `preparePreviewImage(...)` for file-backed scan, refinement, and avatar paths; `ImageDownsampler.downsample(data:maxSize:)` only for already-bounded bytes | `UIImage` initialization decompresses the entire 12MP–48MP payload into raw RAM (often 50MB–300MB per image). Four frames loaded sequentially will crash the host process. |
| `NSItemProvider.loadDataRepresentation` for image imports | `loadFileRepresentation` / `loadInPlaceFileRepresentation` + file-size validation | Share extensions have tiny memory ceilings. Materializing an arbitrary HEIC/PNG/TIFF into extension RAM can terminate the extension before downsampling starts. |
| Edge `req.json()` / `response.arrayBuffer()` on media-bearing bodies | `_shared/mediaBudgets.ts` capped readers | `Content-Length` can be absent or forged by chunked transfer. Stream-count bytes first, cancel on overflow, then assemble the bounded buffer. |
| Unbounded Edge `Promise.all(...)` over user-scaled rows | `_shared/concurrency.ts` `mapWithConcurrencyLimit` | Fanout over devices, R2 objects, or DB writes can spike sockets, V8 heap, provider throttles, and Postgres load from one isolate. |
| `@EnvironmentObject` | `AppDIContainer.shared` + `@Observable` | Massive environment objects cause entire view graphs to recompute uncontrollably ("View Graph Tearing") when state mutates. We isolate dependencies using iOS 17's macro. |
| SQLite `FileManager` I/O | `Task { await FileIOActor.shared }` | Synchronously deleting files from a `ModelContext` lock causes the SwiftData Persistence Store to deadlock, interrupting camera feed logic. Always use `FileIOActor`. |
| `.sheet(isPresented:)` without `@MainActor` delays | `DispatchQueue.main.async { activeSheet = ... }` | Emitting UIKit-backed modals concurrently while `AVCaptureSession` tears down locks the hardware GPU thread and produces black screens. |
| `PHAsset` Image Retrieval loops | `PHAssetCreationRequest` temporary URLs | Fetching `.imageManager` loads full-fidelity photo-library proxies. Instead, stream data into `URL.documentsDirectory` off-thread. |
| Catch-all `Task { ... }` blocks | Structured `Task { ... }` + actor/repository-owned work; if a true detached bridge is required, route it through `DetachedWork` / `Task.detached` only for narrow `Sendable`-only bridges | Inheriting `@MainActor` accidentally blocks the viewport, while overusing detached tasks drops cancellation and isolation guarantees. |

---

## Core Architectural Flows

### 1. Database Operations (`BackgroundDatabaseActor.swift`)
Never write queries to SwiftData from standard ViewModels.
All data inserts must go through `@ModelActor` global bounds:
```swift
// WRONG: Blocks UI
modelContext.insert(record)
try modelContext.save()

// CORRECT: Dispatch to Actor
Task {
    let dbActor = BackgroundDatabaseActor(modelContainer: context.container)
    await dbActor.saveLiveScanRecord(
        mappedData: data,
        localImagePaths: paths,
        observationContextsJSON: nil,
        audioFilePaths: nil,
        mediaTimeline: timeline
    )
}
```

### 2. Disk Operations (`FileIOActor.swift`)
SwiftData records should only store pointers (`String` paths), never binary `Data` or `[UInt8]` values.
If you need to fetch, purge, or stream bytes, go through the File IO actor:
```swift
// Wait for NVMe drive confirmation
let paths = await FileIOActor.shared.writeTemporaryImages(imageDatas: compressedDatas)
```

### 3. Queue Hydration Constraints
Background `URLSession` hooks (`application(_:handleEventsForBackgroundURLSession:...)`) are limited to 30 seconds of continuous execution.
* Do not parse data synchronously from the background queue.
* Always yield parsing: `OfflineQueueManager.shared.enqueueCapture(...)`

## Debugging Memory Boundaries
If you suspect an issue:
1. Open the Xcode memory profiler.
2. If memory spikes by ~130MB exactly as the shutter fires, check your local variables. You likely captured `Data` inside a strong class scope without deferring `.removeAll()`, holding the ARC reference.
3. Enable `Strict Concurrency` globally in Xcode build settings to generate build failures when crossing `@Sendable` isolated memory pools.

## 2026-05 Hardening Addendum

- Never call `fatalError` from auth, configuration, or persistence bootstrap paths. `MerianEnvironment.load()` returns typed diagnostics, optional SDKs skip missing-key setup, Supabase endpoint construction throws, and `ModelContainer` recovery must log, quarantine, fall back to in-memory safe mode, or show startup-blocked UI.
- Camera shutter ImageIO work must run through `DetachedWork.value(category: .imagePreparation)`. `Task {}` inside a `@MainActor` view model is orchestration only; it must not synchronously downsample, crop, or encode 12MP buffers.
- File-backed still-image imports must enter through `MediaPreparationActor`.
  Gallery staging, refinement staging, and avatar crop previews use bounded
  ImageIO passes before any SwiftUI `UIImage` is created. `StagedImage.displayData`
  is a display-sized payload only, never a full original file mapping.
- Offline queued-only submissions must not call `InferenceEngine.prepareForNewScan()`. Prepare the live engine only after online live inference is confirmed, otherwise `isProcessing` can stay true with no active request.
- Queued audio must stage through R2 and replay as `audioR2ObjectKeys`; only live foreground audio may use inline `audioBase64s`, and only after byte-size preflight.
- Media-bearing Edge requests must use `readRequestJsonWithinBudget`; R2/media
  responses must use `readResponseArrayBufferWithinBudget` or
  `readStreamArrayBufferWithinBudget`. `Content-Length` is a pre-check only.
- Never build collection UI from `ScanCollection.scans` on the main thread. Use scan-side membership projections (`LocalScanRecord.collections` → `CollectionMembershipSnapshot`) so large libraries do not fault full relationship graphs into memory.
- Species observation chart overlays must use
  `SpeciesObservationStatsDatabaseActor` with filtered predicates and
  `propertiesToFetch`; do not fetch the entire biological corpus on
  `@MainActor` for local chart stats.
- Explore restore media uploads must stay file-backed with `URLSession.upload(for:fromFile:)` and bounded concurrency. Reading each image into `Data` and then assigning `httpBody` is a zero-OOM violation.
- Remote export media must pass exact-host allowlisting through `URLComponents` and `https` enforcement before any download begins. The approved host is `media.merian.app`.
- Settings-heavy SwiftUI surfaces should bind through `AppSettings`, not scattered `@AppStorage("...")` literals. The view layer should express intent (`appSettings.themeMode`, `appSettings.gridColumns`), not storage keys.
- Detached work should route through `DetachedWork`, which marks intentional executor escapes and makes raw `Task.detached` searchable and lintable.
- Regression tests must pin every zero-OOM invariant introduced by hardening work. The current suite covers non-crashing `MerianEnvironment` fallback loading, offline visual/audio submissions that never activate `InferenceEngine.isProcessing`, staged audio queue state (`.pending` for R2 upload), `MediaStagingContract` object-key/task-description/budget behavior, `MediaPreparationActor` bounded still-image preparation, inline audio byte preflight before base64 encoding, and batched biological-only lookalike cache clearing.
