# Image Pipeline

This document traces the full journey of an image from physical shutter press to on-screen render, identifying the OOM risk at each step and the mechanism that mitigates it.

---

## Capture → Disk

### 1. AVFoundation Buffer (`CameraManager`)

`CameraManager` receives raw `CMSampleBuffer` frames from the AVFoundation `captureOutput` delegate on a dedicated `DispatchQueue(label: "camera.session")`.

- **OOM risk**: Decoding a full 12–48 MP `CMSampleBuffer` without throttling instantly spikes RAM and triggers JetSam.
- **Mitigation**: An atomic `nonisolated(unsafe) private var activeInferencePaused` boolean short-circuits the entire `captureOutput` pipeline when the viewfinder AI is halted. No histogram allocation occurs for a paused session. Additionally, `defer { CVPixelBufferUnlockBaseAddress }` is unconditionally applied to prevent AVFoundation buffer leaks.

### 2. Dual-Path Downsample (`ImageDownsampler`)

Every capture produces **two independent downsampled images** from the same raw source buffer. The two paths serve different purposes and are sized accordingly.

| Path | Constant | Size | Destination |
|---|---|---|---|
| **Inference** | `MerianConfig.inferenceImageMaxSize` | 1024 px longest edge | Base64-encoded and sent to Gemini; retained in `activeLiveCaptureDatas` for background-rescue re-queuing |
| **Display** | `MerianConfig.displayImageMaxSize` | 2048 px longest edge | Written to disk by `FileIOActor`; read by the insight sheet carousel and scan library |

```swift
// Camera shutter path (Capture.swift) — same captureData source, two passes
let inferenceCGImage = ImageDownsampler.shared.downsample(
    data: captureData, maxSize: MerianConfig.inferenceImageMaxSize)  // → Gemini

let displayCGImage = ImageDownsampler.shared.downsample(
    data: captureData, maxSize: MerianConfig.displayImageMaxSize)    // → disk / insight sheet

// Gallery picker path (CameraViewModel) — same dual pattern from a file URL
let inferenceCGImage = ImageDownsampler.shared.downsample(
    url: validUrl, maxSize: MerianConfig.inferenceImageMaxSize)
let displayCGImage = ImageDownsampler.shared.downsample(
    url: validUrl, maxSize: MerianConfig.displayImageMaxSize)
```

The two resulting `Data` values are staged separately in `CameraViewModel`:
- `activeScannedDatas` — 1024 px inference payloads
- `activeDisplayDatas` — 2048 px display payloads

`Analysis.submitActiveScan()` passes both arrays to `InferenceEngine.analyze(imageDatas:displayDatas:)`. Inside the engine, `imageDatas` is base64-encoded for the AI call; `displayDatas` is forwarded to `InferenceProcessingActor.parseAndSave(displayDatas:)` and written to disk via `FileIOActor.writeTemporaryImages`. The AI never receives the larger payload.

**Why 1024 px for inference?** Sufficient for Gemini species identification. Keeps the base64 payload at ~100–250 KB, reducing token cost and upload latency by ~15× versus the previous 4000 px ceiling.

**Why 2048 px for display?** Covers the full-width pixel density of all current iOS devices without upscaling (iPhone Pro Max at 3× = 1290 px native; iPad Pro at 2× = 2048 px native). Eliminates the JPEG blocking artifacts that were visible when the insight sheet and scan library rendered the same 1024 px image that was sent to the AI. Stored files average ~300–700 KB vs ~100–250 KB at inference quality.

**Why two `CGImageSourceCreateThumbnailAtIndex` calls instead of one?** Both operate on the compressed source bytes (JPEG / HEIC) without ever expanding the full 12 MP raster. The cost is two lightweight thumbnail decodes from the same buffer — negligible compared to the AVFoundation capture itself.

**Crop export path**: `ImageCropProcessor` uses `maxSize: 768` (tighter, crop-optimised for crop-view thumbnails). This path is unaffected by the inference/display split.

**Implementation**: Uses `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways: true` and `kCGImageSourceShouldCache: false`. This instructs ImageIO to decode only a scaled thumbnail directly from the compressed source, never loading the full pixel buffer into RAM.

**`autoreleasepool`**: Both display and inference downsample calls — and the `UIImage.jpegData` encoding that follows each — are wrapped in `autoreleasepool` so intermediate CoreGraphics allocations are released immediately.

**`nonisolated` methods**: Both `downsample(url:maxSize:)` and `downsample(data:maxSize:)` are declared `nonisolated`, making them synchronous and callable without `await`. This allows concurrent grid loads to decode in parallel on the cooperative thread pool. The `autoreleasepool` inside each call remains safe because CoreGraphics is thread-safe at the frame level.

**Full-resolution preservation**: The unmodified 12 MP sensor buffer is saved to the user's Camera Roll by `PhotoLibraryManager` *before* any downsampling occurs, so no image quality is permanently lost regardless of which path is used.

### 3. Write to Documents Directory (`FileIOActor`)

`FileIOActor.shared` (`Core/Data/Database/FileIOActor.swift`) is a Swift `actor` that handles all disk I/O off both the Main Actor and the SwiftData actor thread.

```swift
// Writes [Data] → [filename] in URL.documentsDirectory atomically
FileIOActor.shared.writeTemporaryImages(imageDatas: [Data]) -> [String]

// Deletes by filename (skips http:// paths — those are cloud-owned)
FileIOActor.shared.deleteImages(at: [String])
```

