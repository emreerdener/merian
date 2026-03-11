# SwiftUI UI Components Guide

Merian enforces a radical, zero-friction UI mapping exclusively to physical hardware. Standard UI navigation stacks (`UINavigationController`) are completely removed in favor of single-view contextual overlays.

## 1. `CameraRootView.swift`

The massive full-bleed base architecture.

- Maps an `AVCaptureVideoPreviewLayer` wrapping `UIViewRepresentable` entirely behind a `ZStack` physically.
- Listens to the `@EnvironmentObject var vui: ViewfinderIntelligence` injected from the root application.
- Integrates iOS native `PhotosPicker` natively within a floating Top Toolbar to scan legacy captures directly from the camera roll.
- Renders contextual `VisualEffectBlur(blurStyle: .systemUltraThinMaterialDark)` liquid-glass nodes replacing bulky UI overlays, rendering floating interaction points (Flash/Torch top-right, Life List bottom-left, User Profile bottom-right, Shutter bottom-center).
- Binds a premium `RainbowScanningOverlay` natively injecting a dynamic hue-rotating linear gradient pulsing `0.6` opacity frames to communicate inference processing dynamically matching the 16-point UI corner radiuses precisely. 
- Throws `.ultraThinMaterial` dynamic SwiftUI hints ("Move Closer", "Too Dark") instantly without `alert` blockers.
- Binds `AVCaptureEventInteraction` natively mapping the hardware volume buttons, the Action Button, and the physical iPhone 16 Camera Control strictly onto the `.began` state allowing hardware closures to immediately trigger Shutter captures mirroring the system Camera app implicitly.
- Orchestrates dynamic `.black` bounding boxes removing transparent elements completely when `HardwareOrchestrator` triggers thermal throttling states.

## 1.2 `CameraViewModel.swift`

Extracts all state management explicitly away from `CameraRootView`.

- Owns presentation states (`isInsightSheetOpen`, `isPaywallOpen`, `isLifeListOpen`).
- Manages strict logic wrapping `handleCropCompletion` safely inside Task closures and delegates context retrieval seamlessly downwards to `AppDIContainer.shared.environmentContextManager` preventing the View layer from touching CoreLocation rules natively.
- Immediately forces an Optimistic State Execution (`isAnalyzingFullscreen = true`) updating the view bindings natively *before* deferring off to the heavy `EnvironmentContextManager` mapping dynamically, guaranteeing the UI never deadlocks on a 2-second viewfinder freeze during terrible satellite acquisitions in the wilderness.
- Evaluates async processing synchronizations and explicitly pauses `CameraManager` viewport sensors when the Insight sheet is dynamically expanded securely saving thermal capacity.

## 1.5 `GlassCircularButton.swift`

A highly reusable UI primitive resolving Glassmorphism thermal state bounds across the application.

- Accepts dynamic `.environmentObject` states securely dictating whether an `.ultraThinMaterial` backplate or an opaque `.black.opacity(0.7)` bounds natively. This ensures standard thermal drops execute globally without massive `ZStack` UI duplication.

## 1.6 `ImageCropperView.swift`

Forces symmetrical constraints natively upon captured payloads prior to inference.

- Intercepts all inputs (`Camera` & `PhotosPicker`) with a `.fullScreenCover`, allowing users to pan/zoom their subject directly within a strictly enforced 1:1 `.clipShape(Rectangle())`.
- Mathematically bounds translation and zoom arrays natively using `DragGesture` and `MagnificationGesture`. It explicitly traps images within the geometric viewport dynamically mapping `maxX` and `maxY` constraints enforcing rigid boundaries. If a user tries to zoom too far out, a `withAnimation(.spring())` wrapper snaps the picture seamlessly back inside the 1:1 footprint avoiding void or black edge exposure safely natively.
- Completely bypasses Apple's `@MainActor` `ImageRenderer` constraints by mathematically mapping the SwiftUI native `scaleEffect` and `offset` state matrix backwards into physical pixel coordinate modifiers dynamically. Inside a structurally isolated `Task.detached(priority: .userInitiated)` block off the UI thread, it executes heavy 12-Megapixel bounds entirely over Core Graphics via `cgImage.cropping(to:)`. Crucially, it wraps the entire context buffer strictly inside an `autoreleasepool { }` boundary. This natively purges the heavy 12-Megapixel raw `CGImage` footprints and intermediate struct buffers explicitly out of RAM the exact millisecond `jpegData` compression finishes, actively protecting old iOS devices like the iPhone 11 from fatal Out-Of-Memory (`EXC_RESOURCE`) memory spikes.

