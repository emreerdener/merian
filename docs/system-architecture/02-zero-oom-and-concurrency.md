# Zero-OOM & Concurrency Architecture

Naturebook enforces a "Zero-OOM" (Out-Of-Memory), offline-first, and highly
concurrent philosophy across its iOS client and serverless Deno Edge backend.
This document captures the architectural decisions implemented to satisfy these
constraints.

## 1. iOS Concurrency & Memory Constraints (P0)

To prevent UI hangs, memory leaks, and OS-level Watchdog terminations, the iOS
app architecture imposes strict limits on resource boundaries:

### Swift 6 Structured Concurrency & Constrained `Task.detached`

Historically, background threading relied heavily on `Task.detached(priority:)`.
While successful in offloading work from the `@MainActor`, unconstrained
detached tasks evade Swift 6 Sendable boundaries and structured cancellation
propagation. Merian now constrains detached work to narrow bridge points only:
AVFoundation startup where mediaserverd IPC must not block the main actor, and
pure CPU / file transforms over `Sendable` snapshots. High-level feature flows
route those escapes through `DetachedWork`, while long-lived workflows are
pushed into actors (`SearchFilterActor`, `FileIOActor`,
`InferenceProcessingActor`, `ExportProcessingActor`, `AudioSessionCoordinator`)
so cancellation, serialization, and ownership stay explicit.

### ImageIO, CoreVideo, & UIImage Autoreleasepool Memory Leaks

When performing bulk downsampling with CoreGraphics
(`ImageDownsampler.downsample` and `ImageCropProcessor`), the C-level APIs
(`CGImageSourceCreateThumbnailAtIndex`) allocate large transient buffers. In a
standard Swift async function looping hundreds of times without yielding,
Apple's Objective-C ARC delays flushing these buffers until the overarching task
suspends, producing transient RAM spikes that triggered JetSam OOM terminations.
Merian resolves this by wrapping the ImageIO rendering blocks inside
`autoreleasepool { ... }` boundaries, clearing C-level `NSMutableData` instances
immediately on each loop iteration and preserving a clean RAM ceiling.

This identical RAM ceiling violation exists during Apple Vision AI inferences,
detached image decoding, manual cropping, and metadata scrubbing. Executing
`VNImageRequestHandler` classifications (e.g., `InferenceEngine.swift` and
`SizeEstimator.swift`), uncompressing raw blobs via `UIImage(data:)` off the
main thread (`ImagesCarousel.swift` and `CropSheetModifier.swift`), or actively
parsing EXIF properties during GPS stripping (`PhotoLibraryManager.swift`'s
`executePhotoLibraryWrite`) inside detached closures leaves enormous
multi-megabyte allocations cached until the CPU rotates out the `Task.detached`
context. Merian enforces `autoreleasepool { ... }` wrappers around these entire
isolated blocks and explicitly deprecates raw `UIImage(data:)` inflations in
favor of constrained `ImageDownsampler.downsample(data:maxSize:)` extractions.
This guarantees that unmanaged ImageIO formats immediately relinquish memory
back to the system, dropping transient spikes completely and averting JetSam OOM
kills during rapid captures, exports, or swipes.

The candidate-review "original capture" expansion follows the same rule.
`OriginalCaptureExpandedView` must not call `UIImage(data:)` on
`activeMedia.liveImageData`; it downscales through
`ImageDownsampler.downsample(data:maxSize: MerianConfig.displayImageMaxSize)`
inside a detached `autoreleasepool` and only publishes the bounded `UIImage`
back to SwiftUI. Full-resolution originals are never inflated just to support
pinch-to-zoom.

### LocalImageLoader Unbounded ImageIO Execution

While pre-fetching bounds concurrent image downloads, unbounded programmatic
calls to `LocalImageLoader.loadLocal` and `fetchRemote` historically spawned
dozens of unbounded `Task.detached` blocks on the global concurrent executor,
driving immediate ImageIO over-subscription JetSam crashes during grid
scrolling. The zero-OOM architecture uses a four-permit asynchronous pool:
excess callers suspend without occupying an OS thread, and cancellation removes
queued waiters without consuming a later permit. Admitted ImageIO work runs on
an explicitly user-initiated concurrent decode queue. This preserves the
four-decode memory valve without `DispatchSemaphore.wait()` priority inversions
or cooperative-executor blocking. The remote loader's dedicated `mediaSession`
is also capped to `httpMaximumConnectionsPerHost = 4` with `urlCache = nil`,
aligning network fan-out with decode capacity and preventing the shared URL
cache from ballooning with thumbnail responses.

### TaskGroup Retain Cycles (`InferenceEngine`)

Within parallel inference scopes, applying
`group.addTask { @MainActor [self] in }` inside `withTaskGroup` unintentionally
forced hard retain cycles. If Edge network requests hung, the `InferenceEngine`
explicitly retained multi-shot buffers (`activeLiveCaptureDatas`) indefinitely.
The architecture strips hard closures, enforcing `@MainActor [weak self]`
alongside `guard let self else { return }`, breaking execution cycles and safely
allowing `cancelActiveRequest()` to wipe memory footprints without ghost task
zombies.

### DRY SwiftData Boilerplate Abstraction (`BackgroundDatabaseActor`)

Repeating `FetchDescriptor` and localized `try? modelContext.save()` blocks
across different inference override endpoints (`updateScanWithOverride`,
`updateScanAsFlagged`) injected unnecessary SQLite boilerplate and compilation
overhead. These endpoints are consolidated efficiently via a shared
`private func mutateScan(id: String, mutation: (LocalScanRecord) -> Void)`. By
stripping repeated fetches and saves, localized data mutations are isolated
within primitive Swift closures, protecting background threads and streamlining
SQL execution performance.

The scan-creation paths follow the same bounded abstraction rule without merging
modality behavior. Offline result processing, live visual persistence, and
nonvisual persistence now share `resolveSpeciesIdAndDiscoveryStatus(...)`,
`fetchLocalScanRecord(id:)`, and the small collision helpers around
`buildScanRecord(...)`. Offline replay still uses
`insertLocalScanRecordIfMissing(...)` so a completed queue result cannot
overwrite an existing local record; live and nonvisual saves use
`insertReplacingLocalScanRecord(...)` so a richer foreground inference can
replace a queued skeleton while preserving the existing species UUID and staged
field notes. The helpers stay private to `BackgroundDatabaseActor`, keeping
SwiftData fetch/delete/insert work on the actor executor.

Those scan-creation paths also share `ScanFinalizationCoordinator`, a tiny
actor-level lock keyed by stable scan ID. The lock is required because live
inference and background URLSession inference can complete the same queued scan
through independent SwiftData contexts. Serializing the final
`LocalScanRecord.id` write prevents Core Data from invoking unique-constraint
merge resolution on `capturedMediaEntries`, a no-inverse to-many relationship
that cannot be safely merged by `NSMergePolicy`. After waiting, the offline path
re-checks for an existing `LocalScanRecord` inside the lock and skips insertion
if the live path already committed.

### SwiftData Memory Exhaustion (`InsightSheetView`, `ScansSheetView`, & `BackgroundDatabaseActor`)

When querying records from large user-generated biological libraries in
SwiftData, executing a generic `FetchDescriptor` and filtering the
`records.first(where:)` array synchronously in memory triggers an OS JetSam
crash for power users. This applies specifically to underlying actor resolution
arrays which expand to multi-megabyte payloads in SQLite mappings.

View models and actor blocks must absolutely not fetch duplicate persistent
`@Model` arrays! `ScansLibrarySearchCoordinator` builds lookup state only from
the already-resident `@Query` result: `[String: Int]` index positions, a
`[String: LocalScanRecord]` mirror of those same live references for stale-index
fallback, `[String: ScanSortPrimitive]` sort snapshots, and cached sorted ID
arrays. This keeps search result materialization O(1) without issuing a second
SwiftData fetch or falling back to repeated `allScans.first(where:)` scans.

Search no longer linearly scans every `SearchableScan` on each keystroke. The
contained coordinator maintains a detached-built `SearchIndexSnapshot`
containing exact-term, unigram, bigram, and trigram posting lists plus
precomputed category buckets. Queries intersect those posting lists first, then
verify the narrowed candidates against `searchString.contains(...)`. This
preserves the previous substring semantics while moving the expensive work from
"full library per keypress" to "bounded candidate verification per keypress",
including single-character queries that used to fall back to the entire library.

The same principle applies to `BackgroundDatabaseActor.pushCollectionsToEdge()`,
which previously fetched every `ScanCollection` unconditionally including
Favorites (which is never synced). The fetch now uses a
`#Predicate { $0.name != "Favorites" }` to exclude Favorites at the SQLite
layer. `propertiesToFetch` is intentionally absent: `ScanCollection` has only
three stored attributes (`id`, `name`, `createdAt`) so there is nothing to skip,
and partial-attribute mode can prevent the `scans` relationship fault from
firing correctly, causing `scan_ids` to be serialised as `[]`.

`pushCollectionsToEdge()` projects membership from the exact relationship owners
it is synchronizing: non-Favorites `ScanCollection` rows with their inverse
`scans` relationship prefetched. It never enumerates unrelated `LocalScanRecord`
rows and therefore needs neither OFFSET pagination nor a full-library membership
map. Membership IDs are sorted for deterministic retries, while the Edge
endpoint reads existing memberships with a composite primary-key cursor and
applies only the database delta. Historical download reconciliation remains
separately page-bounded, and stale lookalike cache clearing still loops with a
biological/cache-present predicate plus `fetchLimit`.

Species Observation Charts also obey the "no full library fetch on `@MainActor`"
rule. `SpeciesObservationStatsViewModel` creates
`SpeciesObservationStatsDatabaseActor` and awaits filtered candidate fetches for
`speciesId` / `confirmedSpeciesId` plus exact scientific-name fallback. The
actor projects only the fields needed by the reducer, merges candidates by
record ID, and delegates normalization/bucketing to
`SpeciesObservationStatsReducer`. It returns a `Sendable` aggregate to the main
actor. Chart rendering must not call `modelContext.fetch` for every biological
`LocalScanRecord` from the view model.

### Deno Edge Stream Caps

Supabase Edge Functions run inside a constrained V8 isolate. Declared
`Content-Length` guards are useful for fast rejection, but they are never
authoritative because chunked transfer encoding and missing-length R2 responses
can still allocate past the heap before a post-read check runs. Media-bearing
handlers must parse request JSON through `readRequestJsonWithinBudget(...)` and
response bodies through `readResponseArrayBufferWithinBudget(...)` /
`readStreamArrayBufferWithinBudget(...)`. These helpers increment the byte
counter per chunk, cancel the reader on overflow, and only concatenate chunks
after the stream has stayed under budget.

Edge fanout must also be bounded. Use
`mapWithConcurrencyLimit(items, width, fn)` for outbound work that could scale
with user-controlled rows. `send-push-notification` uses width `8` for APNs
delivery and device-state writes, preventing one notification from opening a
socket/write storm inside a single isolate.

### File-Backed Import and Refinement Staging (`CaptureWorkspaceViewModel`)

The gallery import path previously bounced back to `@MainActor` on every
selected item to clear picker state, re-check the staged-image cap, re-check the
paywall gate, and append each decoded image individually. The refinement path
had the opposite problem: it eagerly loaded the full on-disk image into `Data`,
then potentially decoded it again into `UIImage`, creating unnecessary byte
copies for a path that is supposed to be latency-sensitive and zero-OOM safe.

The flow now snapshots the import budget once on `@MainActor`
(`availableSlots` + `canPerformScan`), clears `selectedPhotoItems`, and sends
file-backed still images through `MediaPreparationActor`. A Photos share-sheet
file first moves from the transient security-scoped URL into the actor-owned
`ExternalImageImportStore` Application Support inbox; no source bytes are
decoded during that copy. Historical metadata is converted into a
`HistoricalEnvironmentContextSnapshot: Sendable` before leaving the main actor,
and the worker task returns only `PreparedStagedImage` values (`Data` + sendable
metadata + budget metrics). Refinement staging and both import sources use the
same async prepared-image loader contract
(`PreparedStagedImageRequest -> PreparedStagedImage?`), whose production
implementation always writes a bounded 2048 px WebP/JPEG display payload rather
than a memory-mapped view of the original file. Final insertion back into
`stagedCapture.images` happens in a single main-actor commit, preserving Swift 6
isolation while eliminating both the per-item hop churn and the full-file
refinement read. That loader contract is also what the test suite stubs, so the
concurrency-safe production path and the behavior-verified test path stay
identical.

### SwiftData Relationship Faults (OOM)

When managing many-to-many SwiftData relationships, mutating the "Many" side
(e.g., `collection.scans.append(record)`) forces the underlying SQLite engine to
synchronously fault the entire array — potentially thousands of heavy
`LocalScanRecord` structures — into active RAM on the Main Thread. For power
users, this causes an immediate JetSam Out-Of-Memory termination. To protect the
RAM ceiling, inverted "One" side mutation is centralized in
`CollectionMutationService` for `SelectMultipleScansView` and
`CollectionDetailView`. Collection code mutates and reads the "One" side of the
relationship by reassigning `scan.collections` (for example
`var updated = scan.collections ?? []; updated.append(collection); scan.collections = updated`
or the analogous `removeAll(where:)` + reassignment pattern) rather than
mutating the "Many" side (e.g., `collection.scans?.append(record)`). This
prevents both the SQLite engine from expanding massive data arrays into active
RAM and SwiftData from missing optional-array mutation notifications. Deleting a
collection bypasses iterative child array loops entirely. By executing
`modelContext.delete(collection)`, the system uses SwiftData's default
`.nullify` behavior, severing connections without pulling individual heavy
payloads into active memory.

### SwiftData Child-Fault Trap (`CapturedMediaEntry`)

Mixed-media persistence writes both `capturedMediaJSON` and
`capturedMediaEntries`, but UI read paths must treat the scalar JSON as the
first read source. A TestFlight build 390 crash on May 12, 2026 showed
`BiologicalView` evaluating `LocalScanRecord.capturedMediaSnapshot`, sorting
`capturedMediaEntries`, and then faulting `CapturedMediaEntry.kindRaw` through
SwiftData's `_InvalidFutureBackingData`, which triggers `_assertionFailure` on
the main thread. This is not an OOM, but it shares the same zero-OOM principle:
hot SwiftUI body evaluation should not cross relationship fault boundaries when
an equivalent scalar projection exists.

`SerializedMediaItem.swift` now centralizes the rule in
`resolvedSerializedMediaItems(...)`: decode `capturedMediaJSON` first, and pass
`capturedMediaEntries` as an autoclosure so Swift does not even evaluate the
relationship unless JSON is absent or invalid. The relationship mirror remains
populated for migration/debugging/fallback durability. Do not reverse this order
in `LocalScanRecord.serializedCapturedMediaItems`,
`OfflineQueuedScan.serializedCapturedMediaItems`, `InsightSheetViewModel`,
`InferenceEngine.load(from:)`, export flows, or thumbnail code.

### SwiftUI View Invalidation Thrashing (`@Observable` Macro Migration)

Under the legacy `ObservableObject` protocol, whenever a core engine like
`InferenceEngine` or `HardwareOrchestrator` mutated a background tracking array
or hardware metric via `@Published`, it broadcast a global `objectWillChange`
event. This forced SwiftUI to recalculate the `body` of every view in the
environment graph that injected the object (e.g., `CaptureWorkspaceView`,
`InsightSheetView`), even if those views only relied on isolated, unchanged
properties like `isProcessing`. Merian eliminated `ObservableObject` from the
codebase.

All environmental managers (`AppDIContainer`, `CameraManager`,
`HardwareOrchestrator`, `InferenceEngine`, and `ScansManager`) were migrated to
Swift `@Observable` classes. This drops CPU render overhead because SwiftUI
tracks property access at runtime directly inside view closures. High-frequency
background mutations (`subjectDistanceInMeters`) no longer thrash the global
environment, preserving 120Hz refresh rates and reducing thermal loads. All
`@EnvironmentObject`, `@StateObject`, and `@ObservedObject` injections were
remapped to modern `@Environment()`, `@State`, and `@Bindable` constraints.

### Typed Event and Route Separation (`NotificationCenter` Migration)

Historically, implicit app state changes (e.g., crossing daily usage limits,
handling active deep link phases) were broadcast globally via string-keyed
`NotificationCenter.default.post` calls. This posed two architectural risks:

1. **Thread Hopping**: Notifications originating from detached backend tasks
   could inadvertently trigger UI modifications on a background thread if
   subscribers omitted `.receive(on: RunLoop.main)` guards.
2. **Type Safety & Retain Cycles**: String-keyed payloads (like
   `userInfo["scanId"]`) bypassed Swift compiler checks, and dangling `.sink`
   observer scopes without `[weak self]` caused invisible memory cycles.

**The refactor:** internal string broadcasts are forbidden. `AppDIContainer`
owns two deliberately different `@MainActor` services:

- `AppEventPublisher` delivers synchronous, loss-tolerant invalidations. It has
  no replay buffer and never carries authoritative collections or model objects.
- `AppRouteCoordinator` owns delivery-critical navigation in a bounded queue of
  16 lightweight envelopes with priority, semantic coalescing, expiry,
  account/session fences, and explicit outcomes.

The capacity check applies both at initial request ingress and when a deferred
in-flight envelope resumes after presentation teardown. An expired deferred
envelope is rejected before eviction, and a live resumed envelope can displace
only eligible equal-or-lower-priority work. This keeps the hard 16-envelope
bound intact even when producers refill the queue while a sheet is occupied.

Reference-type Combine consumers store their cancellables and capture themselves
weakly; SwiftUI `.onReceive` remains view-lifecycle-owned. Framework publishers
cross through `sinkOnMainActor`; the app bus is already main-actor isolated and
remains synchronous. Its erased `AnyPublisher` is constructed once instead of
being reallocated on every consumer access. The feature-local Insight carousel
pause coordinator follows the same allocation rule and is injected into every
production video page; builder-only callers share one inactive fallback,
avoiding both repeated erasure and recomposition-time publisher allocation. The
event-routing guard rejects raw `.sink` use outside the reviewed lifetime
owners, making capture strength, cancellable storage/cancellation, ordering, and
actor delivery an explicit review boundary. Full contracts and matrices live in
[Event and Presentation Routing](10-event-and-presentation-routing.md).

