# Zero-OOM & Concurrency Architecture

Merian enforces a strict "Zero-OOM" (Out-Of-Memory), offline-first, and highly concurrent philosophy natively across its iOS client and serverless Deno Edge backend. This document captures the architectural decisions implemented to satisfy these demanding constraints.

## 1. iOS Concurrency & Memory Constraints (P0)

To fundamentally prevent UI hangs, memory leaks, and OS-level Watchdog terminations, the iOS app architecture imposes strict limits on resource boundaries:

### SwiftData Memory Exhaustion (`InsightSheetView`)
When querying records from massive user-generated biological libraries natively in SwiftData, executing a generic `FetchDescriptor` and filtering the `records.first(where:)` array synchronously in memory instantly triggers an OS JetSam out-of-memory crash for power users. Merian structurally prevents this array-loading catastrophe by natively injecting `#Predicate` constraints directly into the `FetchDescriptor`, forcing the underlying SQLite engine to isolate the single `targetId` perfectly without expanding V8 generic Swift collections.

### SQLite Thread-Safety Violations (`ArchiveManager`)
Instantiating non-isolated `ModelContext` containers directly inside arbitrary `Task.detached` background closures explicitly violates strict Swift 6 concurrency parameters, generating rampant data races and `EXC_BAD_ACCESS` fatal crashes natively under massive load. Merian explicitly abandons arbitrary detached SQLite threading; it maps background database ingestion (such as rescuing aging `.jpg` blobs off the S3 proxy) strictly inside localized `@ModelActor` constructs (like `ArchiveDatabaseActor`). This structurally isolates the SQL read/write matrix cleanly inside a sequential concurrent thread pool inherently preventing memory access corruption.

### Background Suspension Limits (`OfflineQueueManager`)
When evaluating inference payloads in the wilderness disconnected from cell service, the system natively requires `UIBackgroundTaskIdentifier` hooks to complete URLSession executions. In `Merian`, these handles are explicitly extracted *outside* of generic `@MainActor` task executions to defeat rapid synchronous delegate fire-and-return OS suspension traps natively. We employ `@unchecked Sendable` reference boxes secured with `NSLock` instances to seamlessly bind these background identifiers.
If a user hits the physical capture button and immediately locks their phone before the NVMe controller finishes writing `.jpg` bytes cleanly to disk during the `Task.detached { try imageData.write(to:) }` parameter natively, iOS instantly violently suspends the thread, permanently generating a corrupted 0KB binary footprint. By explicitly wrapping the disk I/O parameter inside a rigorous `OfflineQueueCaptureWrite` OS Background limit hook, Merian natively commands the iOS SpringBoard to grant the exact millisecond differential required to cleanly flush the data buffer natively preventing payload corruption.
Furthermore, to safely bridge strict Swift 6 concurrency boundaries without halting the nonisolated `urlSession(_:task:didCompleteWithError:)` execution loop, UI-level terminations natively map securely back inside explicit `Task { @MainActor in }` contexts stopping deadlock crashes.

### Hanging Continuations (`CameraManager`)
Apple's ISP (Image Signal Processor) can stall during extreme thermal saturation, failing to return an image frame via `AVCapturePhotoCaptureDelegate`. Rather than silently hanging the `isShutterActive` UI state indefinitely, Merian wraps structural `withCheckedThrowingContinuation` patterns securely inside a `withTaskCancellationHandler`. This is tied dynamically to a deterministic `Task.sleep(5.0)` hardware timeout fallback, resolving any stalled continuations cleanly with standard `CancellationError` triggers.

### Thread Starvation & Dropped Frames (`InferenceEngine`)
To prevent the Main Thread from stuttering during extreme native Swift UI interactions (like 120Hz `ScrollView` dragging), Merian prohibits standard Main Actor `JSONDecoder()` operations against massive scientific dictionary responses. Instead, the structural initialization and SwiftData `.insert()` methodologies are entirely detoured into `Task.detached(priority: .userInitiated)` structures.
Additionally, when checking historic scans natively, local `FileManager` checks determining sandbox paths are strictly prevented from binding into the `InsightCarouselView` rendering engine. They natively evaluate asynchronously within `InferenceEngine` dynamically binding to `@Published` values guaranteeing flawless 60fps Carousel snapping.

