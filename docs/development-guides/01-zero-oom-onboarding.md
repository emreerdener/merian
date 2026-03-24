# Merian Developer Onboarding: The "Zero-OOM" Survival Guide

Welcome to the Merian core architecture. If you are used to building standard SwiftUI applications using high-level convenient APIs like `UIImage(data:)`, standard `@EnvironmentObject`, or implicit `Task { }` blocks—**stop**. 

Merian is essentially engineered like a realtime low-level camera engine wrapped in SwiftUI. We ingest massive, uncompressed 12MP RAW buffer data locally on isolated NVMe SSDs to bypass iOS thermal throttling and Memory Pressure kills (JetSam OOMs). 

This document serves as the absolute source of truth for all Swift 6 concurrency bounds and memory pipelines. **Failure to adhere to these rules mathematically guarantees a Memory Leak or a Silent iOS Watchdog Crash.**

---

## 🛑 Banned APIs & Architectural Constraints

In order to maintain strict native bounds against the 2GB iPhone memory ceiling, **you may never use the following standard Apple APIs:**

| ❌ BANNED API / PATTERN | 🚀 MERIAN APPROVED ALTERNATIVE | ⚠️ WHY IT'S FATAL |
| :--- | :--- | :--- |
| `UIImage(data:)` | `ImageDownsampler.shared.downsample(data:maxSize:)` | Native `UIImage` initialization decompresses the *entire* 12MP physical payload into raw RAM (often 50MB-100MB per image). Four frames loaded sequentially will crash the host process. |
| `@EnvironmentObject` | `AppDIContainer.shared` + `@Observable` | Massive environment objects cause entire view graphs to recompute uncontrollably ("View Graph Tearing") when state mutates dynamically. We isolate dependencies strictly utilizing iOS 17's macro. |
| SQLite `FileManager` I/O | `Task { await FileIOActor.shared }` | Synchronously deleting files directly from `ModelContext` lock instances causes the SwiftData Persistence Store to deadlock natively, skipping camera feed logic. purely use `FileIOActor`. |
| `.sheet(isPresented:)` without `@MainActor` delays | `DispatchQueue.main.async { activeSheet = ... }` | Emitting native UIKit-backed rendering modals concurrently as `AVCaptureSession` tears down locks the hardware GPU thread rendering black screens natively. |
| `PHAsset` Image Retrieval loops | `PHAssetCreationRequest` temporary URLs natively | Fetching `.imageManager` directly loads full fidelity photo-library proxies. Instead, stream data into `URL.documentsDirectory` off-thread safely. |
| Catch-All `Task { ... }` blocks | `Task.detached(priority: .userInitiated) { ... }` | Relying on standard `Task` statically inherits the `@MainActor` thread context from the View blindly blocking the user-facing hardware viewport. |

---

## 🏗️ Core Architectural Flows

### 1. Database Operations (`BackgroundDatabaseActor.swift`)
Never write queries to SwiftData from standard ViewModels natively!
All data inserts map explicitly into `@ModelActor` global bounds:
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
SwiftData records should only map pointers (`String` paths), *never* binary `Data` or `[UInt8]` boundaries.
If you need to fetch, purge, or stream Native bytes, hit the SSD explicitly via the File IO native thread:
```swift
// Wait for NVMe drive confirmation
let paths = await FileIOActor.shared.writeTemporaryImages(imageDatas: compressedDatas)
```

### 3. Queue Hydration Constraints
Background `URLSession` hooks (`application(_:handleEventsForBackgroundURLSession:...)`) are explicitly limited to 30 continuous execution seconds. 
* Do not parse data synchronously from the background queue! 
* Always yield parsing explicitly: `OfflineQueueManager.shared.enqueueCapture(...)`

## 🧠 Debugging Memory Boundaries 
If you suspect an issue:
1. Open XCode memory profiler cleanly.
2. If memory spikes instantaneously by ~130MB exactly as the shutter presses, check your local variables. You likely captured `Data` natively inside a strong class scope without deferring `.removeAll()` successfully locking the ARC natively.
3. Track Swift 6 Warnings: Enable `Strict Concurrency` globally natively in Xcode bounds to automatically generate build failures natively if crossing `@Sendable` isolated memory pools natively.