Transient UI feedback follows the same typed boundary. Feature state stores a
small `ToastPayload`—presentation UUID, title/body, `ToastSeverity`, and an
optional typed action descriptor—instead of a `String?` whose wording must be
parsed to recover severity or behavior. `MerianSystemFeedbackModifier` owns one
identity-keyed structured dismissal task. Passive banners disable hit testing,
omit interactive controls, and action banners claim their intrinsic card bounds
only when both the typed descriptor and view-owned handler exist. An incomplete
pairing is pass-through. Toast and milestone animation transactions are scoped
inside their overlay builders rather than around the feature root; neither path
introduces a full-screen invalidation, animation transaction, or gesture layer.
Producers assign the payload and view-owned action without `withAnimation`; the
modifier alone owns insertion and removal animation. Ordinary toast animation
identity also includes milestone suppression, allowing the same payload to
transition out and back in during serialized feedback ownership. The DI-owned
milestone presenter holds at most 32 lightweight items and its host registry at
most eight UUIDs. `ScanMilestoneCoordinator` holds at most 16 sleeping
automatic-retry tasks across all scans (in addition to the three-attempt
per-scan budget); oldest overflow is cancelled and its process-local captures
are released because the SwiftData goal hint remains the durable recovery
outbox. Account/session transitions cancel every retained retry task and clear
its preferred-goal/model-container captures.

### SwiftUI 17 Environment Macros (`HapticManager`)

Injecting singleton managers into the view hierarchy via
`.environment(container.hapticManager)` when those managers did not broadcast
state (such as pure hardware execution wrappers with no `@Published` or `@State`
variables) compiled cleanly in older Swift versions. Merian targets iOS 18/Swift
6, which requires every object passed into `.environment()` to be an
`@Observable` macro instance so the SwiftUI engine can track rendering graphs
uniformly. Classes like `HapticManager` adopt `@Observable` despite having no
view bindings, satisfying the `AppDIContainer` expansion boundaries.

### SwiftUI Presentation Collisions (`CaptureWorkspaceView`)

Concurrent root `.sheet` modifiers can collide when background, push, and user
actions arrive together. Merian maps root navigation to one `PresentedRoute` and
one `.sheet(item:)` in `CameraSheetRouter`. `AppRouteCoordinator` permits only
one in-flight presentation request; an occupied host records a deferral,
dismisses, and resumes from the real `onDismiss` callback. Achievement detail
and the notification prompt use that same host. There is no sleep-based sheet
handoff and no second root presentation anchor. Capture's feature-local crop,
video, description, question, and feedback presentations report the same UIKit
slot as occupied; global routes wait for their exact `onDismiss` before being
reclaimed. The feedback survey is also mounted from dismissal callbacks rather
than a guessed 1.2-second teardown delay.

Feature-local nested sheets use the same lifecycle rule. Candidate review,
confidence review, Insight Chat follow-ups, and Explore activity navigation
store typed pending actions with scan/presentation identity where applicable,
dismiss their current owner, and resume only from that owner's `onDismiss`. They
never mutate the backing identification or mount a sibling destination while
UIKit is tearing the source sheet down. This removes short-lived duplicate view
graphs and prevents a delayed callback from targeting a replacement scan.
Explore notification navigation stores only a post ID across dismissal and
re-resolves the bounded feed-store value afterward. A latest-wins token rejects
late async preparation after a newer tap or manual dismissal, and a prepared
destination or failure must commit with that same token before dismissal or
feedback. The coordinator keeps uncommitted staged state separate from the
pending destination consumed by `onDismiss`, so dismissal can invalidate stale
work without erasing an already committed handoff. For an owned post inside
Insight-hosted Explore, the leaf reports a scan ID, the Explore shell owns its
dismissal, and Insight applies the staged scan only from the shell's real
`onDismiss`.

Explore post detail, Insight content, the outer Insight shell, Profile,
achievement detail, candidate cards, and Species Dictionary detail also
serialize their feature-local destinations through typed presentation values.
Explore's remote composer preparation is a stored, replaceable task cancelled on
unmount or a competing presentation, and completion must match both request and
post identity before mounting. Insight resolves eight content destinations
through one value, with one sheet host and the gallery's full-screen binding
mutually exclusive with that same resolved value; its outer shell separately
serializes paywall, author, Field Chat, onboarding, and Explore and admits only
one teardown-queued follow-up. Profile avatar preparation is stored,
account/request fenced, and cannot mount a cropper while an editor or Photos
picker owns the local slot. One bounded prepared preview may wait for the Photos
picker binding to dismiss; replacement and account/view teardown clear it.
Species Dictionary uses one value for gallery, author, Field Chat, and paywall.
This prevents duplicate UIKit presentation requests and avoids briefly retaining
two heavy modal view graphs.

Transient visual delays are lifecycle-owned as well. Zoom labels, viewfinder and
SNR prompts, focus indicators, back-swipe rearming, Field Chat preparation, and
delayed Explore onboarding use structured or explicitly stored cancellable tasks
with identity checks. Unmount/reset cancels retained tasks, and passive surfaces
disable hit testing so neither timers nor invisible layout layers keep obsolete
UI graphs alive or block interaction.

### Capture Startup AttributeGraph Isolation

The user may configure Scan, Record, or Describe as the first capture page, so
the startup view graph cannot assume Camera is selected. The horizontal pager
uses `LazyHStack`, and `CaptureWorkspaceView` initializes both its selected mode
and scroll position from the first sanitized preference value. Describe keeps
its vertical scroller behind a UIKit hosting boundary; its dictation/prompt
lifecycle observer and prompt sheet are mounted outside the pager. Fixed capture
chrome and full-screen overlay clearance come from `CaptureControlBarLayout`
instead of measuring a child and writing that value back into parent layout. The
full-screen clearance remains 250 pt because the safe-area-ignoring pager
reports a zero bottom inset.

These boundaries eliminate the startup cycle previously formed by eager
off-screen pages, nested SwiftUI scroll graphs, presentation state, and a layout
preference feedback loop. Do not collapse them without cold-launching all three
first-mode permutations with `AG_PRINT_CYCLES=3`. Automated UI tests cover
Audio-first selection and Description-first rendering/sheet presentation; the
strict cycle trace remains a separate diagnostic requirement documented in
[`08-testing-strategy.md`](../development-guides/08-testing-strategy.md).

### Swift 6 MainActor Initialization (`CaptureTelemetry`)

When mapping telemetry from the global `InferenceEngine` into a lightweight,
`Sendable` `CaptureTelemetry` struct for network offloading, a standard struct
initializer `init(from inferenceEngine:)` violates Swift 6 concurrency rules.
Because the `InferenceEngine` tracks its properties on the `@MainActor`, a
non-isolated initializer crosses execution boundaries, triggering a "Main
actor-isolated property can not be referenced from a nonisolated context"
compiler error. Merian tags `@MainActor` on the `CaptureTelemetry` initializer
itself (`@MainActor init(from inferenceEngine: InferenceEngine)`), ensuring
execution aligns with `AppDIContainer.handleBackgroundPhase()` on the UI thread.

### SwiftData Environment Tearing (`MerianApp`)

Attaching `.modelContainer(container)` to conditional child elements (like
`.modelContainer` embedded on `CaptureWorkspaceView` but not `OnboardingView`
inside an `if/else` block) forces iOS to tear down and rebuild the SwiftData
environment during runtime view swaps. This causes blank screens or crashed
queries. Merian hoists all heavy `@Environment` injectables over the outer
conditional `Group` shell, ensuring the database mounts from frame zero
unconditionally.

### Eager Hardware Instantiation (`CameraManager` & `PhotoLibraryManager`)

Instantiating hardware layers (such as wiring `AVCaptureDeviceInput` inside
`CameraManager.init()`) is prohibited. Because Merian uses
`AppDIContainer.shared` to distribute managers via `.environmentObject`, these
classes boot on cold launch. Executing hardware configuration inside an `init`
defeats the Onboarding UI Permission Priming pipeline, triggering OS API modals
before the welcome screen appears. The architecture defers hardware
instantiation: locks like `.setupSession()` or
`PHPhotoLibrary.requestAuthorization` are shifted to explicit `.startSession()`
invocation blocks, orchestrating OS bindings behind UX gates.

### Lifecycle Initialization Leaks (`AppDIContainer`)

On a fresh cold-boot, SwiftUI evaluates the global `WindowGroup` environment and
transitions `Environment(\.scenePhase)` from `.inactive` to `.active`.
`MerianApp` observes this trigger and executes wake-up logic through
`AppLifecycleManager`. Camera session startup remains owned by the Capture
workspace rather than the lifecycle manager. Because this phase hook fires
milliseconds before the first `OnboardingView` renders, it previously bypassed
Onboarding gating, forcing camera initialization and OS permission alerts onto
the first Onboarding screen. To enforce bounded onboarding states, lifecycle
code evaluates the injected `AppSettings.hasCompletedOnboarding` value before
active hardware or queue work. After onboarding, it always allows consent
reconciliation while the required gate is closed, but it aborts hardware,
notification, usage, and queued provider work until current adult, Terms, and
Gemini evidence also passes.

### SwiftUI Render Loop CPU Thrashing (`ScansThumbnailView`)

When loading grid arrays from SwiftData entries, missing `imagePath` and
`fallbackImageUrl` values previously mapped conditionally to
`.task(id: ... ?? UUID().uuidString)`. SwiftUI cancels running `.task { }`
executions whenever their tracked `id` parameter changes. By returning a dynamic
UUID inline, SwiftUI aborted the task, forced a view invalidation, executed
layout, and evaluated a new UUID, re-triggering the task recursively. This
created infinite cancellation loops running at 120Hz, generating 100% CPU load
and draining device battery. Merian fixes this by replacing UUID generation with
a constant literal fallback: `?? "empty_thumbnail_state"`.

### SQLite Thread-Safety Violations

Instantiating non-isolated `ModelContext` containers inside arbitrary
`Task.detached` closures violates Swift 6 concurrency rules, generating data
races and `EXC_BAD_ACCESS` crashes under load. Merian abandoned arbitrary
detached SQLite threading. Background database ingestion runs inside
`@ModelActor` constructs such as `BackgroundDatabaseActor` and
`HistoricalDatabaseActor`. This isolates SQL read/write operations inside a
sequential concurrent thread pool, preventing memory access corruption.
Duplicated object mapping logic across models (such as copying `SpeciesData`
initialization dictionaries inside `OfflineQueueManager`) is consolidated back
into `init(fromEdgeResponse:)` origins, isolating network JSON decoding and
preventing data parity errors.

### Serial Upload Staging Head-of-Line Blocking (`OfflineQueueManager`)

Before upload tasks were handed to the OS background `URLSession`, each image in
a batch was staged serially: `FileManager.copyItem` (a synchronous NVMe write)
ran sequentially per file before the next began. For a 3-image scan on a busy
NVMe controller this added 500 ms–2 s of dead time before any byte reached R2.

`syncPendingScans` now uses `withTaskGroup` to fan out the staging work.
Pre-flight checks — URL parsing, file-existence guards, tombstoning — remain
serial because they are fast and because tombstoning mutates `@MainActor` state.
Only the `FileManager.copyItem` + `URLSession.uploadTask` pair is placed in a
task group child. All captured types (`URL`, `String`, `Int`, `URLSession`) are
`Sendable`, satisfying Swift 6 strict concurrency.

### Background Suspension Limits (`OfflineQueueManager`)

When evaluating inference payloads without cell service, the system requires
`UIBackgroundTaskIdentifier` hooks to complete URLSession executions. In Merian,
these handles are extracted outside of `@MainActor` task executions to avoid
rapid synchronous delegate fire-and-return OS suspension traps.

A unified `BackgroundTaskWrapper` reference box secured with `NSLock` binds
these background identifiers. To eliminate duplicated `#if os(iOS)` preprocessor
macros and `endBackgroundTask` loops across `enqueueCapture`,
`syncPendingScans`, and background URLSessions, the architecture uses a static
abstraction: `BackgroundTaskWrapper.execute(name:operation:)`. This handles
registering the active memory environment, tracking OS expiration callbacks, and
invoking `.endBackgroundTask` inside a `defer` block, guaranteeing URLSession
callbacks execute across thread boundaries safely.

If a user taps the capture button and immediately locks their phone before the
NVMe controller finishes writing `.jpg` bytes to disk, iOS suspends the thread,
producing a corrupted 0KB file. By wrapping the disk I/O inside this OS
Background task hook, Merian grants iOS the additional time required to flush
the data buffer and prevent payload corruption.

When bridging Swift 6 concurrency boundaries via `Task.detached`, these
reference boxes are injected as `Sendable` captures tracking temporal OS states.
By dropping optional limits and processing `.invalid` locks over the abstraction
boundary, the system prevents iOS Watchdog panics.

To prevent iOS from suspending the application before background I/O queues tear
down, Merian does not use `Task { ... }` blocks orphaned inside asynchronous
`defer` closures. Inside the URLSession completion handler, active task
evaluations (`session.allTasks`) are executed within the synchronous, awaited
boundary of `BackgroundTaskWrapper.execute`, guaranteeing the queue lock
releases before the `UIBackgroundTaskIdentifier` expires.

`urlSession(_:task:didCompleteWithError:)` extracts non-Sendable
`task.taskDescription` and HTTP string properties into local immutable variables
on the delegate context before crossing the background wrapper boundary.

Every upload teardown path carries the batch UUID into
`finishUploadSync(generation:)`. Empty batches, signing failures, zero-task
dispatches, background expiration, and delegate completion can release only the
matching batch. Inference result/failure paths use a `defer` that completes only
their exact inference UUID. This preserves unconditional cleanup without
allowing a delayed teardown to clear a replacement operation.

When chunking pending offline scans into Edge Function payloads, Merian caps
loop payloads via `.prefix(5)` on the `filteredScans` array. Previously,
applying a secondary `.prefix(5)` limit on the flattened `fileNames`,
`fileURLs`, and `scanIDs` arrays severed multi-capture payloads (since one
offline scan can have up to 2 local captures). Removing the truncation on the
flattened arrays and relying solely on the scan-level limit guarantees a partial
payload is never pushed to Cloudflare R2, preventing silent
`HTTP 400 Array Length` errors. Before signing URLs,
`BackgroundDatabaseActor.markScansAsUploading(scanIds:)` now returns the scan
IDs whose `.pending → .uploading` transition actually committed.
`syncPendingScans` signs and dispatches only those claimed records; if the actor
rolls back on fetch/save failure, no URLSession upload is launched against
unpersisted state. To comply with Swift 6 concurrency, redundant `await` hooks
preceding `session.uploadTask(with:fromFile:)` were removed. Since this
URLSession factory creates a deferred upload object synchronously, calling
`await` forced unnecessary thread hops and produced compiler concurrency faults.

### Background Delegate Deadlocks (`PushNotificationManager`)

When executing URLSession hooks via a background task identifier, the Merian
application remains visually suspended but structurally active. When AI
processing triggered completion alerts, `UNUserNotificationCenterDelegate` fired
`willPresent` because the process was alive. Historically, attempting to
asynchronously read `@MainActor UIApplication.shared.applicationState` inside
`willPresent` to conditionally suppress foreground banners caused race
conditions that led iOS to drop the notification entirely. Furthermore,
conditionally omitting notifications from `InferenceEngine` when the app was in
the foreground prevented users from receiving alerts if they navigated away from
the camera to browse their library.

Now, `InferenceEngine` emits notifications unconditionally. The delegate
executes purely synchronously by reading the persisted
`suppressInferenceBanners` key because `willPresent` is nonisolated and must
call its completion handler immediately. UI and view-model code mutate that
persisted key through the `AppSettings.suppressInferenceBanners` typed boundary,
instructing the delegate to suppress the banner only when the user is explicitly
staring at the scanning overlay or insight sheet. This guarantees reliable 100%
delivery for insight completions and achievements without triggering main-thread
blocking or spamming the active viewfinder context.

### Hardware Rotation Defenses (`CameraManager`)

Historically, attempting to manually map `UIDevice.orientation` against
`videoOrientation` triggered a double-rotation sequence because Apple's camera
firmware independently injected EXIF `CGImagePropertyOrientation` into the
output buffer. Merian resolves this using iOS 17's
`AVCaptureDevice.RotationCoordinator`. By instantiating a hardware rotation
coordinator against the active camera device, the app continuously monitors
physical accelerometer data independent of the user's software Control Center
orientation lock. The capture sequence synchronously injects
`videoRotationAngleForHorizonLevelCapture` into the `photoConnection` prior to
executing the shutter. This delegates the geometric rotation to the image signal
processor without corrupting Apple's resulting EXIF headers, guaranteeing
perfectly oriented portrait and landscape shots even while the device software
rotation is locked.

### Recorded Video Stabilization Boundary (`CameraManager`)

`AVCaptureMovieFileOutput` is attached during visual camera setup so Pro video
recording can start without reconfiguring the session after the hold threshold.
Because AVFoundation stabilization can crop the field of view, add latency, and
reduce still-photo dimensions when left enabled on a prepared output, Merian
keeps the movie connection's preferred stabilization mode `.off` until
`recordVideo(...)` starts a real clip. The start path requests `.auto`
stabilization only when the video connection supports it, records the requested
and active modes in hardware logs for physical-device QA, and resets the
connection to `.off` on finish, cancellation, or failure.

### Recording Generation and Delegate Correlation (`CameraManager`)

Every `recordVideo(...)` request creates one immutable generation containing a
UUID and a UUID-derived, standardized output URL. The continuation, start time,
duration cap, start callback, timeout, and automatic-stop task live together in
one `ActiveCameraVideoRecording` value protected by `videoRecordingLock`.
Recording state is taken and cleared atomically only when the caller presents
the current generation. This prevents an old cancellation or queued stop from
resolving a replacement recording.

Task cancellation alone is not a synchronization boundary: a task that was
cancelled after waking can still reach its queued closure. Each timeout and
automatic-stop task therefore also receives its own action UUID. Replacing a
task changes that action token under the same lock. The token-only placeholder
is installed before the task is launched, and the task handle is attached only
if the token is still current, closing both launch-before-install and
cancel-after-wake races. The camera-queue handler must match both the recording
generation and the current action UUID before it may stop AVFoundation or
resolve the continuation.

`AVCaptureFileOutputRecordingDelegate` does not provide the application's UUID.
The delegate entry points snapshot the output identity and callback URL, then
immediately dispatch to the serial camera queue. A callback may take active
state only when it came from `movieOutput` and its standardized URL equals the
current generation's URL. A delayed `didStartRecording` or `didFinishRecording`
for recording A therefore cannot clear recording B, reset B's stabilization,
invoke B's start callback, or resume B's continuation. A separate MainActor
presentation-generation check prevents an already-enqueued UI update from A from
changing B's `isRecordingVideo` state.

