# Zero-OOM & Concurrency Architecture

Merian enforces a strict "Zero-OOM" (Out-Of-Memory), offline-first, and highly concurrent philosophy natively across its iOS client and serverless Deno Edge backend. This document captures the architectural decisions implemented to satisfy these demanding constraints.

## 1. iOS Concurrency & Memory Constraints (P0)

To fundamentally prevent UI hangs, memory leaks, and OS-level Watchdog terminations, the iOS app architecture imposes strict limits on resource boundaries:

### Background Suspension Limits (`OfflineQueueManager`)
When evaluating inference payloads in the wilderness disconnected from cell service, the system natively requires `UIBackgroundTaskIdentifier` hooks to complete URLSession executions. In `Merian`, these handles are explicitly extracted *outside* of generic `@MainActor` task executions to defeat rapid synchronous delegate fire-and-return OS suspension traps natively. We employ `@unchecked Sendable` reference boxes secured with `NSLock` instances to seamlessly bind these background identifiers.
Furthermore, to safely bridge strict Swift 6 concurrency boundaries without halting the nonisolated `urlSession(_:task:didCompleteWithError:)` execution loop, UI-level terminations natively map securely back inside explicit `Task { @MainActor in }` contexts stopping deadlock crashes.

### Hanging Continuations (`CameraManager`)
Apple's ISP (Image Signal Processor) can stall during extreme thermal saturation, failing to return an image frame via `AVCapturePhotoCaptureDelegate`. Rather than silently hanging the `isShutterActive` UI state indefinitely, Merian wraps structural `withCheckedThrowingContinuation` patterns securely inside a `withTaskCancellationHandler`. This is tied dynamically to a deterministic `Task.sleep(5.0)` hardware timeout fallback, resolving any stalled continuations cleanly with standard `CancellationError` triggers.

### Thread Starvation & Dropped Frames (`InferenceEngine`)
To prevent the Main Thread from stuttering during extreme native Swift UI interactions (like 120Hz `ScrollView` dragging), Merian prohibits standard Main Actor `JSONDecoder()` operations against massive scientific dictionary responses. Instead, the structural initialization and SwiftData `.insert()` methodologies are entirely detoured into `Task.detached(priority: .userInitiated)` structures.
Additionally, when checking historic scans natively, local `FileManager` checks determining sandbox paths are strictly prevented from binding into the `InsightCarouselView` rendering engine. They natively evaluate asynchronously within `InferenceEngine` dynamically binding to `@Published` values guaranteeing flawless 60fps Carousel snapping.

## 2. Deno Edge Scalability & OOM Protection (P1)

Deno Edge functions run in an ultra-restricted 256MB V8 heap footprint. To handle scale gracefully without 504 Timeouts:

### Stream Execution Over ArrayBuffers (`export-dwca`)
Global researchers pulling thousands of scientific records previously caused Deno OOM crashes when concatenating massive memory arrays via `JSZip.generateAsync()`. The `export-dwca` instance now structurally maps AWS `UNSIGNED-PAYLOAD` signatures coupled securely to `ReadableStream` generators spanning `JSZip.generateInternalStream`. This forces data directly out to the Cloudflare R2 proxy byte by byte, bypassing massive monolithic V8 memory reservations.

### Vector Sizing Attacks (`identify`)
Merian strictly protects backend endpoints from malformed or malicious multi-gigabyte S3 object structures by natively extracting `r2Response.headers.get("Content-Length")`. Any object exceeding the `5MB` constraint gracefully yields an `HTTP 413 Payload Too Large` immediately before the backend `.arrayBuffer()` parser attempts to evaluate it natively preventing Deno restarts.

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