- **OOM risk**: Writing large arrays of image `Data` on the main thread blocks the UI and spikes memory.
- **Mitigation**: By running on its own isolated actor, `FileIOActor` guarantees that disk writes never contend with SwiftData saves (`BackgroundDatabaseActor`) or UI rendering.
- **Path format**: Only the filename (e.g. `"uuid_scan.jpg"`) is stored in SwiftData — never the full absolute sandbox path. This prevents broken image renders caused by iOS randomizing container UUIDs on reboots and app updates.

---

## Disk → Display

### 4. Load Request (`LocalImageLoader`)

`LocalImageLoader.shared` (`Core/Data/Images/LocalImageLoader.swift`) is a Swift `actor` that serves as the single entry point for all image loads — both local and remote.

```swift
LocalImageLoader.shared.loadImage(
    fromPath: record.localImagePath,   // filename or http:// URL
    fallbackUrl: record.referenceImageUrl,
    maxDimension: 1024
)
```

**Resolution order:**

| Step | Check | Action |
|---|---|---|
| 1 | RAM cache hit (`ImageCache`) | Return immediately |
| 2 | Duplicate in-flight request | Coalesce — await the existing `Task` |
| 3 | `imagePath` starts with `http://` | Download via `URLSession`, downsample, cache |
| 4 | `imagePath` is a local filename | Resolve to `documentsDirectory`, downsample, cache |
| 5 | Local file missing | Try `fallbackUrl` (supports comma-separated list) |

- **Thundering herd prevention**: The `activeTasks: [String: Task<UIImage?, Never>]` dictionary ensures that 50 cells requesting the same image key in a single scroll frame all await one download, not 50 parallel downloads.
- **OOM risk during scroll**: Loading full-resolution images for every visible grid cell would exhaust RAM on large libraries.
- **Adaptive `maxDimension`**: `ScansGrid` computes the actual cell pixel size from screen width, column count, and display scale — `Int((screenWidth - spacing) / columns * scale)` — and passes it to `ScanThumbnail` as `maxDimension`. On a 3-column iPhone 15 at 3× scale this is roughly 390px, versus the previous hardcoded 1024px. `LocalImageLoader` threads `maxDimension` through to both local and remote load paths. Remote fallback downloads previously capped at a hardcoded 500px now use the same caller-provided value.
- **`maxDimension` default**: `600` in `ScanThumbnail` (used when a caller omits the parameter, e.g. single-image detail views).

### 5. RAM Cache (`ImageCache`)

`ImageCache.shared` (`Core/Data/Images/ImageCache.swift`) wraps `NSCache<NSString, UIImage>`.

```swift
cache.countLimit = 100                    // hard entry cap
cache.totalCostLimit = 30 * 1024 * 1024  // 30 MB byte cap
```

Every `set(_:forKey:)` call computes the pixel-area cost (`width × height × 4 bytes`) and passes it to `setObject(_:forKey:cost:)`. This gives `NSCache` an accurate memory footprint so it can evict the largest images first rather than treating a 4K thumbnail the same as a 64×64 icon.

- **Automatic eviction**: `NSCache` evicts entries under system memory pressure without any manual intervention. With `totalCostLimit` set, eviction is triggered by *actual byte usage* rather than just entry count.
- **No strong references**: Images in `NSCache` do not prevent deallocation, so they are released when iOS signals a memory warning.

---

## Historical / Remote Images (Rehydration)

When a user reinstalls the app or signs in on a new device, `LocalScanRecord.localImagePath` contains a Cloudflare R2 URL rather than a local filename. `LocalImageLoader` handles this transparently — it detects the `http://` prefix and routes through `fetchNetworkFallback`, which downloads to a temp file, downsamples to the caller-provided `maxDimension` (no longer hardcoded), caches in RAM, and deletes the temp file.

This means the grid renders correctly with cloud images immediately, and any locally archived scans (via `ArchiveManager`) will be served from disk on subsequent loads once they have been rescued to `documentsDirectory`.

---

## Upload Path (Offline Queue)

For captures that go into the offline queue, images are written to disk by `FileIOActor.writeTemporaryImages` before the `OfflineQueuedScan` SwiftData record is inserted. During upload, `OfflineQueueManager` copies each image to a temp file in `URL.cachesDirectory` (naming convention: `<scanId>_<index>_temp_upload.jpg`) and hands the path to `URLSession.uploadTask(with:fromFile:)`. The OS background session owns the byte transmission from that point. On upload completion, the temp staging file is deleted unconditionally regardless of success or failure.

**Offline queue image quality**: The offline queue stores inference-quality images only (1024 px). When an offline scan is reprocessed, `InferenceProcessingActor.parseAndSave` receives `displayDatas = []` and falls back to writing the inference-quality files to disk. This is a deliberate trade-off: the full-resolution photo is already saved to Camera Roll at capture time, so 1024 px on-disk files are an acceptable fallback for the subset of scans that passed through the offline queue. Live captures and gallery picks both produce display-quality on-disk files.

---

## Component Responsibilities Summary

| Component | Location | Responsibility |
|---|---|---|
| `ImageDownsampler` | `Core/Utilities/` | CGImageSource thumbnail decoding; `nonisolated` methods safe for concurrent calls; autoreleasepool |
| `FileIOActor` | `Core/Data/Database/` | Disk reads/writes; isolated from Main and SwiftData actors |
| `LocalImageLoader` | `Core/Data/Images/` | Load orchestration; RAM cache hits; request coalescing; local/remote routing |
| `ImageCache` | `Core/Data/Images/` | NSCache-backed RAM store; auto-evicts under memory pressure; 100-entry cap |
| `ArchiveManager` | `Core/Data/Images/` | Streams aging Free-tier images from R2 to disk via `URLSession.download(from:)`; avoids `.data(from:)` OOM |