All `AVCaptureMovieFileOutput` and movie `AVCaptureConnection` reads and writes
are confined to the camera queue, including start, stop, cancellation, timeout,
delegate completion, and failure cleanup. Queue preconditions defend this
contract at runtime. Continuations are resumed only after the exact active
generation has been removed under the lock, making completion exactly-once.

### Hanging Continuations (`CameraManager`)

Apple's ISP (Image Signal Processor) can stall during extreme thermal
saturation, failing to return an image frame via
`AVCapturePhotoCaptureDelegate`. Rather than silently hanging the
`isShutterActive` UI state, Merian wraps `withCheckedThrowingContinuation`
patterns inside a `withTaskCancellationHandler`. To handle multiple overlapping
captures on a single UI state, Merian associates an array tracking queue
(`activeCaptureRequests`), isolating concurrent `timeoutTask?.cancel()` closures
via unique UUID identifiers. This clears specific stalling entries from RAM and
resolves dropped continuations via `CancellationError` without blocking
subsequent captures.

**Double-resume crash safety** (`CaptureRequest.isResumed`): Each
`CaptureRequest` struct carries an `isResumed: Bool` flag (default `false`). All
four resume sites — timeout expiry, queue connection failure, photo processing
completion, and task cancellation — guard via
`guard var r = activeCaptureRequests[requestId], !r.isResumed else { return nil }`
inside `requestsLock.withLock`. The flag is set to `true` and the entry is
removed from the dictionary atomically within the same lock, making
double-resume structurally impossible. Without this guard, a late
`photoOutput(_:didFinishProcessingPhoto:)` callback racing against a timeout
expiry could resume the same `CheckedContinuation` twice, which is undefined
behaviour and causes an immediate crash.

### Post-Inference Image Buffer Cleanup (`InferenceEngine`)

Prior to the enqueue-at-submission refactor, `InferenceEngine` retained
`activeImageData`, `activeLiveCaptureDatas`, and `activeCompressedImageData` as
`@MainActor` properties to support background-rescue re-queuing. For multi-shot
captures, these arrays held several MB of compressed JPEG bytes with no cleanup
path on the success branch.

All three buffers have been removed entirely. Scan durability is now provided at
submission time — `CaptureWorkspaceViewModel.submitActiveScan` calls
`enqueueCapture` synchronously before any `async` boundary and writes images to
disk (see §8 of `docs/development-guides/11-swiftdata-and-api-gotchas.md`). An
online live scan initially suppresses that row's background upload so it does
not contend with the inline inference body; upload completion, a two-second
fail-safe, request failure, connectivity loss, app backgrounding, or relaunch
releases the durable row. `analyze()` receives images as `imageDatas`
parameters, uses them for base64 encoding, and does not retain them as instance
state — Swift ARC reclaims the memory after the call.

`activeImageData: Data?` is the only raw image buffer retained in
`InferenceEngine` during the inference window. It holds a single 2048 px
display-quality WebP frame that seeds `activeMedia` with a live preview while
inference is in progress. Once `InferenceProcessingActor.parseAndSave`
completes, the persisted user timeline is rebuilt into `activeMedia` and the
carousel transitions from the in-memory preview to path-backed `MediaItem.image`
entries — at which point `activeImageData` is still held but no longer the
primary display source. It is released when `prepareForNewScan()` or
`cancelActiveRequest()` fires. This two-phase design eliminates the previous
`activeDisplayDatas: [Data]` array that held all display images (potentially
multiple MB for multi-image captures) simultaneously in RAM for the full
inference session.

### Historical Scan Hydration Task Proliferation (`InferenceEngine.load(from:)`)

When opening a historical scan, `load(from:)` previously spawned up to 4
independent untracked `Task { }` blocks (image path validation, JSON decode,
Wikipedia hydration, enrichment/GBIF hydration). Navigating rapidly between
scans left all prior tasks running — each decoding JSON, making network calls,
and writing `@Observable` state for a scan no longer on screen.

`InferenceEngine` now owns a single
`@ObservationIgnored private var historicHydrationTask: Task<Void, Never>?`. At
the start of every `load(from:)` call, the previous task is cancelled. All async
hydration work (image-path validation → JSON blob decode → override patch →
Wikipedia → enrichment) runs sequentially inside this one task with
`guard !Task.isCancelled` checks between stages. The JSON blobs are decoded
inside a nested `Task.detached` to keep `JSONDecoder` off `@MainActor`.

`historicHydrationTask` is also cancelled at the start of both
`prepareForNewScan()` and `analyze()` (see below), so a library-scan hydration
that is still running when the user submits a new capture can never write stale
image paths, candidates, or species data over the new scan's cleared state.

### Stale Content-Router State on New Scan (`InferenceEngine.prepareForNewScan()`)

**Background:** `InsightContentView` routes to `AnalyzingContentView` only when
`inferenceEngine.isProcessing == true && inferenceEngine.speciesData == nil`.
After `load(from:)` finishes for a library scan, `isProcessing = false` and
`speciesData` is fully populated. If the user then submits a new scan,
`CaptureWorkspaceViewModel.submitActiveScan()` opens the sheet immediately
(`activeSheet = .insight`) but calls `analyze()` only after an async
telemetry-resolution Task resolves — a gap that can span hundreds of
milliseconds. During that window, the router evaluated the stale library state
and briefly rendered `BiologicalView` (or `NonBiologicalView`) before
`analyze()` cleared `speciesData`.

**Fix:** `InferenceEngine` exposes `prepareForNewScan()`, called synchronously
only when a live inference path is confirmed online and immediately before
setting `activeSheet = .insight`. Offline queued-only submissions must not call
it; otherwise `isProcessing` can be left true with no live task to clear it. It:

- Cancels durable/result tasks: `inferenceTask`, `liveHydrationTask`,
  `historicHydrationTask`, `gbifHydrationTask`, and `enrichmentWriteTask`.
- Calls `cancelLocalVisualAnalysis()` to cancel `localClassificationTask`,
  `foundationVisualCueTask`, and `phaseRotationTask`, then releases the bounded
  local derivative, Vision candidates, request-dispatch flag, and phrase
  coordinator state. None of this ephemeral work joins the Auth-transition
  quiescence drain or delays the next scan.
- Nil-s the task handles for `historicHydrationTask`, `gbifHydrationTask`, and
  `enrichmentWriteTask`.
- Resets all loading flags (`isEnrichmentLoading`, `isLookalikesLoading`) and
  `scanningPhaseText`.
- Sets `isProcessing = true` and `speciesData = nil` atomically, so the router
  sees the correct `AnalyzingContentView` condition from the very first SwiftUI
  frame.
- Clears all image and telemetry state (`activeMedia`, `activeImageData`, all
  environmental telemetry fields).

`analyze()` subsequently overwrites the image and telemetry fields with the new
scan's data once the async Task resolves. `analyze()` also cancels
`historicHydrationTask` internally so the offline-queue reprocessing path (which
calls `analyze()` directly without going through `submitActiveScan()`) gets the
same protection.

### Camera Capture Decode Boundary

The camera shutter path (`CaptureWorkspaceViewModel.executeCapture`) captures
hardware/location state on the main actor, but the 12MP ImageIO downsample,
composing-zone crop, and WebP/JPEG encode run through
`DetachedWork.value(category: .imagePreparation)`. The detached worker returns
only bounded inference/display `Data` plus a `SendableCGImage` preview wrapper.
`AVCapturePhoto.fileDataRepresentation()` is wrapped in an `autoreleasepool` so
AVFoundation intermediates are released promptly after the continuation resumes.

### Non-Crashing Startup Contract

`MerianEnvironment.load()` now returns typed configuration plus issue
diagnostics rather than calling `fatalError`. Missing Supabase config blocks
network endpoint construction with `MerianError.invalidURL`; optional
analytics/payment SDKs skip setup when their keys are absent. `MerianApp` uses
store-aware SwiftData startup selection (current-store open, recent
source-isolated plan, or full historical migration), then corruption quarantine
and retry, legacy migration rescue with a fresh persistent store, in-memory safe
mode, and finally a startup-blocked UI if no `ModelContainer` can be created. No
auth/config/store bootstrap path may hard-crash before user-visible recovery UI.

### Unbounded GBIF Reference Image Accumulation (`InferenceEngine`)

`fetchGBIFImagesAndHydrate` previously appended up to 4 new GBIF image URLs to
`speciesData?.referenceImageUrl` (a comma-separated string) on every open. GBIF
URLs are now capped at **5 entries** (`Array(currentUrls.prefix(5))`). The
redundant `await MainActor.run { }` hops inside this method have also been
removed — `InferenceEngine` is a `@MainActor` class, so all methods resume on
the main actor after every `await`; the explicit wrappers were a no-op.

### Enrichment Re-firing on Every Open (`InferenceEngine`)

For species that permanently lack GBIF data or habitat descriptions, the
enrichment eligibility condition evaluated `true` on every open, firing an
`enrich-scan` Edge Function call that returned the same empty result each time.
`InferenceEngine` now maintains
`@ObservationIgnored private var enrichmentAttemptedScanIds: Set<String>`. The
gate is set **before** the call so even empty results prevent re-fires. Live
inference scans (via `analyze()`) bypass this gate.

### Enrichment Rate-Limit Recovery (`InferenceEngine`)

`fetchAndApplyEnrichment` calls the `enrich-scan` Edge Function, which proxies
to Gemini. When Gemini returns HTTP 429, `InferenceEngine` previously set a
permanent `isEnrichmentRateLimited: Bool = true` flag for the remainder of the
app session — a single transient quota spike killed enrichment for all
subsequent scans until app restart.

`isEnrichmentRateLimited` has been replaced with
`@ObservationIgnored private var enrichmentRateLimitedUntil: Date?`. On a 429
response, `enrichmentRateLimitedUntil` is set to
`Date.now.addingTimeInterval(60)` (60-second backoff; the `Retry-After` response
header is used when present). The gate condition is:

```swift
guard enrichmentRateLimitedUntil.map({ $0 <= Date.now }) ?? true else { return }
```

- `nil` → passes (not rate limited)
- Future date → blocks (backoff still active)
- Past date → passes (backoff expired, enrichment resumes automatically)

`enrichmentRateLimitedUntil` is cleared to `nil` inside `prepareForNewScan()` so
a new scan session does not inherit a prior session's backoff window. Both the
`enrichment` and `lookalikes` scope 429 handlers set the same
`enrichmentRateLimitedUntil` property.

### Session-Scoped Deduplication Set Eviction (`InferenceEngine`)

`InferenceEngine` maintains three session-scoped `Set<String>` guards to prevent
redundant network calls across an app session:

- **`wikiFetchAttemptedIds`** — Wikipedia fetch attempts, keyed by scientific
  name.
- **`enrichedSpeciesTimestamps: [String: Double]`** — species that have
  completed a full `enrich-scan` Edge call, keyed by scientific name, with the
  `timeIntervalSinceReferenceDate` of first enrichment as the value. Persisted
  to `UserDefaults` (key: `"enrichedSpeciesTimestamps"`) with a **24-hour
  rolling expiration window** — `isSpeciesEnriched(name)` returns `true` only
  when the stored timestamp is less than 86 400 seconds old. Loaded once at
  `InferenceEngine` init from `UserDefaults`; written back lazily only when a
  new species is first enriched via `markSpeciesEnriched(name)`. Replaces the
  previous in-memory `Set<String>` that was session-scoped and had a hard
  500-entry cap — the `UserDefaults` dictionary persists across app restarts,
  preventing redundant enrichment calls for species the user has already scanned
  within the past day.
- **`enrichmentAttemptedScanIds`** — scan IDs for which enrichment was attempted
  via `load(from:)`. Prevents re-firing on every historical open for species
  that permanently lack GBIF or habitat data. Remains session-scoped with a
  500-entry cap and 10% eviction policy.

`wikiFetchAttemptedIds` and `enrichmentAttemptedScanIds` share a single
`private let sessionSetCap = 500` ceiling. When either set reaches the cap,
**10% of entries** (`prefix(sessionSetCap / 10)`) are evicted, preserving 90% of
recently-used entries and bounding session RAM to ~50 KB per set.
`enrichedSpeciesTimestamps` has no hard cap — the 24-hour TTL window naturally
bounds growth to the number of distinct species a user scans within a day
(practically < 200 entries for any realistic session).

### Stale GBIF Write Prevention — Tracked `gbifHydrationTask` (`InferenceEngine`)

`fetchAndApplyEnrichment` previously spawned a bare `Task { }` to call
`fetchGBIFImagesAndHydrate` after resolving a `gbif_taxon_key` from the
`enrich-scan` response. This task was not attached to any cancellable handle:
when `cancelActiveRequest()` cancelled `liveHydrationTask` or
`historicHydrationTask` (e.g. user starts a new scan), the GBIF task kept
running. It would eventually complete and call
`BackgroundDatabaseActor.updateScanWithWikipedia(scanId:..., imageUrl:)` —
writing image URLs to a record that might now belong to a completely different
species or, worse, to a record that was deleted between task spawn and
completion.

`InferenceEngine` now owns
`@ObservationIgnored private var gbifHydrationTask: Task<Void, Never>?`. The
property is:

- **Cancelled and nil-ed** at the start of every `analyze()` call (new scan
  starts) and inside `cancelActiveRequest()` (background rescue or explicit
  cancel).
- **Assigned immediately on `@MainActor`** inside `fetchAndApplyEnrichment` —
  `gbifHydrationTask?.cancel(); gbifHydrationTask = Task { ... }` — so only one
  GBIF hydration is ever in flight at a time. **Critical**: this assignment must
  happen synchronously on `@MainActor`, never deferred inside an `await` or
  another `Task`. If it were nested inside `enrichmentWriteTask` (after the
  async DB write), a `prepareForNewScan()` call arriving during that write would
  see `gbifHydrationTask == nil`, issue a no-op cancel, and the deferred
  assignment would then spawn a running GBIF task that is never cancelled —
  leaking work for the previous scan into the next scan's result.
  `enrichmentWriteTask` is kept purely for the DB write
  (`updateScanWithEnrichment`) and is independent of `gbifHydrationTask`.

### GBIF Response Decoded Off `@MainActor` (`InferenceEngine`)

`fetchGBIFImagesAndHydrate` is a method on `@MainActor InferenceEngine`. After
`URLSession.shared.data(for:)` suspends and resumes, execution returns to the
main actor. Previously,
`JSONDecoder().decode(GBIFMediaResponse.self, from: data)` ran synchronously on
the main run loop — for common species GBIF occurrence responses this payload is
50–200 KB. Parsing that on `@MainActor` produces a measurable jank spike
immediately after the user receives their scan result, especially during
`ScrollView` interactions at 120 Hz.

The decode now runs inside `Task.detached(priority: .utility)`. Only the
URL-extraction loop and the final `[String]` result cross back to `@MainActor`
after the decode completes:

```swift
let newUrls = try await Task.detached(priority: .utility) {
    let decoded = try JSONDecoder().decode(GBIFMediaResponse.self, from: data)
    var urls: [String] = []
    for result in decoded.results ?? [] {
        for mediaItem in result.media ?? [] {
            if mediaItem.type == "StillImage", let id = mediaItem.identifier {
                urls.append(id); break
            }
        }
    }
    return urls
}.value
// @MainActor UI patching continues here
```

### `JSONEncoder` Hoist + Consolidated Date Parse in `ingestScans` (`HistoricalDatabaseActor`)

`HistoricalDatabaseActor.ingestScans` processes up to
`MerianConfig.historicalSyncPageSize` scan records per page call. Two
per-iteration allocations compounded over bulk ingestion:

1. **`JSONEncoder()` per scan** — `JSONEncoder` init touches multiple Obj-C
   objects (key encoding strategy, output formatting, date strategy). Over a
   1,000-scan first sync this is 1,000 gratuitous allocations generating GC
   pressure and cache thrash on the `@ModelActor` thread. The encoder is now
   hoisted as `let encoder = JSONEncoder()` before the loop and reused across
   all records.

2. **Double date parse per scan** — `parsedDate` and `exifDate` were derived
   from the exact same timestamp string through the exact same two formatters in
   two separate `flatMap` closures. `ISO8601DateFormatter.date(from:)` is a
   Calendar+Locale-sensitive parse, not a cheap O(1) op. On a 10,000-scan sync
   this was ~20,000 redundant formatter calls. Both values are now derived from
   a single parse: `let exifDate: Date? = ...`, then
   `let parsedDate = exifDate ?? Date()`. Formatter order is also optimised: a
   `.contains(".")` check on the timestamp string routes fractional timestamps
   to the fractional formatter first, and standard timestamps (the majority) to
   the plain formatter first, eliminating the consistent cold-path miss of
   always trying the fractional formatter first.

### `syncCollections` Fetch Limit Guard (`HistoricalDatabaseActor`)

`HistoricalDatabaseActor.syncCollections` previously issued
`FetchDescriptor<ScanCollection>()` with no predicate and no fetch limit — a
full-table scan that loads every `ScanCollection` record including any orphaned
or schema-migrated rows. A defensive `fetchLimit = 500` is now set. For the vast
majority of users (5–50 collections) this is invisible; it prevents a
pathological case where a schema migration or bug creating duplicate collections
causes the entire collection graph to be loaded and faulted into memory before
sync begins.

### `ScanRepository.syncCollections` N+1 Fix (`ScanRepository`)

`ScanRepository.syncCollections` (the iOS-side cloud-down reconciliation)
previously used an `fetchIdentifiers + model(for:)` loop to look up
`LocalScanRecord` instances for each scan referenced in a remote collection's
`collection_scans` array. On a library of thousands of scans, this faulted a
separate DB round-trip per referenced scan ID, producing an N+1 query pattern.

The function now issues a **single `FetchDescriptor<LocalScanRecord>`** filtered
to only the scan IDs referenced by the incoming collections, then builds a
`Dictionary<String, LocalScanRecord>` keyed on lowercased ID for O(1) lookups.
The same pattern is applied to the `ScanCollection` fetch — a single
`FetchDescriptor<ScanCollection>` with `fetchLimit = 500` is issued up-front and
the results are stored in a dictionary, replacing per-entry existence checks.
Both single-fetch + dictionary-lookup changes bound the total SwiftData
operations to O(1) per remote collection/scan regardless of library size.