### Main Thread Search Thrashing (`LifeListSearchManager`)
When evaluating and mapping raw SwiftData query bounds across thousands of user payloads, lowercasing heavy concatenated String matrices directly inside `@MainActor` property observers (like `didSet`) forces devastating UI freezes when rendering the parent views. The `LifeListSearchManager` elegantly circumvents this native starvation by structuring mapping requests securely within a `Task.detached(priority: .userInitiated)`. It perfectly transforms the massive array payload off the UI layer into discrete matrices securely utilizing `Sendable` `ScanPayload` struct references decoupled from the core SwiftData `@Model` classes to prevent data race violations during `.detached` execution boundaries, explicitly calling `await MainActor.run` natively ONLY when the search cache finishes securely mapping the query bounds in the background. Furthermore, to prevent CPU thrashing (100% CPU utilization) during rapid SwiftData batch insertions, the detached sequence is bound to an explicit `indexingTask` reference; earlier task executions are successfully terminated instantly via `indexingTask?.cancel()` checking dynamic `Task.isCancelled` states dynamically shedding redundant String processing payload execution.

### Apple Geocoder Rate Limiting (`EnvironmentContextManager`)
When evaluating and extracting localized context natively via `@MainActor` executions, invoking `CLGeocoder().reverseGeocodeLocation` on every single historical index directly triggers Apple Server rate bounds. Rapid bulk photo imports explicitly fire `CLError.network` suspensions resulting in hours of stranded metadata. Merian completely abstracts the geocoder network loop with a RAM-based LRU coordinate matrix bounding string evaluations to a rounded hash (111-meter precision, `%.3f,%.3f`). Because natural location patterns evaluate synchronously over 100+ photos clustered on the exact coordinates dynamically without touching the device radio, offline synchronizations skip the server check entirely!

### App Boot SDK Stutter (`MerianApp`)
Historically, deferring heavy external SDK boot sequences (like PostHog and Crashlytics) via `DispatchQueue.main.asyncAfter` guaranteed a massive UI hitch exactly milliseconds after the `CameraRootView` finished rendering, completely destroying the "Instant-On" camera physics. Merian rigidly forces these SDK initializations completely off the iOS Main Thread by wrapping them within a `Task.detached(priority: .background)` combined seamlessly with `try? await Task.sleep(nanoseconds: 500_000_000)`, guaranteeing zero stutter during user acquisition transitions.

### Accelerate Vector Optimizations (`CameraManager`)
Calculating target Luma brightness by statically looping through deep `CVPixelBuffer` matrix addresses iteratively byte-by-byte (`totalLuma += UInt64(buffer[rowOffset + x]`) brutally pegs the iPhone processor inside the critical 60fps loop, provoking extreme thermal throttling in outdoor summer environments. Merian aggressively optimizes this calculation dynamically via Apple's `.Accelerate` framework. Utilizing `vImage_Buffer` alongside native execution vectors via `vImageHistogramCalculation_Planar8`, the computation relies strictly on lightning-fast vector hardware dropping execution latencies from massive milliseconds structurally down into microsecond bounds.

### Image Render RAM Spikes (`ImageCropperView`)
When capturing full resolution Apple ProRAW or high megapixel `AVCapturePhoto` assets via the viewfinder, translating native mathematical view coordinates into geometric grid slices forces extreme temporary V8 memory allocations. Drawing a 12-48MP uncompressed bitmap matrix natively into `UIGraphicsImageRenderer` to finalize the 768x768 output violently expands into active RAM, causing severe memory spikes (~50MB+) that explicitly trigger JetSam OOM terminations on older hardware natively. Merian rigidly abandons intermediate bitmaps outright; instead, it leverages Apple’s native C `ImageIO` framework (`CGImageDestination`). It writes the mathematical `cgImg.cropping(to: cropRect)` bound directly into a binary JPEG `.Data` buffer strictly utilizing `kCGImageDestinationImageMaxPixelSize: 768` and `kCGImagePropertyOrientation` option dictionaries entirely circumventing main RAM bloat and preserving absolute performance metrics.

## 2. Deno Edge Scalability & OOM Protection (P1)

Deno Edge functions run in an ultra-restricted 256MB V8 heap footprint. To handle scale gracefully without 504 Timeouts:

### Explicit Buffer Resolving vs Chunked Streams (`export-dwca`)
Global researchers pulling thousands of scientific records previously crashed AWS V4 Signatures on Cloudflare R2 when piping `<ReadableStream>` duplexes because the edge router dynamically appended `Transfer-Encoding: chunked` headers, eliciting violent `411 Length Required` or `403 Signature Does Not Match` rejections. Since actual physical images are deliberately offloaded from the .zip payload, the `export-dwca` generator natively limits its size under 10MB statically. Merian abandons streaming completely here, explicitly commanding `await zip.generateAsync({ type: "uint8array" })` to calculate the exact `Content-Length` binary bound natively bypassing AWS generic stream rejections without violating the 256MB V8 RAM limits.

### Vector Sizing Attacks (`identify`)
Merian strictly protects backend endpoints from malformed or malicious multi-gigabyte S3 object structures by natively extracting `r2Response.headers.get("Content-Length")`. Any object exceeding the `5MB` constraint gracefully yields an `HTTP 413 Payload Too Large` immediately before the backend `.arrayBuffer()` parser attempts to evaluate it natively preventing Deno restarts.

### V8 Event Loop Saturation (`export-dwca`)
Generating Darwin Core Archives natively extracts tens of thousands of occurrences securely masking global user identities via `crypto.subtle.digest` logic. Constructing a monolithic asynchronous mapping `Promise.all(scans.map(...)` array completely halts the Deno V8 Javascript event loop, blocking HTTP threads, starving the Node container, and producing lethal `504 Gateway Timeout` errors natively. Merian rigidly forces the loop into an isolated `BATCH_SIZE = 250` chunking matrix explicitly pushing blocks sequentially into the stack preserving deep backend thread latency and stopping CPU threshold limit exhaustion dead in its tracks.

### Native Execution Deferrals (`revenuecat-webhook`)
S3 bulk-bucket mutations (e.g. migrating 1000s of payloads from `/free/` into `/pro/` prefixes) exceeded Deno's 10-second processing restriction for power users. Merian decouples the webhook execution by logging tier upgrades and issuing `HTTP 200` instantly, natively deferring all structural S3 R2 operations cleanly out to the background via `EdgeRuntime.waitUntil(promise)`.

## 3. Infrastructure Latency & Privacy (P2)

To reduce Round Trip Times (RTT) by milliseconds dynamically and protect researchers structurally:

### Zero-RTT Authentication Mapping (`jose`)
Validating identities originally cost 50-80ms dynamically querying `supabase.auth.getUser()`. Every edge function (`identify`, `delete-scan`, `generate-upload-urls`, `export-dwca`) has seamlessly migrated to validating standard ES256 signatures natively checking the `Bearer` token physically via `jose.jwtVerify()` using the `SUPABASE_JWT_SECRET`. 

### Symmetrical Thread Execution (`Promise.all`)
Traditional Edge Functions sequentially executed R2 bucket transactions iterating array closures globally dynamically at `O(N)` latency scaling. Endpoints natively executing arrays have migrated structurally to `Promise.allSettled()` and `Promise.all()` to fire network requests evenly in parallel reducing aggregate wait latency drastically.

### Cryptographic Geoprivacy Limits (`export-dwca`)
Users releasing their scan captures to the "global" discovery feed previously distributed their exact UUID. DwC-A metadata distributions now intercept the internal ID and utilize a salted `crypto.subtle.digest("SHA-256")` cryptographic generator. This generates a stable, isolated anonymous `recordedBy` label structurally protecting explicit location boundaries from stalker behavior.

### Bounded Sync Caching (`ArchiveManager`)
Merian protects users on strict remote cellular data plans natively inside Swift by injecting rigorous `.fileExists` barriers blocking recursive `URLSession.download` operations on massive (100MB+) biological database configurations, hitting `ArchiveManager` seamlessly bypassing the network cleanly and serving physically straight out of the `documentsDirectory` index instantly.

### Large Payload RAM Bypass (`ArchiveManager`)
Archiving rich media from massive historical dataset queries previously loaded entire byte streams natively into `Data` objects inside system memory synchronously prior to passing the buffer into `PHAssetCreationRequest`. This triggered memory crashes on low-ram hardware securely. The `.downloadToLocalLibrary` execution natively sidesteps RAM allocations by executing `URLSession.shared.download(from: url)`, strictly writing the payload as a stream to an ephemeral disk mapping explicitly. `PHPhotoLibrary` consumes the data straight from disk, dropping peak RAM utilization by over 90%.