## 1.7 `LifeListSearchManager` & Search Integration

Manages the core historical species cataloging system.

- Instantiates a bottom-aligned native iOS `.searchable` style textfield strictly enforcing `LocalScanRecord` structure searches cleanly embedded directly into the layout. 
- Deduplicates identical species captures natively into unified model wrappers containing arrays of historical `additionalImagePaths`.
- Radically abandons continuous `@ModelActor` SwiftData executions per-keystroke. Instead, the manager inherently pulls all database matrices once efficiently parsing them down into flat, thread-safe `SearchableScan` structs (`id`, `searchString`). It fires `Task.detached(priority: .userInitiated)` entirely over standard arrays in physical memory evaluating `localizedStandardContains()`, strictly circumventing all SQLite physical SSD loads bounding search response times completely to 0ms implicitly. 
- Enforces strict asynchronous debounce boundaries natively using `Task.sleep()` coupled with `searchTask?.cancel()` cancellation hooks on every keystroke.
- Strips heavy typography text labels from the `LazyVGrid` feed explicitly in favor of a dense, 3-column `GridItem` layout enforcing a perfect 1:1 `aspectRatio(contentMode: .fill)` constraint on all historical payloads mirroring a native iOS Camera Roll. Thumbnails securely bind a thread-safe singleton, `ImageCache.shared` to hit 0ms loading latencies natively bypassing disk reads when rapidly scrolling back up.
- To prevent layout collisions mapping modal presentations onto `NavigationStack` boundaries, the feed natively eliminates navigation routing inherently. Tapping specific historical arrays dynamically sets a localized `$selectedScanForInsight` object mapping instantly to a `.sheet()` modal. This bounds the `InsightSheetView` identical behavior identically matching the Viewfinder's bottom-up presentation loop.

## 2. Default `InsightSheetView.swift` (Built Structure)

The physical analytical response boundary natively wrapping the `SpeciesData` schema generated natively by Deno.

- Always renders up in the "Natural Thumb Zone" from the bottom. Defaults exclusively to a full-screen `.large` presentation detent explicitly obscuring the background viewfinder cleanly.
- To allow flexible integration across both state-driven flows and standalone item bindings (as deployed inside the Life List historical feed), all closing and dismissing events exclusively leverage the native SwiftUI `@Environment(\.dismiss)` hooks rather than rigidly mutating parent `@Binding var isPresented` states natively.
- Implements a horizontal `TabView` carousel displaying all historical encounters natively mapping to `activePayloads` file path strings dynamically via `AsyncLocalImageView`. This securely bounds its payload via `ImageCache.shared.get()` capturing the `UIImage` immediately via RAM at 0ms latency. If missed, it rigidly detaches heavy 12-Megapixel file I/O loading strictly off the `@MainActor` onto a CPU pool. It securely decodes raw byte bounding boxes directly from the physical disk dynamically utilizing strict `ImageIO` bounds explicitly invoking `CGImageSourceCreateThumbnailAtIndex` implicitly guaranteeing absolute UI fluidity natively setting `ImageCache.shared` post-decode bounds natively limiting iOS Out-Of-Memory (OOM) crashes across 12-Megapixel boundaries natively.
- Renders dynamic metadata badges natively evaluating `isInvasive`, `ecologyType`, `isBiological`, and `isLiveCapture` flags beneath the primary confidence score UI.
- Displays dynamic Taxonomy (Kingdom, Phylum) trees visually expanding the Deno metadata inputs explicitly using horizontal glassmorphic capsules natively.
- Evaluates strict liability rules dictating `isPoisonous` renderings accurately: Merian strictly bounds a red warning badge if poisonous, otherwise defaults exclusively to "Edibility Unknown. Merian is an educational tool. Never ingest wild flora." securely protecting users from hallucinations natively.
- Automatically drops VoiceOver explicitly reading the `commonNames` strings first, followed deeply by `isPoisonous` states natively.

## 3. The Digital Terrarium (`TerrariumView` - Partially Built)

The core physical engagement reward schema natively designed inside `RiveRuntime`.

- Natively draws a vector glass sphere looping physically inside Merian.
- As users accumulate native biology logs (e.g. scans a Monarch Butterfly natively), the Terrarium dynamically initializes the vector entity (the physical butterfly) dynamically moving endlessly inside the user's saved biological state.
- Renders the "Museum Card" schema exporting natively dynamic glassmorphic text mappings physically into the iOS Photos gallery.