### Reconnect Debounce Task Stacking (`OfflineQueueManager`)

On a flapping WiFi ↔ cellular handoff, `NWPathMonitor` fires multiple
`pathUpdateHandler` callbacks. Each positive-connectivity callback previously
created a new untracked 1-second debounce task, causing stacked
`syncPendingScans()` calls. `OfflineQueueManager` now holds
`@ObservationIgnored private var reconnectDebounceTask: Task<Void, Never>?`.
Every positive event cancels the previous debounce task before creating a new
one. Connectivity-loss cancels the pending debounce alongside `syncTask` and
`collectionSyncTask`, **and additionally nils the reference**
(`reconnectDebounceTask = nil`). Without the nil assignment, a subsequent
reconnect callback would see a non-nil (but already-cancelled) task handle,
cancel it redundantly, and potentially skip creating a new one depending on
control flow — the nil ensures the next reconnect always spawns a fresh debounce
task.

The debounce window is **3 seconds** (previously 1 second). A WiFi → cellular →
WiFi transition typically fires 3–4 `NWPathMonitor` events within ~2 seconds;
the 1-second window fired on the first cellular `satisfied` event before WiFi
association was complete, triggering sync on a metered connection unnecessarily.
The 3-second window lets the OS networking stack fully resolve the final
interface before the sync begins.

Additionally, after the debounce resolves, the handler checks
`monitor.currentPath.isConstrained` before proceeding. When `isConstrained` is
`true` (iOS Low Data Mode is active), all non-critical background syncs are
skipped. Critical user-triggered uploads are not affected — they bypass this
path entirely.

### Background Write Task Cap and Pending Queue (`InferenceEngine`)

After a successful identification, `InferenceEngine` can queue background
`BackgroundDatabaseActor` write tasks for Wikipedia hydration, GBIF image
hydration, and enrichment persistence. Identification review persistence and
review-bound metadata use a separate serial latest-action tail. Without a
ceiling, rapid successive scans or a heavy session opening dozens of historical
records could accumulate an unbounded number of concurrent actor instances,
retained closures, and associated `ModelContext` objects, eventually triggering
JetSam OOM.

`InferenceEngine` caps both concurrent in-flight tasks and retained pending
closures with `backgroundWriteTaskCap = 8` and
`pendingBackgroundWriteTaskCap = 8`. When all active slots are occupied,
`executeTrackedBackgroundTask` appends at most eight incoming closures to
`pendingBackgroundTasks`. Further best-effort metadata writes are dropped until
capacity returns; the engine never creates an unbounded overflow buffer. When a
slot frees (inside the `defer` block that removes the completed task from
`backgroundWriteTasks`), `drainPendingBackgroundTasks()` dequeues the next
pending closure via `removeFirst()` and dispatches it into a tracked slot. The
result is a hard maximum of eight active and eight pending write closures per
engine presentation.

### Wikipedia Decode Offloaded from `@MainActor` (`InferenceEngine`)

After `URLSession` returns the Wikipedia mobile-sections API response,
`fetchWikipediaAndHydrate` previously decoded the JSON and ran `stripHTML`
synchronously on `@MainActor`. For popular species, the mobile-sections payload
is 50–200 KB. Running `JSONDecoder` and the HTML stripping pass on the main run
loop produces a measurable jank spike immediately after the user receives their
scan result — especially visible during 120Hz `ScrollView` interactions.

The JSON decode and `stripHTML` now run inside
`Task.detached(priority: .utility)`. `stripHTML` is marked `nonisolated` since
it is a pure string transformation with no actor state dependencies. Only the
final `(String, String, String?)` tuple crosses back to `@MainActor` once the
detached task completes.

The detached closure throws `WikiContentNotFound` (a
`private struct WikiContentNotFound: Error {}` sentinel) when the Wikipedia
response contains no "Description" section or the stripped text is empty. This
is distinct from `CancellationError` — a missing description is a parse skip,
not task cancellation — so the `catch` path can correctly distinguish between
the two without accidentally swallowing genuine cancellations.

### `AVCaptureSession.inputs` Thread Safety (`CameraManager`)

`AVCaptureSession.inputs` must be accessed on the session queue.
`applyTargetFPS`, `throttleToIdleState`, `toggleFlash()`, and
`applyZoom(factor:ramp:)` resolve video device inputs inside `queue.async`, then
publish observable UI state back through `Task { @MainActor in ... }`. The same
ownership rule applies to `AVCaptureMovieFileOutput`, its recording state, and
its video connection: start/stop, stabilization, timeout cleanup, and
recording-delegate handling all execute on the camera queue. New hardware
control paths must follow that split: AVFoundation session/device/output reads
and `lockForConfiguration()` stay on the camera queue; `@Observable` state
writes stay on `@MainActor`.

### Historical Scan Hydration Snapshot Boundary (`InferenceEngine`)

`InferenceEngine.load(from:)` receives a live SwiftData `LocalScanRecord`, but
its follow-up hydration task can outlive the view transition that provided that
record. Every scalar used by the async task must be copied while the model is
still live on `@MainActor`. This includes reference-image URLs: the task reads
the snapshotted `recordReferenceImageUrl` value instead of touching
`record.referenceImageUrl` after suspension. Accessing a deleted or detached
`@Model` from the hydration task can crash in
`SwiftData._KKMDBackingData.getValue`.

### Thread Starvation & Dropped Frames (`InferenceEngine`)

To prevent the Main Thread from stuttering during 120Hz `ScrollView`
interactions, `JSONDecoder()` operations against large scientific dictionary
responses run inside `Task.detached(priority: .userInitiated)`. To prevent Swift
6 race conditions causing `EXC_BAD_ACCESS` during rapid multithreading,
SwiftData `.insert()` operations are decoupled from the raw `.detached` payload
and routed through the `@ModelActor BackgroundDatabaseActor`, preserving
isolated SQL boundaries.

If the user rapidly triggers the capture shutter, old execution loops are
cancelled via `self.inferenceTask?.cancel()` at the top of `.analyze()`,
immediately severing orphan tasks that leak memory, consume cellular data, and
increment API limits.

When checking historic scans, local `FileManager` checks for sandbox paths
evaluate asynchronously within `InferenceEngine`, binding to observable state
and guaranteeing smooth insight carousel rendering.

### Main Thread Disk I/O Blocking

Executing local `FileManager` disk sweeps and `URLSession` network downloads on
the `@MainActor` thread blocks the 120Hz UI refresh rate during heavy
operations. `InsightMediaExportManager` now routes remote downloads,
downsampling, and photo-save work through a bounded export actor pipeline, while
cache-clearance flows in Settings use `DetachedWork` only as a narrow Sendable
bridge before actor/file-system work takes over. The main thread is only
re-entered to flip UI state or trigger `HapticManager` responses.

### OOM-Safe Bulk Deletion (`NonBiologicalScanService`)

When executing bulk "Clear All" operations on potentially hundreds of
non-biological scans, looping file and SwiftData row deletion on the main actor
would freeze the UI. Passing `[LocalScanRecord]` model objects to background
work would also violate the SwiftData executor boundary.

The Scans Shell remains the sole query owner and passes its record set into
`NonBiologicalScansViewModel`. At deletion ingress, the main-actor view model
copies only IDs and ordered image/audio/video paths into
`NonBiologicalScanErasureSnapshot` values. These immutable `Sendable` values
cross the injected service boundary; the live adapter converts them into
`BackgroundDatabaseActor.ScanErasurePayload` values, and the database actor
re-fetches every ID before mutation. It skips an existing row that is now
biological, including its local paths and cloud-deletion job; eligible or
already-missing IDs retain the idempotent deletion path. The actor saves the
batch once, and only locally owned paths returned after that commit are passed
to `FileIOActor` for cleanup. No detached task transports SwiftData models.

The observable view model owns the one-operation overlap fence, grid/toolbar
interactivity, compact progress badge, and feedback state. After database and
file completion it publishes `scanLibraryChanged`, success haptics, the typed
toast, and pending-deletion sync in order. A database failure restores
interaction and emits only error feedback; it does not delete files, publish a
commit event, or enqueue sync.

### Bulk Export OOM Exhaustion (`InsightMediaExportManager` & `PhotoLibraryManager`)

When executing `saveUserMedia()` across the historical file cache and external
Cloudflare URLs, loading via `Data(contentsOf: url)` placed multi-megabyte
uncompressed JPEGs directly into active RAM. For power users running global bulk
exports, this breached iOS memory ceilings and triggered JetSam terminations.

**The Refactor**: `PhotoLibraryManager` now has two scrub paths. In-memory
`Data` payloads still use `CGImageSourceCreateWithData` because the bytes are
already resident. File-backed payloads, however, no longer round-trip through
`Data(contentsOf:)`; GPS stripping streams through `CGImageSourceCreateWithURL`
and `CGImageDestinationCreateWithURL`, producing a temporary scrubbed file that
`PHAssetCreationRequest` imports directly. This removes the worst-case "full
file read + scrubbed copy + PhotoKit copy" triple-buffer spike while preserving
the metadata-scrub guarantee. Video resources stay file-backed from source to
PhotoKit. Automatic capture retains the original until its PhotoKit transaction
finishes; approved cloud Downloads use `URLSession.download` and delete the
temporary file only after the awaited import returns. See
[Camera Roll and Captured-Media Export](../features-and-hardware/27-camera-roll-media-export.md).

This OOM boundary also affected `ScansSheetView` multi-select. Allowing "Select
All" on 2,000 entries would map entirely uncompressed `UIImage` data into the
`UIActivityViewController` sharing array, immediately exceeding available
memory. To prevent this, selections are capped at 20
(`maxBatchSelectionLimit = 20`). Tapping "Select All" filters
`searchManager.filteredScans.prefix(20)`, and manual taps beyond the limit
trigger an `ErrorThump` alert.

### Swift 6 Sendable Violation Crash & Media Export RAM Spikes (`InsightMediaExportManager`)

When executing `batchSaveUserMedia` and `batchShareDiscovery` iteratively,
passing an array of `[LocalScanRecord]` (`@Model` / `@MainActor` bound) directly
into a `Task.detached` closure violated Swift 6 Sendable boundaries, causing
`EXC_BAD_ACCESS` crashes under high load.

## 2. Serverless Edge Token Exhaustion & Race Conditions

### Statement-Level Species Count Serialization (PostgreSQL)

The original scan trigger ran `COUNT(DISTINCT species_id)` over a user's entire
history once for every inserted, updated, or deleted row. Besides quadratic
bulk-write amplification, an owner transfer updated only `NEW.user_id` and could
leave the previous owner's projection stale.

Migration `20260724222838_optimize_species_count_trigger.sql` replaces that path
with the private `internal.user_species_scan_counts` ledger. PostgreSQL
transition tables collapse each SQL statement into net `(user_id, species_id)`
deltas, including OLD and NEW owner/species values. The helper locks affected
user rows in UUID order, changes the public total only when a ledger row crosses
zero, and keeps the ledger, scan mutation, and projection in the same
transaction. Unrelated updates produce an empty net set. The deployment backfill
and trigger swap open one explicit transaction before taking the scan write lock
and commit only after the final trigger exists, so there is no untracked cutover
interval. PostgreSQL requires this explicit boundary for `LOCK TABLE`; the
static migration contract rejects a missing or early commit in this immutable
historical file. It is not a template for new migrations, which rely on Supabase
CLI `2.109.1` to transact the migration and history insert together and must not
add top-level transaction controls.

### Inference Payload Racing (`identify` vs `enrich-scan`)

Historically, the `identify` Deno Edge function attempted to pre-warm the
database by invoking Gemini text-generation (`fetchStaticEncyclopedicData` and
`fetchSimilarSpecies`) concurrently with the primary vision inference inside a
background worker. Because the iOS client natively expects to fetch heavy
supplementary text metadata explicitly via its own `/enrich-scan` API call
during Insight Sheet hydration, the system previously fired dual payloads,
duplicating Gemini AI costs globally across all user scans.

Merian decoupled these capabilities entirely: primary identification executes
through the Gemini 2.5 Flash/Pro inference path (`/identify-multimodal` for
current live and replay submissions, with `/identify` retaining the
image-specific compatibility contract) alongside simple REST data lookups such
as Wikipedia and GBIF identifiers. All heavy diagnostic text footprints and
PostHog metadata (e.g., habitat generation, taxonomic hierarchies, and
`EncyclopedicCost` tracking) are mounted inside the `/enrich-scan` endpoint.
This singularizes token overhead and guarantees a stable event schema for data
warehousing operations.

**The Refactor**: The processing boundary decouples the `@MainActor` SQLite
arrays. `.map` executes on the UI Thread to create lightweight, `Sendable`
structs (`SaveMediaPayload` and `SharePayload`). These pure primitive payloads
then flow through `ExportProcessingActor` and the bounded media pipeline rather
than ad hoc raw detached closures, resolving thread violations and eliminating
crashes.

Loading local file bytes sequentially via `Data(contentsOf:)` and binding
`UIImage(data:)` in batch share arrays bloated uncompressed files into active
RAM. Loading 20 concurrent captures crushed iOS memory limits during
`UIActivityViewController` presentation. Merian replaces this entirely with
`ImageDownsampler.downsample(url: maxSize: 2048)` and
`ImageDownsampler.downsample(data: maxSize: 2048)`, fetching bounded `CGImage`
thumbnails that constrain the memory footprint and enable smooth sheet rendering
wrapped perfectly inside `autoreleasepool`.

### Non-Biological Correction Presentation Boundary

The correction alert retains only the selected scan ID. Confirming
`Reanalyze as biological` does not mutate `LocalScanRecord.isBiological`, save a
model from a presentation closure, or depend on a local query refresh. The
feature view model requests the typed
`AppRoute.refinement(..., entryPoint: .nonBiologicalCorrection)` destination
through its injected routing dependency.

The existing refinement/replacement pipeline refetches the source by ID, stages
bounded original media, and keeps the original non-biological record unchanged
unless a replacement analysis succeeds. This makes durable replacement state,
not an alert-captured model reference or observer side effect, the correction
authority.

### GCD Dispatch Mixed Into Swift Concurrency Contexts

Several sites used `DispatchQueue.main.async` or
`DispatchQueue.main.asyncAfter(deadline:)` inside `@MainActor`-bound or SwiftUI
view contexts, creating subtle ordering hazards:

- **`HapticManager.triggerErrorThump`** (a `@MainActor @Observable` class): The
  follow-up `error.notificationOccurred(.error)` was delayed with
  `DispatchQueue.main.asyncAfter(...+0.1)`. Because the class is already
  `@MainActor`, crossing back through GCD is redundant and can produce ordering
  races if the main run loop is busy. Replaced with
  `Task { @MainActor in try? await Task.sleep(nanoseconds: 100_000_000) ... }`.
- **`InsightSheetView.onAppear`**: The bottom-bar animation was triggered with
  `DispatchQueue.main.asyncAfter(...+0.35)` inside an `.onAppear` closure. This
  was converted to a standalone `.task` modifier. The `.task` version is
  automatically cancelled if the view disappears before the 350 ms delay fires —
  the `asyncAfter` version was not cancellable and would mutate state on a view
  that was no longer on screen.
- **System framework callbacks** (`UNUserNotificationCenter`, `AVCaptureDevice`,
  `PHPhotoLibrary`, `CLLocationManagerDelegate`, `AVCaptureEventInteraction`):
  These APIs call their completion handlers on arbitrary background threads.
  Crossing back to the main thread with `DispatchQueue.main.async { }` is
  replaced throughout with `Task { @MainActor in }`. This keeps all main-actor
  hops within the Swift concurrency runtime, enabling priority inheritance and
  avoiding the GCD/async interop pitfalls documented by SE-0297.
- **`BackgroundTaskWrapper.safeEnd()`**:
  `UIApplication.shared.endBackgroundTask()` requires the main actor. Previously
  used `DispatchQueue.main.async`; replaced with `Task { @MainActor in }` for
  the same reason.

**Rule:** Avoid adding `DispatchQueue.main.async` for actor hopping or
`DispatchQueue.main.asyncAfter` for lifecycle/presentation coordination. Use
`Task { @MainActor in }` for one-shot hops from nonisolated callbacks, and
`.task` modifiers or `await MainActor.run { }` for structured async contexts.
`sinkOnMainActor` deliberately retains `receive(on: DispatchQueue.main)` at
unknown-executor framework boundaries; view-owned `NotificationCenter`
publishers apply the same explicit main-queue delivery before SwiftUI
`.onReceive`. Small UIKit/animation compatibility shims elsewhere are not
evidence that the app event bus should become asynchronously scheduled.

Where lifecycle work has a structured-concurrency owner, keep the hop inside
that task tree so cancellation, ordering, and priority inheritance remain
predictable. Framework publisher bridges retain Combine ordering and explicit
token/cancellable ownership instead.

### SwiftUI Task Cancellation Swallowing

When generating delays such as toast/banner teardown, swallowing
`CancellationError` and then continuing can let an old task clear replacement
state. Auto-dismiss tasks use `do/try/catch`, return from cancellation, and
compare the payload or item identity before mutation. Candidate acknowledgement,
the Field Chat sheet-local `Copied` badge, and note-confirmation delays are
structured `.task(id:)` work, so unmounting their view cancels the timer instead
of retaining its SwiftUI state box. Field Chat copy does not also enqueue a
parent toast. The shared system-toast and milestone overlays occupy distinct
presentation states so only one bottom feedback layer mounts at a time. Feature
animation sleeps that perform no teardown may still use cancellation-tolerant
behavior where explicitly appropriate.

### Owner-Scoped Media Observation

Ad hoc `AVPlayer` notification/KVO/time observers can retain a departed media
surface or deliver a queued callback into a replacement player. Explore public
media, Insight video pages, and fullscreen playback use
`MediaPlaybackObservation`, an `@MainActor @Observable` lifetime owner. It
stores every KVO cancellable, notification token, and periodic-time token;
replacing or detaching a player removes tokens from the exact old player/item.
Callbacks capture owners weakly and verify a generation fence before mutating UI
state. This bounds observer memory and prevents stale end/interruption events
from redrawing a newly mounted page.

