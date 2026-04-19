# Merian Developer Onboarding: The "Zero-OOM" Survival Guide

Welcome to the Merian core architecture. If you are used to building standard SwiftUI applications with high-level APIs like `UIImage(data:)`, standard `@EnvironmentObject`, or implicit `Task { }` blocks — **stop**.

Merian is engineered like a realtime low-level camera engine wrapped in SwiftUI. We ingest massive, uncompressed 12MP RAW buffer data locally on isolated NVMe SSDs to bypass iOS thermal throttling and Memory Pressure kills (JetSam OOMs).

This document is the source of truth for all Swift 6 concurrency bounds and memory pipelines. **Failure to adhere to these rules guarantees a memory leak or a silent iOS Watchdog crash.**

---

## Banned APIs & Architectural Constraints

To maintain strict bounds against the 2GB iPhone memory ceiling, **you may never use the following standard Apple APIs:**

| BANNED API / PATTERN | MERIAN APPROVED ALTERNATIVE | WHY IT'S FATAL |
| :--- | :--- | :--- |
| `UIImage(data:)` | `ImageDownsampler.downsample(data:maxSize:)` | `UIImage` initialization decompresses the entire 12MP payload into raw RAM (often 50MB–100MB per image). Four frames loaded sequentially will crash the host process. |
| `@EnvironmentObject` | `AppDIContainer.shared` + `@Observable` | Massive environment objects cause entire view graphs to recompute uncontrollably ("View Graph Tearing") when state mutates. We isolate dependencies using iOS 17's macro. |
| SQLite `FileManager` I/O | `Task { await FileIOActor.shared }` | Synchronously deleting files from a `ModelContext` lock causes the SwiftData Persistence Store to deadlock, interrupting camera feed logic. Always use `FileIOActor`. |
| `.sheet(isPresented:)` without `@MainActor` delays | `DispatchQueue.main.async { activeSheet = ... }` | Emitting UIKit-backed modals concurrently while `AVCaptureSession` tears down locks the hardware GPU thread and produces black screens. |
| `PHAsset` Image Retrieval loops | `PHAssetCreationRequest` temporary URLs | Fetching `.imageManager` loads full-fidelity photo-library proxies. Instead, stream data into `URL.documentsDirectory` off-thread. |
| Catch-all `Task { ... }` blocks | `Task.detached(priority: .userInitiated) { ... }` | A standard `Task` inherits the `@MainActor` context from the calling View, blocking the user-facing hardware viewport. |

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
    await dbActor.saveLiveScanRecord(mappedData: data, localImagePaths: paths)
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
