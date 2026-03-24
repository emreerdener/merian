# Image Pipeline

This document traces the full journey of an image from physical shutter press to on-screen render, identifying the OOM risk at each step and the mechanism that mitigates it.

---

## Capture → Disk

### 1. AVFoundation Buffer (`CameraManager`)

`CameraManager` receives raw `CMSampleBuffer` frames from the AVFoundation `captureOutput` delegate on a dedicated `DispatchQueue(label: "camera.session")`.

- **OOM risk**: Decoding a full 12–48 MP `CMSampleBuffer` without throttling instantly spikes RAM and triggers JetSam.
- **Mitigation**: An atomic `nonisolated(unsafe) private var activeInferencePaused` boolean short-circuits the entire `captureOutput` pipeline when the viewfinder AI is halted. No histogram allocation occurs for a paused session. Additionally, `defer { CVPixelBufferUnlockBaseAddress }` is unconditionally applied to prevent AVFoundation buffer leaks.

### 2. Downsample Before Encoding (`ImageDownsampler`)

Before any image bytes are written to disk or sent to the network, raw `CMSampleBuffer` data is piped through `ImageDownsampler.shared` (`Core/Utilities/ImageDownsampler.swift`).

```swift
// Disk-bound path (from a file URL)
ImageDownsampler.shared.downsample(url: fileURL, maxSize: 1024)

// Memory-bound path (from raw Data)
ImageDownsampler.shared.downsample(data: rawData, maxSize: 1024)
```

- **Implementation**: Uses `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways: true` and `kCGImageSourceShouldCache: false`. This instructs ImageIO to decode only a scaled thumbnail directly from the compressed source, never loading the full pixel buffer into RAM.
- **`autoreleasepool`**: Each downsample call wraps its work in an `autoreleasepool` so intermediate CoreGraphics allocations are released immediately rather than accumulating until the next runloop drain.
- **Actor isolation**: `ImageDownsampler` is a Swift `actor`, so concurrent downsample calls are serialized. This prevents CPU starvation from multiple parallel full-resolution decodings.

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
- **Mitigation**: `maxDimension` defaults to `1024` for the scan grid and is reduced to `500` for remote fallback thumbnails. All loads go through `ImageDownsampler` before being stored in the cache.

### 5. RAM Cache (`ImageCache`)

`ImageCache.shared` (`Core/Data/Images/ImageCache.swift`) wraps `NSCache<NSString, UIImage>`.

```swift
// Capped at 100 entries (~15 MB estimate)
cache.countLimit = 100
```

- **Automatic eviction**: `NSCache` evicts entries under system memory pressure without any manual intervention.
- **No strong references**: Images in `NSCache` do not prevent deallocation, so they are released when iOS signals a memory warning.

---

## Historical / Remote Images (Rehydration)

When a user reinstalls the app or signs in on a new device, `LocalScanRecord.localImagePath` contains a Cloudflare R2 URL rather than a local filename. `LocalImageLoader` handles this transparently — it detects the `http://` prefix and routes through `fetchNetworkFallback`, which downloads to a temp file, downsamples to 500px, caches in RAM, and deletes the temp file.

This means the grid renders correctly with cloud images immediately, and any locally archived scans (via `ArchiveManager`) will be served from disk on subsequent loads once they have been rescued to `documentsDirectory`.

---

## Upload Path (Offline Queue)

For captures that go into the offline queue, images are written to disk by `FileIOActor.writeTemporaryImages` before the `OfflineQueuedScan` SwiftData record is inserted. During upload, `OfflineQueueManager` copies each image to a temp file in `URL.cachesDirectory` (naming convention: `<scanId>_<index>_temp_upload.jpg`) and hands the path to `URLSession.uploadTask(with:fromFile:)`. The OS background session owns the byte transmission from that point. On upload completion, the temp staging file is deleted unconditionally regardless of success or failure.

---

## Component Responsibilities Summary

| Component | Location | Responsibility |
|---|---|---|
| `ImageDownsampler` | `Core/Utilities/` | CGImageSource thumbnail decoding; actor-serialized; autoreleasepool |
| `FileIOActor` | `Core/Data/Database/` | Disk reads/writes; isolated from Main and SwiftData actors |
| `LocalImageLoader` | `Core/Data/Images/` | Load orchestration; RAM cache hits; request coalescing; local/remote routing |
| `ImageCache` | `Core/Data/Images/` | NSCache-backed RAM store; auto-evicts under memory pressure; 100-entry cap |
| `ArchiveManager` | `Core/Data/Images/` | Streams aging Free-tier images from R2 to disk via `URLSession.download(from:)`; avoids `.data(from:)` OOM |