System and milestone feedback overlays keep their layout footprint to the
visible banner. `AppDIContainer` owns the sole production milestone presenter,
clock, host registry, and scan coordinator. Its process-local queue is capped at
32 lightweight items, duplicate payloads coalesce to stable identities, and the
stack materializes one payload subtree plus at most two decorative backplates.
The outer overlay animates only visibility, active-item replacement is owned by
the stack, and backing-depth changes are owned by the surface; FIFO mutations
therefore neither allocate a full queued-ID animation key nor drive overlapping
card transitions. A nested feedback host becomes the sole renderer while
mounted; removing it restores the previous host without restarting the active
lifetime or repeating haptic/VoiceOver effects. Account or foreground-timeout
generation changes clear the queue and reject stale async callbacks. The Scans
export state uses a compact pass-through progress capsule instead of a dim
full-screen overlay, while conflicting mutation controls remain disabled. These
boundaries avoid retaining or invalidating a full heavy view tree for ephemeral
feedback.

### Incomplete Gamification UI Animation Thrashing (`AwardCard`)

When rendering large arrays of incomplete offline biological achievements
(`AwardCard`), unconditionally executing `.overlay` `GeometryReader` linear
gradient shaders alongside randomly generated
`.task { while !Task.isCancelled }` animation loops locked `@MainActor`
execution, wasting CPU cycles on badges the user had not unlocked. Merian bounds
both the `.overlay` rendering and the stochastic task generators inside an
explicit `guard award.isCompleted else { return }` check, stopping the OS from
executing animation sweeps on unearned badges.

### UI Thread Blocking (`ProfileView` Exports)

Requesting a Darwin Core Archive (DwC-A) over `/request-export-dwca` performs
only the bounded queue transaction synchronously. That transaction fixes the
eligible scan IDs plus both immutable phase DTOs in one MVCC statement, capped
by the job's canonical row budget plus one lookahead and an aggregate source
byte budget; CSV generation, R2 upload, and email remain on the resumable
`/export-dwca` worker. The request is not assumed to complete within a fixed
sub-100ms latency, so awaiting it on the UI thread would still be incorrect.

`ExportScans` now launches the export request from a structured `Task` owned by
the view lifecycle, keeping `isExporting` on `@MainActor` while the actual
network request runs asynchronously off-thread. Only when the API returns the
`200 OK` queue confirmation does execution update the main-thread toast state,
notifying the user that the request is queued and the archive link will arrive
by email.

The server side is bounded independently of the UI. `export-dwca` registers a
short synchronous phase under a two-minute database lease. Each claim advances
one UUID keyset page, assembles a prepared manifest, or performs delivery. The
minute wake-up executes several such claims sequentially, but starts no new
phase after a 40-second soft cutoff and attempts no more than 40 phases. It
requests five-job oldest-due waves, requeues successful progress behind older
work, and suppresses failed/contended jobs to avoid hot-loop allocation or
provider traffic. Validated row constraints bound media URL and interaction
arrays plus selected taxonomy fields before the read. Job creation materializes
the narrow occurrence and multimedia JSON separately through a parameterized
lateral cursor. UUID membership is counted first; then each row is projected,
measured, and inserted before the next row. Projection stops above the 256 KiB
per-DTO limit or total source limit of four times the archive budget, with a 64
MiB hard cap, and partial rows are removed. This bounds JSON DTO memory and
temporary-sort amplification during rejection. Each claimed page stops at 100
rows or 256 KiB of serialized source. Occurrence DTOs contain no media arrays;
multimedia DTOs contain no taxonomy/coordinates. Both keyset passes traverse the
same immutable rows. Global and non-precise personal occurrence DTOs omit exact
GPS before persistence.

Normal source edits cannot alter immutable DTOs. Page hashes and a full-member
predicate reject deletion or relevant privacy revocation before assembly,
staging, email, and completion; scan/taxonomy triggers persist invalidation. CSV
encoding appends one row at a time into a fixed buffer capped at 512 KiB and
commits it with its cursor and cumulative row/byte budgets. The durable queue,
not one Edge isolate, owns the full database scan.

Assembly lazily GETs the ordered chunk manifest into the ZIP stream and
coalesces only one 8 MiB R2 multipart part at a time. Preparation persists the
CRC-32 for each bounded CSV chunk; assembly composes the ordered checksums
algebraically instead of running an archive-sized JavaScript byte loop, while
still requiring exact manifest byte counts. No full result history, CSV, or ZIP
is retained. Canonical job defaults cap all CSV rows at 5,000 and the final
archive at 8 MiB; database constraints impose 20,000-row and 16 MiB hard
ceilings for reviewed internal jobs. R2 XML and Resend responses are
byte-capped, and multipart completion parses the body so an embedded S3 error
under HTTP 200 cannot be mistaken for a durable archive.

Storage side effects are fenced too: every temporary CSV key includes phase,
sequence, and claim UUID, while an unstaged final object also includes the claim
UUID. SQL accepts only that exact expected key, so a late PUT cannot overwrite
bytes selected by a replacement manifest. After a winning object/URL is staged,
retries reuse it and send Resend's job-scoped idempotency key. This bounds
duplicate work after an Edge restart without pretending the runtime has
unlimited duration. Public callers may queue personal exports only; global
exports remain a reviewed internal workflow.

Processing application capabilities remain in API-inaccessible work state and
are published only with final fenced completion. Each click is
database-rate-limited and reruns the full source fence before a no-store,
30-second read redirect; expired/revoked archives are removed by a durable
claim-fenced cleanup outbox. Fresh-catalog and hosted maximum-shape measurements
remain required promotion evidence in
[`14-dwca-and-public-web-release-hold-2026-07-27.md`](../backend-and-data/14-dwca-and-public-web-release-hold-2026-07-27.md).

### Main Thread Search Thrashing (`ScansLibrarySearchCoordinator`)

When mapping raw SwiftData query results across thousands of user records,
extracting strings synchronously inside `@MainActor` property observers can
cause visible stuttering during library updates. The contained Library search
coordinator splits this work into two paths. Full rebuilds extract
`RawScanSnapshot: Sendable` values from `allScans` on `@MainActor` in 128-record
chunks, yielding between chunks before shipping those plain structs into a
detached utility task for cancellation-aware string and posting-index
construction. Incremental inserts stay inside `SearchDatabaseActor`, which
batch-fetches only the new IDs and appends their `SearchableScan` payloads once
the work completes. The entire sequence is guarded by the coordinator's private
indexing task and generation checks so rapid changes coalesce cleanly and stale
builds cannot overwrite newer snapshots.

### Main-Actor Advanced-Filter Amplification (`ScansLibrarySearchCoordinator`)

The filter sheet and advanced predicates previously repeated several complete
library scans on `@MainActor`: each option dimension rebuilt a normalized
dictionary, each candidate normalized the same selected string sets, and media
and taxonomy predicates dereferenced live SwiftData models. One interaction
therefore generated multiple O(N) passes and substantial short-lived allocation.

`ScanLibraryFilterIndexSnapshot` is rebuilt once per private coordinator
generation. `ScansLibrarySearchCoordinator` extracts `RawScanFilterSnapshot`
values in yielding 128-record batches and sends them to a detached utility task.
That worker constructs:

- one pre-normalized `ScanLibraryFilterDocument` per scan;
- cached display options for tag, hazard, conservation, life-stage, weather, and
  taxonomy dimensions;
- cached category counts and ordering.

Each interaction creates a single `ScanLibraryFilterQuery`, precomputing
normalized selections and lower-inclusive/upper-exclusive date ranges once.
Matching and primitive sorting then execute together in a detached
user-initiated task. Only final ID-to-model materialization and visible-state
commit return to `@MainActor`. The search, filter, and sorted-ID paths all
compare their captured generation before caching or publishing results.

Targeted invalidation also uses compare-safe coalescing. A new
`pendingReindexIDs` set carries every ID owned by a cancelled predecessor into
its replacement task, so rapid A→B notifications cannot leave A removed from the
search snapshot. Custom-tag and Explore share-state changes rebuild the filter
snapshot and rerun the active query.

### SwiftData Fault Caching Thrash (`SearchDatabaseActor`)

While `SearchDatabaseActor.extractSearchablePayloads` insulated the Main Thread,
an older implementation still faulted rows individually. The batch-fetch
refactor now resolves deltas through one
`FetchDescriptor<LocalScanRecord>(predicate: #Predicate { ids.contains($0.id) })`,
which materially lowers SQLite churn and prevents thousands of sequential row
faults on large libraries.

### Batch SQLite Fetch in Search Indexer (`SearchDatabaseActor`)

`SearchDatabaseActor.extractSearchablePayloads` previously accepted
`[PersistentIdentifier]` and called `modelContext.model(for: id)` in a loop — N
individual full-row SQLite faults for a delta of N records. For a cold-launch
rebuild of 5,000 entries this generated 5,000 sequential SQLite reads, pegging
the background actor for hundreds of milliseconds.

The signature was changed to `from ids: [String]` and the loop replaced with a
single batch `FetchDescriptor`:

```swift
var descriptor = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { ids.contains($0.id) })
descriptor.fetchLimit = ids.count
let records = (try? modelContext.fetch(descriptor)) ?? []
let recordMap = Dictionary(uniqueKeysWithValues: records.map { ($0.id, $0) })
```

All N records are fetched in one SQL `SELECT ... WHERE id IN (...)` call. A
dictionary lookup restores original ID order before mapping to `SearchableScan`
structs. Callers were updated to pass `.map { $0.id }` instead of
`.map { $0.persistentModelID }` — keeping the string ID on the main actor rather
than crossing the persistence stack to retrieve an opaque
`PersistentIdentifier`.

### O(N) CPU Indexing Thrash (`ScansLibrarySearchCoordinator`)

Updating or deleting a single record previously triggered the `allScans`
observer to wipe the entire multi-index tracking string and pass the full array
into `SearchDatabaseActor` for re-evaluation of 5,000+ elements sequentially,
pegging the CPU.

**The Refactor**: The global array re-indexing loop was removed.
`ScansLibrarySearchCoordinator.updateSearchableData` uses a `Set`-based delta
update. Deleted records invoke `.removeAll { ... }` directly against the
discrete array without touching the background processing thread. Newly captured
records jump the background worker queue, incrementally appending only the new
entries onto `@MainActor`.

- **Hot-Swap Updates (Custom Tags)**: Because `Set`-based ID diffing inherently
  ignores internal property mutations on existing scans, updates to fields like
  `customTags` emit the typed, loss-tolerant
  `AppEvent.scanSearchIndexInvalidated(scanId:)`. `ScansManager` receives that
  main-actor invalidation and asks its contained coordinator to isolate the
  single durable scan ID and hot-swap only that scan's indexed search payload
  through `SearchDatabaseActor`. SwiftData remains authoritative; no
  application-defined `Notification.Name` is involved.
- **Initial Rebuild Double-Fetch Elimination**: The full-rebuild branch in
  `updateSearchableData` previously performed two sequential SwiftData fetches —
  one on `@MainActor` (via `allScans`) and one inside `SearchDatabaseActor` to
  materialise the same records a second time for index construction. Because
  `LocalScanRecord` is a SwiftData `@Model` (non-`Sendable`), it cannot cross
  actor boundaries directly. The fix introduces `RawScanSnapshot: Sendable` — a
  plain struct mirroring all 21 `LocalScanRecord` fields — extracted on
  `@MainActor` from the in-memory `allScans` array in yielding chunks, then
  passed into a `Task.detached` that constructs the full `SearchIndexSnapshot`.
  Its pure builder calls
  `SearchDatabaseActor.buildSearchablePayloads(from: [RawScanSnapshot])` (a
  `static` method requiring no `ModelContext` fetch) before constructing the
  exact-term and n-gram posting lists in the same worker. This eliminates the
  redundant SQL `SELECT` and main-actor posting-index build without monopolizing
  the UI during very large initial libraries.
- **`forceReindex` Task Coalescing**: `forceReindex` stores its task in
  `indexingTask`, but cancellation alone is insufficient because the cancelled
  worker may already own an ID. `pendingReindexIDs` is unioned into every
  replacement extraction and cleared only after a generation-checked upsert.
  Rapid successive updates therefore cannot duplicate documents or strand a
  superseded document outside the index.
- **Search-time cache reuse**: Query execution now reuses `[String: Int]`,
  `[String: LocalScanRecord]`, and `[String: ScanSortPrimitive]` caches built
  from the already-resident `allScans` array when it changes. This removes the
  old per-keystroke `[id: LocalScanRecord]` rebuild and the old
  `allScans.first(where:)` fallback without issuing any additional SwiftData
  fetch.

### UI Body Array Calculations (`UserStats` & Contribution Heatmap)

Executing heavy O(N) array manipulations (such as
`Set(allRecords.map { ... }).count` or `Calendar` date-normalization for a
52-week heatmap) directly inside a SwiftUI `var body: some View` forces the Main
Thread to re-evaluate the math on every `@Query` binding update. For Pro users
with 5,000+ captures, this causes stuttering during Profile scrolls. Merian
moves this work off-thread:

- `ProfileDatabaseActor` isolates unique species mapping and the 52-week
  `ProfileHeatmapData` generation inside `@ModelActor`, executing the calendar
  loops off-thread. `NumberFormatter` and `Calendar` loops are removed from
  `ScansHeatmap`'s body; `currentMonthCaptures` is processed inside
  `ProfileDatabaseActor`, producing an O(1) render value on the UI thread.
- Profile stats, heatmap generation, and award calculation now share one compact
  `ProfileStatsProjection` cache made from `propertiesToFetch` scalar columns.
  The actor stores only `Sendable` projection structs, precomputed timestamps,
  and the unique-species count; it never caches live `LocalScanRecord` model
  objects or media blobs.
- The projection cache is guarded by a cheap fingerprint (`recordCount`, latest
  scan ID, latest timestamp). Inserts, deletes, and latest-scan changes refresh
  the projection automatically; callers that mutate existing records in place
  must invalidate before requesting cached profile stats. The post-inference
  `calculateAwards()` path invalidates automatically, and its long-lived actor
  is reused only for the same `ModelContainer` identity.
- Results are packaged as flat `Sendable` configurations before updating
  lightweight `@State` primitives on the `@MainActor`, insulating `ScansHeatmap`
  from any O(N) loop dependencies.
- **View Graph Explosion Protection**: Dense inner views evaluating 364+ element
  block grids in `ScansHeatmap` were migrated to `LazyHStack` bindings,
  preventing massive node instantiations across the `ScrollView` and limiting
  rendering to on-screen elements only.

### Edge Geometry Observers (`FadingScrollView`)

When masking a `ScrollView` with dynamic fade overlays that evaluate scroll
position, combining `PreferenceKey` emission tracking with
`.defaultScrollAnchor(.trailing)` layouts fails on iOS 17. The preference change
resolution is silently dropped during the initial structural anchoring sweep,
permanently freezing geometric tracking variables at `0`. In the `ScansHeatmap`
contribution graph, Merian abandons all `PreferenceKey` protocol loops.

- `FadingScrollView` bypasses this by adopting
  `.onChange(of: geo.frame(in: .named("FadingScrollSpace")).minX, initial: true)`,
  observing geometric measurements directly inside the view-closure block rather
  than delegating across the UI bound tree.
- This triggers alongside the UI layout, allowing `offset` evaluations to mutate
  `LinearGradient` mask bounds correctly without dropping updates across the
  trailing anchor layout.

### Concurrent Environment Context Fetch (`EnvironmentContextManager`)

In `fetchDeferredContext`, reverse geocoding (`reverseGeocode(location:)`) and
weather fetching (`weatherService.weather(for:)`) were previously sequential
`await` calls. Since these are independent network I/O operations — typically
300–800 ms each — sequential execution added 300–1000 ms of unnecessary latency
to every shutter press.

`reverseGeocode` is now launched as an `async let` child task before
`weatherService.weather(for:)` begins on the main task. Both operations run in
parallel. The geocode result is `await`-ed when constructing the
`EnvironmentContext` return value — at which point it is almost always already
resolved. The pattern also handles the failure case correctly: if weather
throws, `await locationName` in the `catch` block retrieves the geocode result
(which ran concurrently and is ready) without re-fetching.

### Apple Geocoder Rate Limiting (`EnvironmentContextManager`)

Invoking `CLGeocoder().reverseGeocodeLocation` on every historical index
directly triggers Apple server rate limits. Rapid bulk photo imports fire
`CLError.network` suspensions resulting in hours of stranded metadata. Merian
abstracts the geocoder loop with a RAM-based LRU coordinate cache, rounding hash
precision to 111 meters (`%.3f,%.3f`). Location patterns clustering on the same
coordinates resolve from cache without touching the device radio, and offline
synchronizations skip the server check entirely.

### Deferred Location Timeouts (`EnvironmentContextManager`)

Unconditionally calling `timeoutTask?.cancel()` in debounced functions like
`requestSingleLocation()` caused starvation. If the user tapped the shutter
rapidly, the timeout task was deferred indefinitely, growing the
`activeContinuations` array and permanently hanging the camera shutter pipeline.
Merian resolves this: the timeout task is now instantiated only if one is not
already running, allowing existing tasks to fire and flush. Active continuations
are cancelled inside `locationManager(_:didUpdateLocations:)` and
`didFailWithError`, enforcing limits on resolution latency.

### Battery-Bounded Location Accuracy (`EnvironmentContextManager`)

The camera viewport no longer keeps CoreLocation pinned at
`kCLLocationAccuracyBest` while the user is composing. Live tracking uses
`kCLLocationAccuracyHundredMeters`, a 100 m distance filter, and automatic
pausing so the device can maintain a macro-region fallback without continuously
driving GPS at full power. `startUpdatingHeading()` is not called because
compass heading was removed from the inference telemetry payload.

When the shutter fires, `CaptureWorkspaceViewModel.executeCapture` starts
`requestCurrentLocation()` concurrently with `CameraManager.captureImage()`.
That one-shot request temporarily raises `desiredAccuracy` to
`kCLLocationAccuracyBest`, calls `requestLocation()`, and then restores the
coarse composing profile after all pending continuations resolve. The resolved
shutter fix is used for the Photos asset location and deferred
WeatherKit/geocode context; if it times out, `lastKnownLocation` still provides
the latest coarse fallback.

### Synchronous SQLite on the Launch Path (`ScanRepository`)

`ScanRepository.configure(with:)` was called synchronously during app setup and
performed a `FetchDescriptor<ScanCollection>()` fetch — loading every
`ScanCollection` record with every stored property — to check whether a
"Favorites" collection existed. On large libraries with many collections, this
blocked the main thread before the first frame rendered.

Two fixes were applied together:

1. **Async deferral**: `configure` now returns immediately after injecting the
   queue context. The Favorites check runs inside `Task { @MainActor in }`,
   yielding the current synchronous callsite and running on the next main actor
   iteration.
2. **O(1) fetch**: The full collection fetch was replaced with
   `modelContext.fetchCount(descriptor)` where `descriptor` uses
   `#Predicate { $0.name == "Favorites" }` and `fetchLimit = 1`. SQLite
   evaluates this as a `SELECT COUNT(*) WHERE name = 'Favorites' LIMIT 1` —
   constant time regardless of library size.

### Bounded SwiftData Startup (`MerianApp`)

`MerianApp` still creates the app-wide `ModelContainer` during startup so the
root SwiftUI environment, repository wiring, and safe-mode state are known
before user workflows begin. The launch path must therefore avoid unnecessary
deep migration validation. Startup reads the store metadata first: fresh/current
stores open without a migration plan, known recent stores use the narrow
source-isolated V49/V48/V47/V46/V45/V44/V43/V42 plans, and unknown older stores
use the full historical migration plan. V49 uses the one required lightweight
V49→V50 hop, while V50 is current and opens without a plan. The full plan
remains linear through V42→V49→V50 so older-store migration does not validate
the duplicate-prone V43...V48 source cluster. V42/V43 use short direct plans to
avoid validating older full-historical custom stages that can raise SwiftData's
equal-model-reference exception. The V46 plan keeps V46 as the only
duplicate-cluster source representative and jumps directly to V49 because V46
was a shipped no-op schema, while true V47 stores use a source-isolated V47→V49
plan with a self-contained scalar queued-scan snapshot. Every chosen older lane
then uses V49→V50; current V50 stores open without migration. Duplicate-checksum
failures retry through the same recent-plan ladder, ordered current store then
V49 down through V42, before legacy rescue or safe mode. Supported recent
sources are a finite enum ending at the immediate predecessor of
`CurrentSchema`, and app dispatch is compiler-exhaustive with no full-history
default. This keeps the synchronous launch boundary bounded for normal upgrades
while preserving a deterministic recovery surface if SwiftData cannot open the
store.

### App Boot SDK Stutter (`MerianApp`)

Deferring external SDK boot sequences via `DispatchQueue.main.asyncAfter` caused
a UI hitch milliseconds after `CaptureWorkspaceView` finished rendering. Merian
avoids delayed startup jolts by preparing only a disabled first-party analytics
facade in the launch path. The required contract forbids PostHog configuration
until `ConsentManager` resolves an explicit grant for the active account;
absence, withdrawal, or account change must keep capture off and close the SDK
without a new request. The current withdrawal and account-transition paths are
release-blocked in the
[production consent readiness record](../legal/production-consent-readiness-2026-08-03.md).
Heavy hardware work remains outside the critical render path.

### Accelerate Vector Optimizations (`CameraManager`)

Calculating target Luma brightness by looping through `CVPixelBuffer` matrix
addresses byte-by-byte (`totalLuma += UInt64(buffer[rowOffset + x])`) pegs the
processor inside the 60fps capture loop, provoking thermal throttling in outdoor
environments. Merian optimizes this calculation via Apple's Accelerate
framework. Using `vImage_Buffer` alongside `vImageHistogramCalculation_Planar8`,
execution drops from milliseconds to microseconds.

**The Refactor**: The previous `vImage` logic parked a single
`nonisolated(unsafe)` buffer atop the class, violating Swift 6 memory bounds and
causing pointer tearing inside the `captureOutput` loop. That global cache
object was removed. The system now allocates a lightweight local array inside
the inner loop scope:
`var histogram = [vImagePixelCount](repeating: 0, count: 256)`. It instantiates
locally 60 times per second and deallocates with ARC, enforcing thread-safe
memory isolation and satisfying Swift 6 compilation checks.

The same histogram loop also derives `lumaStdDev` (standard deviation of the
luma distribution, 0–255 scale) by accumulating `totalLumaSq` alongside
`totalLuma` — `stdDev = sqrt(E[X²] - E[X]²)`. This adds no extra vImage passes
and negligible CPU cost. `lumaStdDev` is forwarded to `ViewfinderIntelligence`
as a sharpness proxy: low variance indicates motion blur or a featureless frame.

### Hardware Concurrency Defenses (`OSAllocatedUnfairLock`)

When tracking asynchronous camera shutter continuations across multiple thread
boundaries sharing identical payload dictionaries, wrapping standard
dictionaries in generic arrays violates Swift 6 memory protections.

**The Refactor**: Instead of using older Objective-C mechanisms like `NSLock()`,
Merian adopts the low-overhead Swift `OSAllocatedUnfairLock` wrapper struct
inside `CameraManager`. Wrapping tracking tuples
(`let requestsLock = OSAllocatedUnfairLock()`) shields Apple hardware callbacks
executing across thread boundaries, removing Thread-Sanitizer execution halts.

### Bridging RAM Leaks (`ImageCropProcessor` & `LocalImageLoader`)

When capturing full-resolution Apple ProRAW or high-megapixel `AVCapturePhoto`
assets, translating view coordinates into geometric grid slices forces large
temporary memory allocations. Drawing a 12–48 MP uncompressed bitmap into
`UIGraphicsImageRenderer` to produce a 1024×1024 output causes memory spikes
(~50 MB+) that trigger JetSam terminations on older hardware. Merian abandons
intermediate bitmaps and uses Apple's C `ImageIO` framework
(`CGImageDestination`). It writes the `cgImg.cropping(to: cropRect)` result
directly into a binary WebP `Data` buffer using
`kCGImageDestinationImageMaxPixelSize: 1024` and `kCGImagePropertyOrientation`
option dictionaries, bypassing RAM bloat. This also enables
`generateAutoCenterCrop(image:)`, a 1:1 auto-center square pipeline writing
bytes off the Main Thread, preserving 60/120Hz viewfinder latency during rapid
multi-capture bursts.

`ImageCropProcessor` consolidates the repeated
`CGImageDestination → NSMutableData → Data` pattern into a single
`static nonisolated func encode(_ cgImage:, quality:, orientation:, maxPixelSize:) -> Data?`
helper. The helper wraps its work in its own `autoreleasepool`, attempts WebP
encoding first (`UTType.webP`), and falls back to JPEG (`UTType.jpeg`)
transparently. All three call sites — `generateCrop`, `generateAutoCenterCrop`,
and `Capture.swift`'s inference/display payload construction — delegate to this
shared encoder, eliminating duplicated encoding blocks and ensuring consistent
`autoreleasepool` bounding across the pipeline.

Extracting the binary payload back out of
`autoreleasepool { ... return renderData }` previously caused bridging RAM leaks
where Swift retained `NSMutableData` references indefinitely. The architecture
resolves this by returning `Data(renderData)`, forcing an immutable copy that
allows the mutable render buffer to deallocate immediately.

Using `image.jpegData(compressionQuality: 0.7)` as a fallback encoding path tied
the uncompressed render operation to the SwiftUI `@MainActor` thread, generating
UI stutters and OOM Watchdog terminations. Merian removes `.jpegData` hooks and
routes the fallback encoding inside the `.detached` background closure, bounding
the unscaled `cgImg` buffer via `CGImageDestination`.

Within `LocalImageLoader`, fetching raw binary buffers over the network
previously used `UIImage(data: data)?.preparingThumbnail(...)` as a fallback if
`ImageDownsampler` returned `nil`. This violates the Zero-OOM architecture
because `UIImage` loaded directly from raw uncompressed data expands 48 MP byte
payloads into active RAM instantly. Merian enforces CoreGraphics bounds: if
`ImageDownsampler.downsample` returns `nil`, the pipeline returns `nil` and
abandons the raw RAM instantiation.

### SSD Download Streaming (`LocalImageLoader`)

When grid interfaces ingest hundreds of locally un-cached remote images,
`URLSession.shared.data(from:)` caused RAM inflation by loading multi-megabyte
blobs directly into system memory. Merian replaces `.data(from:)` with
`.download(from:)`. The network payload streams into an ephemeral file URL on
the SSD, which is passed directly to
`ImageDownsampler.downsample(url:maxSize:)`. The temporary URL is deleted inside
a `defer` block, preventing JetSam memory spikes and ensuring no raw image data
touches RAM before downsampling.

### Unbounded RAM Blob Accumulation (`SimilarSpeciesImageFetcher`)

When querying encyclopedia assets for the Similar Species/Candidate gallery,
relying on raw `URLSession.shared.data` loops inside detached utility tasks
bypassed all Zero-OOM guardrails. Passing raw network `data` arrays into
`UIImage(data:)` spawned heavy uncompressed RAM bitmaps outside
`autoreleasepool` contexts, increasing the risk of iOS background application
terminations. Also, retaining these large uncompressed bitmaps through
`NSCache<NSString, UIImage>` generated permanent unbounded memory leaks.

**The Refactor**: The layer strips custom parsing and cache dictionaries. After
extracting dynamic Wikipedia and GBIF remote URLs off-thread,
`SimilarSpeciesImageFetcher` explicitly pipes an array of fallback URL strings
concurrently via `TaskGroup` into
`LocalImageLoader.shared.loadImage(fallbackUrl:)`. This offloads the heavy
lifting natively, forcing OS APFS caching limits and bounding `CGImageSource`
instantiations dynamically inside `ImageDownsampler`, appending images
dynamically into an array.

### Swift 6 Primitive Extraction (`ImageCropProcessor`)

Passing `UIImage` objects directly into `Task.detached` closures violates Swift
6 strict concurrency rules because `UIImage` is non-Sendable and unsafe to cross
actor boundaries. Merian prevents these traps by extracting thread-safe
primitives (`targetImage.cgImage` and `targetImage.imageOrientation`) on the
`@MainActor` before the detached task. These primitives are passed into the
background processing pool for downsampling without triggering compiler warnings
or runtime data races.

### Sequential CPU Starvation (`Capture.swift`)

When submitting a multi-capture payload (e.g. multiple 12 MP captures)
sequentially, `await`-ing `ImageCropProcessor.generateAutoCenterCrop(image:)`
inside a standard `for` loop forces iOS to compute each crop on a single core,
multiplying UI analysis latency.

**The Refactor**: Multi-capture evaluation runs inside a concurrent
`withTaskGroup`, scheduling individual media transformations across separate
hardware cores simultaneously. Sequential latency is eliminated during critical
capture bursts.

### Massive Payload RAM Bypass (`PhotosPickerItem`)

To avoid JetSam OOM terminations when parsing large 48 MP ProRAW/HEIC payloads
from the Camera Roll, Merian drops standard `.loadTransferable(type: Data.self)`
memory reads. Standard payload expansion crashes foreground apps because the OS
dumps the entire raw array into the CPU cache. Instead, the application uses an
internal Swift struct (`ImageFileWrapper: Transferable`) with
`FileRepresentation`, instructing Apple's `PhotosUI` pipeline to write bytes
into a sandboxed `temporaryDirectory`. Calling
`loadTransferable(type: ImageFileWrapper.self)` streams the payload under the
RAM layer, allowing `.downsample(url:)` to map memory directly from the SSD.

Gallery, Photos document-import, refinement, and avatar preview paths now pass
file URLs through `MediaPreparationActor` before constructing any `UIImage`. The
external import store copies the source file but never decodes it; ImageIO
extracts the small metadata dictionary before bounded preparation.
`StagedImage.displayData` is always a 2048 px re-encoded display payload, never
the original mapped file bytes. The actor records `MediaPreparationMetrics` for
output byte counts and pixel dimensions, and rejects any prepared still image
that exceeds `MerianConfig.stagedImagePayloadMaxBytes`,
`MerianConfig.inferenceImageMaxSize(isProActive:)`, or
`MerianConfig.displayImageMaxSize`. The profile avatar crop preview uses
`preparePreviewImage(fileURL:maxSize:)` and constructs `UIImage(cgImage:)` back
on `@MainActor`; direct `UIImage(contentsOfFile:)` reads are not permitted for
user-selected originals.

### AVFoundation Sample Buffer Lifetime (`Capture.swift`)

Short video scans can extract a companion WAV through `AVAssetReader` /
`AVAssetWriter`. Each `trackOutput.copyNextSampleBuffer()` result is wrapped in
a per-sample `autoreleasepool` and invalidated with `CMSampleBufferInvalidate`
after `writerInput.append(...)`. This keeps native CoreMedia buffers bounded
during the copy loop and prevents AVFoundation sample objects from accumulating
until the whole extraction finishes.

### File System Sandboxing Limits (`LocalImageLoader`)

When grid interfaces ingest hundreds of locally un-cached APFS identifiers,
executing synchronous `FileManager` and `UIImage(contentsOfFile:)` loads
stutters the main thread and trips OS memory caps. Merian abstracts this through
the isolated `LocalImageLoader` actor. It manages multi-tier RAM lookups and
detached request coalescing, then admits `ImageDownsampler.downsample()` work
through the asynchronous four-permit pool onto the dedicated ImageIO queue.
Uncached `CGImageSourceCreateWithURL` fallback loads are removed, forcing the OS
to honor `[kCGImageSourceShouldCache: false]` and CGImageSource size scaling,
protecting device RAM.

The loader also implements local recovery plus a recursive network fallback
pipeline. For an eligible durable R2 URL, `LocalImageLoader` first asks
`LocalScanMediaRecoveryResolver` for a strongly matched surviving Documents
file. A local hit renders immediately and queues owner-authenticated cloud
inspection/repair. Without a local hit, the loader splits aggregated
`fallbackUrl` values and cascades through permitted R2, Wikipedia, and GBIF URLs
sequentially. A terminal failure displays the “Visuals archived” placeholder
without spinning, but that label is a presentation fallback—not an R2 archive
class. Recovery matching, one-to-one timestamp constraints, and atomic
Scan/Explore repair are defined in
[`03-image-pipeline.md`](./03-image-pipeline.md).

The loader protects against "thundering herd" memory leaks. If the UI queries a
missing image URL before cache limits evaluate, it tracks in-flight executions
inside an `[String: Task<UIImage?, Never>]` dictionary, reducing duplicate loads
to a single instance. To address an actor reentrancy vulnerability at the
`await` suspension point, `LocalImageLoader` checks
`if activeTasks[cacheKey] == fetchTask` inside its teardown `defer` block,
ensuring concurrent task overwrites cannot cause an earlier task to wipe a newer
active network request from the dictionary. `loadImage` returns `nil` when path
strings are empty, rather than binding fresh `UUID` strings that previously
bypassed cache logic and inflated `NSCache` allocations indefinitely.

**Actor Re-Entrancy Elimination**: The I/O helpers (`loadLocal` and
`fetchRemote`) are declared `static nonisolated` rather than instance methods. A
`Task.detached` body calling an actor instance method would re-serialize all
execution through the actor's executor, defeating the purpose of detachment.
Promoting these to statics keeps network orchestration off the actor executor,
while the asynchronous permit pool and dedicated decode queue own synchronous
ImageIO admission and execution.

### Task Capture Retain Cycles (`EnvironmentContextManager` and Scans search)

When firing background `@MainActor` executions inside persistent managers (like
`reverseGeocode` or `performSearch`), default `Task { ... }` or
`Task.detached { ... }` blocks implicitly capture `self` via a strong reference.
When a `Task` mutates a local property (e.g., `self.geocodeCache[key]`) and is
retained by the class (e.g., `self.searchTask = task`), this creates a retain
cycle, permanently locking memory inside zombie ViewModels.

**The Refactor**: The codebase captures `[weak self]` inside `Task` /
`Task.detached` closures, dropping the strong pointer. A
`guard let self = self else { return }` check precedes any variable mutation,
allowing Swift garbage collection to purge mapping classes upon background
termination. The Scans Library now contains `searchTask` and the related index
tasks inside `ScansLibrarySearchCoordinator`; every stored task captures that
owner weakly. `EnvironmentContextManager` asynchronously created CoreLocation
delegates generated the same runaway cross-actor memory risk without closure
guard isolation. These closures extract lightweight parameters outside the
suspending boundary before accessing `@MainActor` variables locally.

### Sync Pipeline State Machine (`SyncStateManager`)

The original `SyncStateManager` used two independent properties
(`isSyncing: Bool`, `pendingUploadCount: Int`) to represent upload progress,
making it impossible to distinguish between uploading, inferencing, and
finalizing phases — all of which appear "in progress" to the UI but have
meaningfully different durations and semantics.

`SyncStateManager` was refactored to replace these with an exhaustive
`SyncPhase` enum:

```swift
enum SyncPhase: Equatable {
    case idle
    case uploading(count: Int)   // PUT requests in flight to R2 staging
    case inferencing             // Gemini Edge function running
    case finalizing              // Writing LocalScanRecord, deleting OfflineQueuedScan
}
```

`OfflineQueueManager` transitions the phase at each boundary:

- `beginSync(itemCount:generation:)` registers one upload batch UUID and exposes
  `.uploading(count:)`.
- `beginInferencing(generation:)` idempotently registers the scan generation
  before request preparation can suspend.
- `beginFinalizing(generation:)` advances only that registered inference token.
- `completeSync(generation:)` removes only the matching inference token.
  Unknown, retired, or already-completed UUIDs are no-ops.
- `completeUploadPhase(generation:)` removes only the matching upload batch.
- `forceIdle()` invalidates the current upload and all inference tokens. It is
  used on connectivity loss; a late completion from before the reset cannot
  decrement or clear work registered afterward.

The manager stores one `UploadActivity(generation,itemCount)` and an
`[UUID: InferenceActivity]` map instead of an integer inference count. Phase
selection is deterministic: any finalizer wins, then any inferencer, then the
upload batch, otherwise idle. Exact-token removal eliminates the count-reset
race where a late generation-A completion could decrement generation B after a
forced reset.

Computed shims (`isSyncing: Bool { phase.isActive }` and
`pendingUploadCount: Int`) preserve backward compatibility for existing UI
components.

### Offline Retry ABA Protection (`OfflineQueueManager`)

Swift task cancellation is cooperative. Removing or cancelling a task handle
does not prove that its body will never resume after the next suspension point.
All replaceable offline-sync work therefore follows two ownership rules:

1. **Operation generation** identifies the upload batch or inference attempt
   allowed to mutate domain state. New upload descriptions use
   `upload_v2|ownerUUID|scanId|uploadIndex|generation|serverObjectKey`; new
   inference descriptions use `inference_v3|ownerUUID|generation|scanId`.
   URLSession callbacks parse and carry the durable account owner and generation
   through result, failure, retry, cancellation, and deletion paths. The exact
   server-issued key also fences upload completion against auth/device identity
   drift.
