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
| **Inference** | `MerianConfig.inferenceImageMaxSize(isProActive:)` | **768 px** (Flash/free) or **1024 px** (Pro) longest edge | Base64-encoded and sent to Gemini; discarded after encoding (scan durability is owned by the offline queue) |
| **Display** | `MerianConfig.displayImageMaxSize` | 2048 px longest edge | Written to disk by `FileIOActor`; read by the insight sheet carousel and scan library |

```swift
// Camera shutter path (Capture.swift) — same captureData source, two passes
let inferenceCGImage = ImageDownsampler.shared.downsample(
    data: captureData,
    maxSize: MerianConfig.inferenceImageMaxSize(isProActive: diContainer.revenueCatManager.isProActive))  // → Gemini

let displayCGImage = ImageDownsampler.shared.downsample(
    data: captureData, maxSize: MerianConfig.displayImageMaxSize)    // → disk / insight sheet

// Gallery picker path (CameraViewModel) — same dual pattern from a file URL
let inferenceCGImage = ImageDownsampler.shared.downsample(
    url: validUrl,
    maxSize: MerianConfig.inferenceImageMaxSize(isProActive: self.diContainer.revenueCatManager.isProActive))
let displayCGImage = ImageDownsampler.shared.downsample(
    url: validUrl, maxSize: MerianConfig.displayImageMaxSize)
```

After downsampling, a **composing-zone-aware square crop** is applied to both payloads before WebP encoding. The crop geometry is calculated from the on-screen UI layout: `CameraRootView` measures the vertical center of the composing zone (the open area between the mode toggle at the top and the capture button row at the bottom) using the existing full-screen `GeometryReader` and stores it as `CameraViewModel.composingZoneVerticalCenter` (a fraction of screen height, e.g. ~0.42 on iPhone 15 Pro). `ImageCropProcessor.squareCrop(_:verticalCenterFraction:)` then crops each downsampled `CGImage` to the largest centered square, biasing the crop center to that fraction rather than 0.5 (geometric center). This aligns what Gemini analyzes with where the user actually framed their subject, rather than the dead center of the sensor image — a meaningful correction on tall-screen iPhones where the bottom chrome (shutter row + tab bar) occupies significantly more vertical space than the top chrome (mode toggle).

Three staging buffers are populated in `CameraViewModel` after each capture or gallery pick:
- `activeScannedDatas` — tier-conditional inference payloads: 768 px (Flash/free) or 1024 px (Pro), square-cropped WebP `Data`
- `activeDisplayDatas` — 2048 px display payloads (square-cropped WebP `Data`, same geometry)
- `activeScanImages` — in-memory `UIImage` thumbnails for the Active Scan Toolbar, populated directly from the already-decoded `CGImage` (`UIImage(cgImage:)`) rather than by re-decoding the WebP payload

Using the `CGImage` directly for `activeScanImages` eliminates a WebP round-trip decode step (encode to `Data` → decode back to `UIImage`). The `activeScanImages.count` change is what the `onChange(of: activeScanImages.count)` observer in `CameraRootView` watches to auto-trigger `submitActiveScan`.

`Analysis.submitActiveScan()` first calls `enqueueCapture` synchronously — before any `async` boundary — writing images to disk and dispatching the background URLSession upload while the app is in the foreground (see [Offline Sync Pipeline → Scan Submission & Immediate Durability](../backend-and-data/01-offline-sync-pipeline.md)). It then passes both `Data` arrays to `InferenceEngine.analyze(imageDatas:displayDatas:)`. Inside the engine, `imageDatas` is base64-encoded for the AI call and discarded after encoding — there is no `activeLiveCaptureDatas` buffer; durability is fully owned by the offline queue. `displayDatas` is retained in `activeDisplayDatas` to feed the insight sheet's live carousel with 2048 px display images, while simultaneously being forwarded to `InferenceProcessingActor.parseAndSave(displayDatas:)` and written to disk via `FileIOActor.writeTemporaryImages`. The AI never receives the larger payload.