2. **Registry token** identifies the current delayed task occupying a per-scan
   slot. `GenerationTaskRegistry.replace` removes the old entry before
   cancelling it, installs a fresh UUID, and exposes `isCurrent` /
   `clearIfCurrent`. A resumed old probe, server poll, or retry task cannot
   clear or execute the replacement. Probes and server polls keep their slot
   while awaited recovery/cancellation/database work runs and revalidate it
   after each suspension; clearing the slot before beginning that work would
   recreate the same ABA window.

Inference preparation is single-flight and its UUID becomes the URLSession
generation before status probing or request construction awaits. Upload
completion has a separate token per callback until it hands ownership to that
preparation; removing one token cannot hide another callback for the same
multi-file scan. The latest successfully claimed upload generation remains
recorded per scan after preparation, so a delayed generation-A callback stays
invalid even after replacement B has finished. Background expiration captures
the upload UUID and uses `finishUploadSync(generation:)`; it never writes the
global latch directly.

Any inference-driven queue deletion carries an `InferenceGenerationExpectation`.
`deleteQueuedScan` checks it both before and after
`await backgroundSession.allTasks`; server-poll recovery additionally carries
the exact poll-slot token through that boundary. It then performs cancellation
and SwiftData deletion without another ownership gap. Result finalization also
rechecks the inference generation after the background actor save and before
post-finalization job/UI side effects. This compare-after-await is required:
checking only before URLSession enumeration would leave an ABA window in which a
replacement could start and then be cancelled by the old deleter. Explicit user
deletion intentionally omits the expectation because the requested outcome is to
cancel every generation.

Connectivity loss cancels the registries, retires active inference UUIDs,
invalidates preparation slots, removes preparation entries belonging to the
current upload batch, and force-resets UI tokens. Durable SwiftData states and
URLSession enumeration remain the restart/reconnect recovery source; in-memory
generations are only the callback fence.

Queue-backed foreground inference follows the same rule with a
`ForegroundInferenceGenerationExpectation`. Submission creates the generation
before enqueue and stores it in `OfflineJobRecord.metadataJSON` in the same save
as `OfflineQueuedScan`; the in-memory dictionary is registered before sync or
replay can start. `InferenceEngine` captures that generation rather than using
only `activeScanId`, checks it at task entry, after external suspension points,
immediately before provider dispatch, and at every side-effect boundary, and
supplies a `LiveInferencePersistenceFence` to the database actor.
`OfflineQueueManager` atomically consumes the generation before provider
dispatch, making duplicate starts no-ops across engine instances. Cancellation
and pre-provider exits register a tokenized retirement task synchronously before
durable handoff begins. Registration immediately makes the attempt non-current
for persistence, UI publication, and queue cleanup, even while its raw durable
UUID remains present. Retirement retries transient durable-owner fetch/save
failures with bounded backoff while retaining the marker, so the system neither
admits a callback- equivalent replacement nor strands the queue behind an
abandoned claim.

Error presentation is a generation-owned commit, not harmless cleanup. A failure
handler snapshots the full scan, presentation-attempt, and foreground generation
match before synchronously registering retirement. Only that owner may emit
failure telemetry, update the circuit breaker, trigger a haptic, or publish an
error placeholder, with no suspension between the snapshot and terminal commit.
A stale or cooperatively cancelled task performs none of those effects.

Live persistence acquires `ScanInferencePersistenceCoordinator`, validates both
the durable job generation, MainActor owner, and echoed result scan ID, and
retains the coordinator through `ScanFinalizationCoordinator` and the SwiftData
save. Queue cleanup retains the same per-scan coordinator across URLSession
enumeration, cancellation, and deletion, then compares the foreground generation
again before clearing ownership. If attempt A resumes after replacement B, A
cannot save, publish UI, cancel B's retry/URLSession work, or delete B's queued
row. An ownership fetch error fails closed instead of masquerading as a deleted
job. Only explicit user/system deletion intentionally omits a generation fence.

Upload claims, inference claims, retries, and both orphan reconcilers use one
long-lived `BackgroundDatabaseActor`. Before a reconciler enumerates URLSession
tasks it captures an `observedThrough` cutoff. The actor resets only rows whose
`queueUpdatedAt` is at or before that snapshot; a replacement claim queued while
reconciliation is suspended is therefore ordered on the same actor and excluded
as newer work.

The inference generation is also a persistence fence. The winning
`.staged → .inferencing` save writes `{"inference_generation":"{uuid}"}` to the
scan-ingestion `OfflineJobRecord.metadataJSON`.
`ScanInferencePersistenceCoordinator` serializes per-scan claims, retries,
finalization, and guarded deletion across independent SwiftData contexts. Retry
accounting and retreat to `.staged` compare that exact metadata before saving.
Result persistence and queue deletion likewise validate the durable UUID while
holding the coordinator; the deletion path keeps ownership across URLSession
cancellation and the main-context save. This prevents a stale process-local
callback from mutating a replacement even at the database boundary. Legacy
in-flight work can populate only `nil` metadata once during upgrade; a non-`nil`
generation is never adopted or replaced by a delayed callback.

### Centralized Magic Numbers (`MerianConfig`)

Batch sizes, fetch limits, pagination page sizes, and retention windows were
previously scattered as literals across `OfflineQueueManager`, `ScanRepository`,
and `BackgroundDatabaseActor`. Divergence between these call sites introduced
silent bugs (e.g., a fetch limit of 50 and a batch limit of 5 in different files
with no linking comment).

All policy constants are now consolidated in `MerianConfig.swift`
(Core/Utilities/):

```swift
enum MerianConfig {
    static let uploadBatchSize              = 5
    static let pendingScanFetchLimit        = 50
    static let historicalSyncPageSize       = 200
    static let collectionsSyncPageSize      = 100
    static let ingestCheckpointInterval     = 100
}
```

`OfflineQueueManager+Sync` and `ScanRepository` reference these constants
exclusively. Tuning any policy requires a change in exactly one place.

### Transactional Scan Deletion (`eradicateScan`)

The original `eradicateScan` deleted image files from disk before committing the
SwiftData changes. A save failure after file deletion left the `LocalScanRecord`
intact in the database while its images were gone — a permanently broken state.

The operation was restructured to be database-first:

1. Tombstone any in-flight upload (`softDeleteQueuedScan`).
2. Insert `PendingCloudDeletionTask` + `modelContext.delete(record)`.
3. `modelContext.save()` — **if this fails, rollback and return immediately
   without touching disk**. State is fully consistent.
4. Only after a successful save: `FileIOActor.shared.deleteImages(at:)`
   asynchronously purges local `.jpg` files. Remote R2 URLs are skipped (they
   are not locally owned).

This ensures a save failure can never produce a state where the record exists
but its images are missing.

### Historical Sync OOM Prevention — Page-at-a-Time Streaming (`ScanRepository`)

The previous `syncHistoricalScansDown` accumulated all cloud scan pages into a
single `allScans: [HistoricalScanResponse]` array before any reconciliation
began. At 10 k+ scans this buffer grows to 100 MB+ of decoded Swift structs on
the `@MainActor` heap and triggers JetSam OOM kills on devices with limited RAM.

The fix streams pages one at a time: each fetched page is passed immediately to
`HistoricalDatabaseActor.reconcileScanPage(responses:)` and released before the
next network request begins. In-memory scan accumulation is now O(page_size) —
always 200 records — regardless of how large the user's library grows.

```swift
let dbActor = HistoricalDatabaseActor(modelContainer: container)
var scanOffset = 0
while true {
    let page: [HistoricalScanResponse] = try await ...
        .range(from: scanOffset, to: scanOffset + pageSize - 1).execute().value
    if !page.isEmpty {
        await dbActor.reconcileScanPage(responses: page)
    }
    if page.count < pageSize { break }
    scanOffset += pageSize
}
await dbActor.syncCollectionsDown(remoteCollections: allCollections)
```

Inside `reconcileScanPage`, the existence check uses a chunked `FetchDescriptor`
with `propertiesToFetch = [\.id]` — a narrow ID-only column projection scoped to
each page's incoming IDs. The set is computed fresh per call; no cross-call
caching is used so there is no stale-ID risk across pages.

### Chunk-Process-Save Pattern (`HistoricalDatabaseActor.updateExistingScans`)

`updateExistingScans` must reconcile existing local records against a page of
incoming cloud responses. Two constraints apply simultaneously:

1. **IN-clause planner degradation**: A single
   `#Predicate { responseIds.contains($0.id) }` with hundreds of IDs causes
   SQLite to abandon the primary-key index above a threshold and fall back to a
   full table scan.
2. **Peak heap accumulation**: Fetching all matching records across chunks into
   a shared `allExistingScans` array before iterating holds the entire page's
   worth of fully-faulted `LocalScanRecord` objects in RAM at once — up to 500
   heavy ORM objects simultaneously.

The fix addresses both with a **chunk-process-save** loop: for each stride of
500 IDs, a separate `FetchDescriptor` fetches only that chunk's records (full
fetch, no column projection needed since all fields are read during mutation),
mutations run immediately against the chunk's records, `modelContext.save()` is
called if any field changed, and failed saves rollback the historical actor
context before the next chunk. The chunk's object references then fall out of
scope, allowing ARC to reclaim the heap before the next stride loads its 500
objects. Peak faulted-object count is bounded to one chunk regardless of page
size, page count, or user library depth.

`JSONEncoder` is hoisted above both the chunk loop and the per-record loop.
Allocating one encoder per record across a sync page adds measurable GC pressure
on the `@ModelActor` thread; a single hoisted instance is reused for every
`candidatesData` encode across all chunks.

### Idle CMMotionManager Battery Drain (`EnvironmentContextManager`)

`EnvironmentContextManager` previously instantiated a `CMMotionManager` and
started device-motion updates at 100 Hz
(`motionManager.startDeviceMotionUpdates(to:)`) during live location tracking.
No code path ever consumed the motion data — there were no
`motionManager.deviceMotion` reads and no handler closure attached to the update
queue. The manager was running at 100 Hz purely to warm the sensor, burning CPU
cycles and waking the processor 100 times per second for zero benefit.

`CMMotionManager`, the `import CoreMotion` statement, and all `motionManager.*`
call sites have been removed from `EnvironmentContextManager`. The captured
telemetry fields that were once intended to use motion data
(`cameraPitchDegrees`, `compassHeading`) were already pruned from the
`CaptureTelemetry` payload in a prior token-reduction pass. Removing the manager
eliminates ~1–3% continuous CPU overhead and a measurable battery drain in the
field.

### Synchronous `@MainActor` Execution (`ViewfinderIntelligence`)

`ViewfinderIntelligence.analyze(brightness:distance:lumaStdDev:)` performs only
pure float comparisons — no I/O, no network, no heavy CPU work. Despite this,
the previous implementation wrapped the entire method in a
`Task.detached(priority: .userInitiated)` + a nested
`defer { Task { @MainActor in self?.isAnalyzing = false } }` trampoline,
allocating three Task heap objects per frame at 3 Hz (9 allocations/second)
solely to run a handful of float comparisons.

Because the camera's `captureOutput` delegate already dispatches to `@MainActor`
via `Task { @MainActor in }` before calling `analyze`, there is no work that
needs to leave the main actor. The entire `Task.detached` infrastructure was
removed. `analyze` and `updateHint` are now fully synchronous `@MainActor`
methods:

```swift
// Before
func analyze(...) {
    Task.detached(priority: .userInitiated) { [weak self] in
        defer { Task { @MainActor [weak self] in self?.isAnalyzing = false } }
        ...
        await self.updateHint(.optimal)
    }
}
private func updateHint(_ hint: VUIHint) async { await MainActor.run { ... } }

// After
func analyze(...) {
    guard !isAnalyzing else { return }
    isAnalyzing = true
    defer { isAnalyzing = false }
    // Direct synchronous comparisons — no tasks
    if brightness < 0.20 { updateHint(.tooDark); return }
    updateHint(.optimal)
}
private func updateHint(_ hint: VUIHint) {  // synchronous
    if currentHint != hint { currentHint = hint }
    let newOptimalState = (hint == .optimal)
    if isOptimal != newOptimalState { isOptimal = newOptimalState }
}
```

The `isAnalyzing` flag is retained as a re-entrancy guard: if `analyze` is
called again before the current `@MainActor` drain cycle finishes (e.g., via a
rapid frame callback burst), the second call is dropped immediately rather than
queueing work. `pauseAnalysis(for:)` also calls `updateHint(.optimal)` directly
instead of wrapping it in a `Task { await updateHint }`.

### Latest-State FPS Observation (`CameraManager`)

`CameraManager.trackFPS()` uses
`withObservationTracking { _ = HardwareOrchestrator.shared.targetFPS } onChange:`
to re-apply the frame rate whenever the hardware target changes. Observation
tracking is one-shot: after `onChange` fires, the registration no longer sees
subsequent mutations. The callback therefore clears its
`isFPSTrackingRegistered` guard and calls `trackFPS()` again as its first
operation on `@MainActor`, before starting or awaiting debounce work.

The 100 ms coalescing delay is owned by `CameraTargetFPSDebouncer`. Scheduling a
new application cancels the prior task and installs a fresh UUID generation.
Cancellation remains an optimization rather than the correctness boundary: the
task compares its generation before reading or applying a value, and state is
cleared only by the generation that still owns it. The FPS source is evaluated
after the delay, so a thermal escalation or recovery that occurred while the
task slept supersedes the trigger value.

```swift
self.isFPSTrackingRegistered = false
self.trackFPS() // Re-arm before any suspension.
self.targetFPSDebouncer.schedule(
    currentTargetFPS: { HardwareOrchestrator.shared.targetFPS },
    apply: { [weak self] fps in self?.applyTargetFPS(fps) }
)
```

`applyTargetFPS(_:)` remains the actor-to-hardware handoff: the debouncer and
`HardwareOrchestrator` state stay on `@MainActor`, while session input lookup,
device configuration locking, and frame-duration writes execute on the serial
camera queue.

### Concurrent Cloud Deletion Fan-Out with Batch Cap (`OfflineQueueManager`)

`syncPendingDeletions()` previously called
`MerianNetworkClient.shared.deleteScan(scanId:)` for each queued
`PendingCloudDeletionTask` in a serial `for` loop. Each deletion is an
independent HTTP round-trip to the `delete-scan` Edge function (~300–600 ms
each). For a user who deleted 10 scans offline, draining the queue required 3–6
seconds of sequential network time.

The client fan-out is only an acceleration path. Each server request first
commits a permanent per-scan generation tombstone; an independent leased reaper
finishes interrupted work. R2 candidates must match
`public_uploads/{free|pro}/{verified-owner-uuid}/{safe-filename}` exactly, so
parallel service-role deletion cannot be redirected through a foreign URL in a
poisoned row. URL/tag arrays are bounded in PostgreSQL before Edge allocation.

The loop was replaced with a `withTaskGroup` fan-out, batched in groups of 10 to
prevent connection-pool exhaustion when users accumulate large queues:

```swift
let batchSize = 10
for batchStart in stride(from: 0, to: pendingTasks.count, by: batchSize) {
    let batch = Array(pendingTasks[batchStart..<min(batchStart + batchSize, pendingTasks.count)])
    let batchResults = await withTaskGroup(of: (String, Error?).self) { group in
        for task in batch {
            group.addTask {
                do {
                    try await MerianNetworkClient.shared.deleteScan(scanId: task.scanId)
                    return (task.scanId, nil)
                } catch { return (task.scanId, error) }
            }
        }
        var collected: [(String, Error?)] = []
        for await result in group { collected.append(result) }
        return collected
    }
    allResults.append(contentsOf: batchResults)
}
// Single context.save() after all batches are processed
```

A single `context.save()` runs after all batches settle, batching all successful
tombstone removals into one write. For 10 deletions the wall time drops from ~4
s to ~600 ms; the cap prevents unbounded concurrency for users with hundreds of
queued deletions.

This client fan-out is not the privacy durability boundary. The server first
writes a generation tombstone, and `reconcile-scan-deletions` independently
drains interrupted erasure with 25-job claim waves, 100-job/40-second invocation
bounds, job concurrency four, and finite per-object request deadlines. Thus the
device may disappear without leaving a resumable scan generation or an
unmonitored cleanup backlog.

### `@MainActor` Sort Offload (`ScansLibrarySearchCoordinator`)

When the Scans library has no active filter and the user changes the sort order,
the Library previously re-sorted the full `allScans` array synchronously on the
`@MainActor`. For a library with thousands of records a
`localizedCaseInsensitiveCompare` sort can take 20–50 ms, producing a visible
hitch during the library transition animation.

For the "no active filter" path — which operates on the full dataset — the sort
is now offloaded to a detached worker and cached by sort option. Because
`@Model` entities (`LocalScanRecord`) are non-`Sendable` and cannot safely cross
isolation boundaries in Swift 6, they are mapped into lightweight primitive
structures before offloading:

```swift
struct ScanSortPrimitive: Sendable {
    let id: String
    let timestamp: Date
    let commonName: String
}

let sortOption = requestedSortOption
let primitives = allScanSortPrimitives

let sortedIds = await Task.detached(priority: .userInitiated) {
    ScanLibrarySortPolicy.sort(primitives, by: sortOption).map(\.id)
}.value

sortedAllScanIDsCache[sortOption.rawValue] = sortedIds
let finalSorted = records(for: sortedIds)
onSearchCompleted?(finalSorted, normalizedQuery)
```

The detached task holds no reference to the `@MainActor`-isolated coordinator or
unsafe model references. Once the sorted IDs are cached, subsequent query clears
and sort toggles can reuse the same full-library order without rebuilding it.

### Lightweight ID/Primitive Cache (`ScansLibrarySearchCoordinator`)

The contained coordinator needs efficient ID → record resolution without
scanning the full `@Query` result for every search result. Its private cache is
rebuilt from the already-resident `allScans` array and keeps only live
references plus lightweight sort metadata:

```swift
private var scanIndexByID: [String: Int] = [:]
private var scanRecordByID: [String: LocalScanRecord] = [:]
private var sortPrimitivesByID: [String: ScanSortPrimitive] = [:]
private var allScanSortPrimitives: [ScanSortPrimitive] = []
```