**Empty-payload guard (both paths)**: Both the camera shutter path (`Capture.swift`) and the gallery picker path (`CameraViewModel.handlePhotoPickerSelection`) check `guard !finalSafeData.isEmpty` before appending to `activeScannedDatas`. If WebP encoding fails for any reason (e.g., low-memory `CGImageDestinationCreateWithData` failure), the item is skipped entirely rather than appending `Data()`. Sending an empty base64 string (`Data().base64EncodedString() == ""`) causes Gemini to reject the request with an opaque AI processing error; the guard prevents this at the source.

`InferenceEngine.analyze` adds a second-layer filter: after `encodeBase64`, any empty strings are removed from `base64Strings`. If all strings are empty after filtering, the scan is refunded immediately without a network call. The Edge Function (`identify/index.ts`) applies a third-layer check: each element of `imageBase64s` is validated non-empty before being forwarded to Gemini, returning a clear `400 Bad Request` instead of an opaque AI error.

**Cancel handler**: `ActiveScanToolbar`'s cancel action clears all four staging buffers: `activeScanImages`, `activeScannedDatas`, `activeOriginals`, and `activeDisplayDatas` (both in `CameraViewModel` and `InferenceEngine`). All buffers must be cleared together to prevent stale payload mismatches on the next aborted session.

**Why tier-conditional inference resolution (768 px / 1024 px)?** Gemini Vision tokenizes images by tiling them into 768×768 blocks: a 768 px square image occupies one tile (~258 input tokens), while a 1024 px square image occupies four tiles (~1032 input tokens). Free/Flash tier uses 768 px — a ~75% vision-token reduction with negligible accuracy impact for common-species macro-feature identification (bark texture, wing pattern, leaf shape). Pro tier uses 1024 px to preserve the fine morphological detail (feather barbs, gill spacing, lichen areolae) that subspecies and cultivar discrimination requires. Both payloads are well below the 5 MB guard (~100–250 KB base64 for 768 px; ~200–500 KB for 1024 px). `MerianConfig.inferenceImageMaxSize(isProActive:)` is the single source of truth — `diContainer.revenueCatManager.isProActive` is evaluated at the capture boundary before encoding in both the camera shutter path (`Capture.swift`) and the gallery picker path (`CameraViewModel.swift`).

**Why 2048 px for display?** Covers the full-width pixel density of all current iOS devices without upscaling (iPhone Pro Max at 3× = 1290 px native; iPad Pro at 2× = 2048 px native). Stored as WebP, display-quality files are free from the blocking artifacts associated with lossy JPEG compression at lower resolutions. Files average ~300–700 KB vs ~100–250 KB at inference quality.

**Why two `CGImageSourceCreateThumbnailAtIndex` calls instead of one?** Both operate on the compressed source bytes (JPEG / HEIC) without ever expanding the full 12 MP raster. The cost is two lightweight thumbnail decodes from the same buffer — negligible compared to the AVFoundation capture itself.

**Manual crop export path**: `ImageCropProcessor.generateCrop(image:displaySize:scale:currentScale:offset:currentOffset:maxPixelSize:)` handles the manual crop tool (`ImageCropperView`). The `maxPixelSize` parameter defaults to `1024`. Tier-appropriate sizing is preserved automatically: the image passed into `ImageCropperView` is sourced from `activeOriginals[index].image`, which was already downsampled to the tier-correct size (768 px or 1024 px) during capture or gallery pick. Because `kCGImageDestinationImageMaxPixelSize` is a *maximum cap* — never an upscale target — a free-tier 768 px source image passes through the 1024 px cap unchanged. No explicit tier lookup is needed at the crop boundary. Compression quality uses `MerianConfig.imageCompressionQuality` throughout (previously hardcoded at 0.7, now consistent with the capture path).

When the user confirms a manual crop, `CropSheetModifier` updates both the inference and display payloads to keep them in sync:

1. **Inference payload** (`activeScannedDatas[i]`): `generateCrop` is called on the already-tier-sized inference source. The 1024 px cap is harmless for 768 px free-tier inputs — they are not upscaled.
2. **Display payload** (`activeDisplayDatas[i]`): `generateCrop` is called again on the 2048 px WebP source (decoded off the main thread) with `maxPixelSize: nil` (no cap). The same `scale`, `offset`, and `displaySize` parameters are passed, so the crop geometry is pixel-accurately equivalent. The result (~1536 px at 1× zoom from a 2048 px source) replaces the original auto-cropped 2048 px file.

Without this sync, the scan library would show the original auto-crop while Gemini analyzed the user's manually-adjusted crop — a visual mismatch in multi-capture mode.

**Implementation**: Uses `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceCreateThumbnailFromImageAlways: true` and `kCGImageSourceShouldCache: false`. This instructs ImageIO to decode only a scaled thumbnail directly from the compressed source, never loading the full pixel buffer into RAM.

**Image encoding (WebP with JPEG fallback)**: After downsampling, both the inference and display payloads are encoded as lossy WebP via `CGImageDestinationCreateWithData` with `UTType.webP` and `kCGImageDestinationLossyCompressionQuality` set to `MerianConfig.imageCompressionQuality`. If `CGImageDestinationCreateWithData` returns nil for WebP (e.g., the iOS Simulator's host-macOS ImageIO stack does not support WebP writing on all platforms), the encoding automatically falls back to JPEG using the same quality setting. The actual format used is detected from the first image's magic bytes (`FF D8 FF` → `"image/jpeg"`, otherwise `"image/webp"`) in `InferenceEngine.analyze` and forwarded to the Edge Function's `mimeType` field so Gemini receives the correct MIME label. The `CGImageDestination` API writes directly from the `CGImage` without an intermediate `UIImage`, reducing peak allocation by one full decoded-pixel buffer per encode. The toolbar thumbnail (`activeScanImages`) is separately created via `UIImage(cgImage:)` — a zero-copy reference wrap over the already-decoded `CGImage` — rather than by re-decoding the encoded bytes.

**`autoreleasepool`**: Both display and inference downsample calls — and the `CGImageDestination` WebP encoding that follows each — are wrapped in `autoreleasepool` so intermediate CoreGraphics allocations are released immediately. Furthermore, all standalone `UIImage(data:)` inflations have been officially deprecated across the codebase in favor of bounds-checked `ImageDownsampler` extractions to prevent unbounded 48 MP uncompressed byte payloads from instantly destroying active JetSam RAM limits.

**Alpha channel stripping**: Camera-captured frames decoded via `CGImageSourceCreateThumbnailAtIndex` inherit the `AlphaPremulLast` pixel format from the sensor buffer, even when the image is fully opaque. JPEG and WebP encoders emit an "is trying to save an opaque image with 'AlphaPremulLast'" warning when they encounter this format, and some encoding paths silently degrade quality. `ImageDownsampler` calls a private `stripAlpha(from:)` method on the downsampled `CGImage` before encoding. The method composites the image into a new `CGContext` with `CGImageAlphaInfo.noneSkipLast`, producing an RGB-only `CGImage` without any library dependency. The compositing context is created at the image's native dimensions, so no extra scaling occurs. Only images that actually carry an alpha channel go through the compositing path — images already declared `.none`, `.noneSkipLast`, or `.noneSkipFirst` are returned unchanged.

**`imageCompressionQuality` (0.85)**: Raised from 0.80 to preserve fine morphological detail (feather barbs, insect wing venation, leaf margins) that influences AI identification accuracy. File size increase is ~10–15%, well within the 5 MB payload limit. All WebP encoding paths use `MerianConfig.imageCompressionQuality` as a single source of truth — inference payload, display payload, and manual crop tool all apply the same quality setting.

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
- **Path format**: Only the filename (e.g. `"uuid_scan.webp"`) is stored in SwiftData — never the full absolute sandbox path. This prevents broken image renders caused by iOS randomizing container UUIDs on reboots and app updates.

---

## Disk → Display

### 4. Load Request (`LocalImageLoader`)

`LocalImageLoader.shared` (`Core/Data/Images/LocalImageLoader.swift`) is a Swift `actor` that serves as the single entry point for all image loads — both local and remote.

```swift
// Scan library thumbnail (ScanThumbnail) — small decode for grid cells
LocalImageLoader.shared.loadImage(
    fromPath: record.localImagePath,
    fallbackUrl: record.referenceImageUrl,
    maxDimension: 600   // default; ScansGrid passes a computed cell-pixel value
)

// Insight sheet carousel (AsyncLocalImageView) — full display-quality decode
LocalImageLoader.shared.loadImage(
    fromPath: record.localImagePath,
    fallbackUrl: record.referenceImageUrl,
    maxDimension: Int(MerianConfig.displayImageMaxSize)  // 2048
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

**Dynamic GBIF Hydration**
When a species is scanned for the first time globally (Cache Miss), the Edge function returns immediately to maintain low latency, leaving `reference_image_url` empty. The iOS client (`InferenceEngine`) makes a direct follow-up call to the `api.gbif.org/v1/occurrence/search` API the moment it receives the `gbif_taxon_key` from the secondary `enrich-scan` endpoint. This natively hydrates the comma-separated `fallbackUrl` with 3-4 high-quality field observations from networks like iNaturalist. On Cache Hits, these URLs are already stored in the DB and returned instantly.

- **Thundering herd prevention**: The `activeTasks: [String: Task<UIImage?, Never>]` dictionary ensures that 50 cells requesting the same image key in a single scroll frame all await one download, not 50 parallel downloads. The inner fetch task is explicitly spawned using `Task.detached(priority: .userInitiated) { ... }` rather than a standard `Task`. This severs the concurrency context and prevents **Task Cancellation Poisoning**: if the SwiftUI view that originally initiated the fetch scrolls off-screen and its `.task` modifier cancels, the detached background load continues uninterrupted. This guarantees the image successfully enters the RAM cache and subsequent coalesced callers receive the image rather than a poisoned `nil` result.
- **OOM risk during scroll**: Loading full-resolution images for every visible grid cell would exhaust RAM on large libraries.
- **Adaptive `maxDimension`**: `ScansGrid` computes the actual cell pixel size from screen width, column count, and display scale — `Int((screenWidth - spacing) / columns * scale)` — and passes it to `ScanThumbnail` as `maxDimension`. On a 3-column iPhone 15 at 3× scale this is roughly 390px, versus the previous hardcoded 1024px. `LocalImageLoader` threads `maxDimension` through to both local and remote load paths. Remote fallback downloads previously capped at a hardcoded 500px now use the same caller-provided value.
- **`maxDimension` by caller**:
  - `ScanThumbnail`: `600` default (ScansGrid overrides with a computed cell-pixel size).
  - `AsyncLocalImageView` (insight sheet carousel): `Int(MerianConfig.displayImageMaxSize)` = 2048. The 2048 px files are stored on disk; decoding them at full resolution ensures crisp display on Pro Max (1290 px native width) and iPad Pro (2048 px native width). Previously defaulted to 1024, producing visibly soft full-screen images on large devices.

### 5. RAM Cache (`ImageCache`)

`ImageCache.shared` (`Core/Data/Images/ImageCache.swift`) wraps `NSCache<NSString, UIImage>`.

```swift
cache.countLimit = 100                    // hard entry cap
cache.totalCostLimit = 30 * 1024 * 1024  // 30 MB byte cap
```

Every `set(_:forKey:)` call computes the pixel-area cost (`width × height × 4 bytes`) and passes it to `setObject(_:forKey:cost:)`. This gives `NSCache` an accurate memory footprint so it can evict the largest images first rather than treating a 4K thumbnail the same as a 64×64 icon.

- **Automatic eviction**: `NSCache` evicts entries under system memory pressure without any manual intervention. With `totalCostLimit` set, eviction is triggered by *actual byte usage* rather than just entry count.
- **No strong references**: Images in `NSCache` do not prevent deallocation, so they are released when iOS signals a memory warning.
- **Dimension-aware Cache Keys**: `LocalImageLoader` appends the requested `maxDimension` to the underlying file path or URL to form the cache key (e.g., `filename.webp_600`). This isolates payloads by size, preventing memory collisions where a low-resolution grid thumbnail (600px) could erroneously fulfill a subsequent high-resolution display request (2048px) for the same underlying file.

---

## Historical / Remote Images (Rehydration)

When a user reinstalls the app or signs in on a new device, `LocalScanRecord.localImagePath` contains a Cloudflare R2 URL rather than a local filename. `LocalImageLoader` handles this transparently — it detects the `http://` prefix and routes through `fetchNetworkFallback`, which downloads to a temp file, downsamples to the caller-provided `maxDimension` (no longer hardcoded), caches in RAM, and deletes the temp file.

This means the grid renders correctly with cloud images immediately, and any locally archived scans (via `ArchiveManager`) will be served from disk on subsequent loads once they have been rescued to `documentsDirectory`.

---

## Upload Path (Offline Queue)

For captures that go into the offline queue, images are written to disk by `FileIOActor.writeTemporaryImages` before the `OfflineQueuedScan` SwiftData record is inserted. During upload, `OfflineQueueManager` copies each image to a temp file in `URL.cachesDirectory` (naming convention: `<scanId>_<index>_temp_upload.webp`) and hands the path to `URLSession.uploadTask(with:fromFile:)`. The `Content-Type: image/webp` header is applied to the `URLRequest` before the upload task is created. The OS background session owns the byte transmission from that point. On upload completion, the temp staging file is deleted unconditionally regardless of success or failure.

**Offline queue image quality**: The offline queue stores inference-quality images only (768 px for Flash/free, 1024 px for Pro — whichever was applied at capture time). When an offline scan is reprocessed, `InferenceProcessingActor.parseAndSave` receives `displayDatas = []` and falls back to writing the inference-quality files to disk. This is a deliberate trade-off: the full-resolution photo is already saved to Camera Roll at capture time, so inference-quality on-disk files are an acceptable fallback for the subset of scans that passed through the offline queue. Live captures and gallery picks both produce display-quality on-disk files.

**Auth-state race condition (cold background relaunch)**: `runInferencePipeline` (called from `urlSession(_:task:didCompleteWithError:)`) reconstructs the R2 object key as `staging/<userId>/<scanId>_<imagePath>`. The key's user-ID prefix must match the authenticated user's UUID — the Edge Function's IDOR check rejects any request where the key prefix doesn't match the JWT's `user.id`. On a cold background relaunch triggered by the OS delivering a background URLSession event, the Supabase SDK may not have finished initializing, leaving `currentUser` nil. Previously the code fell back to `DeviceIdentityManager.shared.deviceId`, which doesn't match any JWT claim → 403. The fix: `runInferencePipeline` now reads `currentUser?.id.uuidString` and, if nil, returns early with a debug log (`"Offline inference deferred — auth state not loaded"`). The `OfflineQueuedScan` record is not tombstoned; `syncPendingScans` retries on the next connectivity cycle once auth state is loaded.

---

## Component Responsibilities Summary

| Component | Location | Responsibility |
|---|---|---|
| `ImageDownsampler` | `Core/Utilities/` | CGImageSource thumbnail decoding; `nonisolated` methods safe for concurrent calls; autoreleasepool |
| `FileIOActor` | `Core/Data/Database/` | Disk reads/writes; isolated from Main and SwiftData actors |
| `LocalImageLoader` | `Core/Data/Images/` | Load orchestration; RAM cache hits; request coalescing; local/remote routing |
| `ImageCache` | `Core/Data/Images/` | NSCache-backed RAM store; auto-evicts under memory pressure; 100-entry cap |
| `ArchiveManager` | `Core/Data/Images/` | Streams aging Free-tier images from R2 to disk via `URLSession.download(from:)`; avoids `.data(from:)` OOM |