The caches are rebuilt once when `allScans` changes, then reused across all
query/filter/sort passes. `record(for:)` resolves through `scanIndexByID` first
and only falls back to `scanRecordByID` if the indexed slot is unavailable or
stale during a snapshot transition. `sortPrimitivesByID` avoids recreating
primitive sort payloads on every keystroke. This keeps CPU predictable without a
second SwiftData fetch or per-result linear scan.

Advanced filtering has a parallel immutable cache:
`ScanLibraryFilterIndexSnapshot` plus its committed generation. It contains
plain `Sendable` values only; it must never retain `LocalScanRecord` references.
The filter sheet observes the committed `filterOptions` and
`orderedCategoryFilters` values rather than deriving either from `allScans` in
computed properties.

### Retired Timed Archive Rescue (`ArchiveManager`)

Merian no longer runs timed local rescue downloads for biological scan media
because successful biological evidence is durable in cloud storage regardless of
subscription tier. `ArchiveManager` is now limited to generated dataset archive
ZIP downloads.

### Historical Sync PostgREST Response Bloat — `species_dictionary(*)` Wildcard (`ScanRepository`)

`syncHistoricalScansDown` used `species_dictionary(*)` in its PostgREST embedded
join, fetching every column in `species_dictionary` for every scan on every sync
page. This included large text blobs — `wikipedia_overview`,
`habitat_description`, and the `similar_species TEXT[]` array — that are not
decoded by `CloudSpeciesDictionary`. For a power user with 1,000 scans across 20
pages, each response page carried several MB of unused nested JSON that had to
be fully deserialized before any row could be handed to
`HistoricalDatabaseActor`. The page-streaming design keeps in-memory scan
accumulation at O(page_size), but oversized page payloads negated that benefit
by expanding the Codable decode heap per page.

The wildcard was replaced with an explicit projection covering only the 15
columns that `CloudSpeciesDictionary` actually decodes:

```
species_dictionary(scientific_name, kingdom, phylum, class, order, family, genus,
  wikipedia_url, reference_image_url, hazard_type, common_names,
  wikipedia_overview, iucn_red_list_status, habitat_description, group_tags)
```

`wikipedia_overview` is intentionally included because `CloudSpeciesDictionary`
decodes it for the historical insight sheet display. All other
`species_dictionary` columns (e.g., `gbif_taxon_key`, `colors`,
`similar_species`, internal audit fields) are excluded, immediately reducing
per-page response size.

### Live Inference Hydration Task Proliferation (`InferenceEngine.analyze()`)

After a successful live inference result, three bare fire-and-forget
`Task { [weak self] in ... }` blocks were dispatched for Wikipedia hydration,
`fetchAndApplyEnrichment`, and GBIF image hydration. None were stored in a task
handle. If the user triggered a second scan immediately, `analyze()` cancelled
`inferenceTask` — but the three previous hydration tasks continued running
alongside three new ones. On a fast device scanning rapidly: up to 6 concurrent
background network requests accumulated per scan burst, with stale
Wikipedia/enrichment/GBIF results from the previous scan able to overwrite
`speciesData` state set by the new result.

`InferenceEngine` now owns
`@ObservationIgnored private var liveHydrationTask: Task<Void, Never>?`. At the
top of every `analyze()` / `analyzeNonVisual()` call,
`liveHydrationTask?.cancel()` fires alongside `inferenceTask?.cancel()`. The
live visual and nonvisual success paths both enter
`schedulePostInferenceHydrationIfNeeded(...)`, which creates one tracked task
containing:

- a Wikipedia child task, skipped when the identify response already included
  `wikipediaOverview`
- an enrichment child task that can update taxonomy / habitat / lookalikes, then
  sequentially fetch GBIF reference images with a cancellation check before the
  GBIF call

The helper preserves the one intentional modality difference through
`LiveReferenceHydrationPolicy`: visual captures may set
`activeMedia.referenceState = .loading` while waiting for missing reference
imagery; describe/audio success paths keep that loading state quiet. Core result
presentation does not wait for hydration. `commitSuccessfulResult(...)`
owner-checks the active scan, publishes persisted media, response-provided
references, and `SpeciesData`, then clears `isProcessing` last in the same
main-actor turn. The tracked hydration task continues progressively in the
background and is cancelled if the user starts another scan.

### Singleton Lifecycle Consistency in Child Tasks (`OfflineQueueManager+Sync`)

Inside `syncPendingScans`, invalid staging metadata and missing source files
used to create fire-and-forget inner tasks that tombstoned a scan later. Those
closures could outlive the upload batch that discovered the problem and mutate a
replacement attempt. These preflight failures are now handled synchronously on
the main actor and require both the exact upload-batch UUID and the scan's
latest claimed upload generation before changing durable queue state.

**Rule:** Terminal queue mutations must not be delegated to an unowned inner
task. Keep them inside the generation-owned operation and compare ownership
immediately before the mutation.

### Bounded Authoritative URLSession Enumeration (`OfflineQueueManager`)

OS-owned background tasks survive process suspension and relaunch, so an
in-memory active-ID set cannot be authoritative. Merian enumerates
`session.allTasks` only at ownership boundaries that require the OS view:
cold/ongoing orphan reconciliation, same-scan final-chunk detection, guarded
queue deletion, status-watchdog cancellation, and upload-batch completion.
Ordinary pending-scan selection relies on the durable `.pending → .uploading`
claim and does not enumerate the session first.

Every task description is parsed into a typed identity. Upload enumeration
filters by both scan ID and batch generation; inference enumeration filters by
scan ID and inference generation. The relevant code revalidates its in-memory
generation after each awaited enumeration before it clears registries, cancels
tasks, or mutates SwiftData. This pays the async enumeration cost only where
restart-safe truth is required and closes the ABA window introduced by treating
a pre-await ownership check as sufficient.

Orphan reconciliation also captures an `observedThrough` timestamp before
enumerating URLSession tasks. Rows with a newer `queueUpdatedAt` are excluded,
so a reconciliation pass built from snapshot A cannot reset a claim created
after that snapshot while it waits for the shared queue database actor.

### `reconcileScanPage` ID-Only Column Projection (`ScanRepository`)

Inside `reconcileScanPage`, the per-page existence check previously used the
`fetchIdentifiers + model(for:)` pattern — first fetching opaque
`PersistentIdentifier` handles, then calling `modelContext.model(for:)` for
each, which faulted the full `LocalScanRecord` row including all enrichment text
columns.

The check was rewritten to use a `FetchDescriptor` with
`propertiesToFetch = [\.id]`, which tells SQLite to return only the `id` column:

```swift
var desc = FetchDescriptor<LocalScanRecord>(predicate: #Predicate { chunk.contains($0.id) })
desc.propertiesToFetch = [\.id]
let records = (try? modelContext.fetch(desc)) ?? []
for record in records { existingIds.insert(record.id) }
```

For a page of 200 incoming scans, this reduces SQLite column reads from every
stored property (including large `habitatDescription` and `wikipediaOverview`
text fields) to a single integer-column scan, cutting the per-page fault
allocation significantly.

### Persistent Field Gate in `fetchAndApplyEnrichment` (`InferenceEngine`) — REMOVED

A `habitatDescription != nil, similarSpecies != nil` gate was briefly added at
the start of `fetchAndApplyEnrichment` as a persistent cross-session
deduplication guard. It was subsequently **removed** because it introduced a
similar-species regression:

**Root cause of the regression:** `load(from:)` (the historical scan hydration
path) decodes legacy `LocalScanRecord.similarSpecies TEXT[]` into
`speciesData.similarSpecies` — producing `LookalikeSummary` entries with null
`common_name` and null `reference_image_url` — _before_
`fetchAndApplyEnrichment` runs. The gate saw `habitatDescription != nil`
(already enriched) and `similarSpecies != nil` (populated from TEXT[], not from
the join table) and returned early, permanently blocking the upgrade from legacy
TEXT[] stubs to rich join-table lookalike entries for those scans.

**Why the gate was redundant:**

- **Live scans**: `SpeciesData.init(fromEdgeResponse:)` always initializes
  `similarSpecies = nil`, so the gate would never fire for a newly-captured scan
  anyway.
- **Historical scans**: `enrichmentAttemptedScanIds` (scan-ID-scoped) and
  `enrichedSpeciesTimestamps` (species-name-scoped, 24-hour UserDefaults window)
  already guard re-fires within and across sessions.
- **Cross-session deduplication**: The persistent backstop is the enrichment
  data itself. `load(from:)` computes a local `needsEnrichment` variable —
  `record.habitatDescription == nil || record.gbifTaxonKey == nil || (record.lookalikesData == nil && (record.similarSpecies?.isEmpty ?? true))`
  — and skips `fetchAndApplyEnrichment` when all fields are already present. No
  separate `needsEnrichment: Bool` column exists on `LocalScanRecord`; the
  stored enrichment fields are the gate.

**Rule:** Do not gate `fetchAndApplyEnrichment` on `similarSpecies != nil`.
`similarSpecies` can be populated from the legacy TEXT[] path with incomplete
data (no common names, no images), which is visually indistinguishable from a
populated join-table result at the gate check site but represents un-upgraded
data that must still flow through `enrich-scan`.

### Wikipedia Skip via `species_dictionary` Join (`InferenceEngine`)

The live-inference path's `liveHydrationTask` previously always called
`fetchWikipediaAndHydrate` for every successful scan, even if the `identify`
Edge response already included `wikipedia_overview` from the
`species_dictionary` embedded join.

`mappedData.wikipediaOverview` is captured as `capturedHasWikipedia` before the
task boundary. Inside the task, the Wikipedia round-trip is skipped when
`capturedHasWikipedia` is `true`:

```swift
if !capturedHasWikipedia {
    await self.fetchWikipediaAndHydrate(...)
    guard !Task.isCancelled else { return }
}
```

For any species whose dictionary row already contains Wikipedia data, this
eliminates a ~300–600 ms client Wikipedia call from background result hydration.
Cache misses remain outside the first-render path.

### Scoped Concurrent Enrichment (`InferenceEngine.fetchAndApplyEnrichment`)

`fetchAndApplyEnrichment` fires the `"enrichment"` scope (habitat, taxonomy,
GBIF key) and `"lookalikes"` scope (similar species cards) of the `enrich-scan`
Edge Function concurrently via `withTaskGroup`. Each `@MainActor` task group
child applies its fields to `speciesData` as soon as its network call resolves —
the habitat card and taxonomy section become visible independently of the
similar species gallery:

```swift
await withTaskGroup(of: Void.self) { group in
    if needsMetadata {
        group.addTask { @MainActor [self] in
            defer { self.isEnrichmentLoading = false }
            // fetches habitat_description, gbif_taxon_key, taxonomy
        }
    }
    if needsLookalikes {
        group.addTask { @MainActor [self] in
            defer { self.isLookalikesLoading = false }
            // fetches similar_species
        }
    }
}
```

Two `@Observable` flags gate their respective loading skeletons:

- `isEnrichmentLoading` — habitat/distribution skeleton in
  `HabitatAndDistributionCard`
- `isLookalikesLoading` — similar species gallery skeleton in `BiologicalView`

The historic `load(from:)` path computes `needsMetadata` and `needsLookalikes`
independently so only the missing scope is requested:

```swift
let needsMetadata   = record.habitatDescription == nil || record.gbifTaxonKey == nil
let needsLookalikes = record.lookalikesData == nil || lookalikesHaveNoCommonNames
```

GBIF image hydration continues to run unconditionally because it writes
`referenceImageUrl` to the specific scan record. Only the `enrich-scan` Edge
calls (which write species-level fields shared across all scans) are skipped
when already present. For users scanning the same species repeatedly in a field
session, this eliminates all but the first enrichment calls per species.

**Rule:** `enrichmentAttemptedScanIds` is scan-ID-scoped (guards re-fires on
historic scan opens) and is session-scoped (resets on launch).
`enrichedSpeciesTimestamps` is species-name-scoped (guards redundant Edge calls
during live-inference bursts) and is **cross-session-persistent** via
`UserDefaults` with a 24-hour TTL — a species enriched yesterday will not
re-enrich today. The persistent cross-session backstop is the enrichment data
itself: `load(from:)` computes `needsMetadata` and `needsLookalikes` from stored
field presence — no separate `needsEnrichment: Bool` column exists on
`LocalScanRecord`. Do not add an explicit boolean flag; the stored field
presence is the correct signal. Do not gate on `similarSpecies` field presence
alone; see the "Persistent Field Gate — REMOVED" section for the regression that
approach introduced.

## 2026-05 Regression Test Anchors

The hardening invariants are now codified in tests rather than documented only
as engineering intent:

- `MerianEnvironment.load(infoDictionary:)` verifies missing or malformed plist
  values produce fallback configuration plus typed diagnostics instead of
  startup crashes.
- Capture workspace offline visual/audio tests verify queued-only flows leave
  the live inference engine idle and do not cross `@MainActor` UI state into
  false processing state.
- Network payload and media-staging tests verify staged audio is represented by
  `audioR2ObjectKeys`, upload object keys/task descriptions are generated by
  `MediaStagingContract`, and inline foreground audio is rejected by file-size
  preflight before base64 allocation.
- Database actor tests verify local lookalike cache clearing walks batches and
  leaves non-biological records untouched.

### WAL Flush Frequency (`MerianConfig.ingestCheckpointInterval`)

The `ingestCheckpointInterval` constant (used by `HistoricalDatabaseActor` to
determine how often to call `modelContext.save()` during bulk historical
ingestion) was raised from 50 to 100. Halving the save frequency reduces SQLite
WAL flush operations by 50% during initial historical sync-down. The trade-off
is that an interrupted background task can roll back at most 100 records instead
of 50 — an acceptable loss given that historical sync is fully resumable from
the last committed page.

### Resilient UI Polling (Skeleton Auto-Retry)

When a background fetch fails (such as enrichment metadata failing to load due
to a transient network drop), the traditional approach was to fall back to a
manual "Retry" button. This required explicit user interaction.

To eliminate manual user interaction while protecting against runaway background
polling, the architecture relies on an **exponential backoff auto-retry loop**
bound to the SwiftUI view lifecycle:

```swift
.task {
    var retryCount = 0
    let maxRetries = 5
    
    while !Task.isCancelled && retryCount < maxRetries {
        if data != nil { break }
        
        if !isLoading {
            let delay = pow(2.0, Double(retryCount + 1))
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { break }
            
            retryCount += 1
            await triggerFetch()
        } else {
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
```

This ensures:

1. **Zero memory leaks:** The `.task` modifier bounds the execution lifecycle to
   the view. When the view disappears, the task is automatically cancelled and
   destroyed.
2. **Battery and API safety:** The `maxRetries` cap and the exponential backoff
   (e.g., 2s, 4s, 8s, 16s, 32s) prevent a permanently offline device from
   infinitely polling the network layer.
3. **Seamless UX:** The UI remains in a silent "loading" skeleton state
   throughout the retry window, resolving automatically when connectivity
   restores without requiring a user tap.

## 2026-04 Hardening Updates

- `MerianApp` no longer wipes the SwiftData store on every `ModelContainer` init
  failure. Recovery is now store-aware and corruption-specific, owned by
  `Core/Data/StoreRecovery/ModelStoreRecoveryCoordinator.swift`: it parses store
  metadata for current/recent/full migration selection, quarantines
  `default.store` + WAL/SHM siblings only after verified corruption signatures,
  writes a sanitized manifest, and fails closed on non-corruption startup
  errors.
- `InferenceEngine` now guards background-write replay with a generation token.
  `prepareForNewScan()` and `cancelActiveRequest()` both clear pending closures
  and invalidate stale write tasks so cancelled work cannot mutate the next scan
  session.
- `AudioCaptureManager` and `SpeechManager` now guarantee full teardown on
  startup cancellation and early failures: tap removal, engine stop, task
  cancellation, stream finishing, and session deactivation all happen on every
  exit path. `AudioSessionCoordinator` serializes activation/deactivation with
  lease tokens so stale teardown work cannot deactivate a newer session.
- The spectrogram and SNR hot paths no longer use repeated `removeFirst()` array
  shifts. They now keep bounded circular buffers for visible spectrogram history
  and trailing noise-floor history.
- Non-biological bulk deletion now commits SwiftData and
  `PendingCloudDeletionTask` state before file removal, eliminating the broken
  "DB row survives but media is already gone" failure mode.
- `SupabaseManager` now guards anonymous auth bootstrap with a single
  `ghostSessionTask`, preventing multiple suspended callers from racing
  `signInAnonymously()` against the same empty session state.

## 2026-05 Stability Updates

- **Non-fatal bootstrap boundaries**: auth presentation, Apple nonce generation,
  and `ModelContainer` startup are now recoverable paths. Startup selects a
  store-aware migration strategy before opening, routes SwiftData/Core Data
  Objective-C exceptions through the bridge, retries duplicate-checksum sources
  with source-isolated recent plans, quarantines the store only when corruption
  signatures match, archives non-corrupt legacy migration failures under
  `store-rescue/` before rebuilding a fresh persistent store, and falls back to
  an in-memory safe mode with a user-facing notice only if recovery fails.
- **Collection membership is scan-driven**: `ScansSheetView` owns the shared
  completed-library query, and `CollectionsViewModel`,
  `SelectMultipleScansViewModel`, and `CollectionDetailViewModel` derive bounded
  membership snapshots from `LocalScanRecord.collections`. Collection cards and
  detail/selection views neither add their own record query nor traverse
  `collection.scans`. `CollectionMutationService` commits scan-side edits before
  publishing invalidation or enqueueing sync, so SwiftData faults stay bounded
  and failed writes cannot advertise uncommitted state.
- **Offline file work is actor-owned**: queued-scan cleanup and media
  writes/adoption flow through `FileIOActor.deleteFiles(at:)` /
  `writeTemporaryImages(imageDatas:)`.
- **File-backed restore uploads**: explore restore now re-uploads images and
  videos with `upload(for:fromFile:)` and a small task-group concurrency window,
  eliminating duplicate in-memory media buffers during restores.
- **Detached tasks are now exceptional**: view-owned network mutation work such
  as biological rescue and export flows moved behind repository or actor APIs.
  Remaining detached work must stay within `Sendable` CPU/file bridges only.
- **Documented detached-work bridge**: high-level app flows now use
  `DetachedWork` instead of spelling raw `Task.detached` inline. This keeps the
  remaining executor escapes explicit, searchable, and narrow enough for
  linting.
- **Typed settings boundary**: settings-first UI surfaces now read and mutate
  `AppSettings` rather than owning `@AppStorage` strings directly. Storage keys
  remain centralized, while the view layer binds to typed state.
