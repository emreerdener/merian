# SwiftUI UI Components Guide

Merian enforces a radical, zero-friction UI mapping exclusively to physical hardware. Standard UI navigation stacks (`UINavigationController`) are completely removed in favor of single-view contextual overlays.

## 1. `CameraRootView.swift`

The massive full-bleed base architecture.

- Maps an `AVCaptureVideoPreviewLayer` wrapping `UIViewRepresentable` entirely behind a `ZStack` physically.
- Listens to the `@EnvironmentObject var vui: ViewfinderIntelligence` injected from the root application.
- Integrates iOS native `PhotosPicker` natively within a floating Top Toolbar to scan legacy captures directly from the camera roll.
- Renders contextual `VisualEffectBlur(blurStyle: .systemUltraThinMaterialDark)` liquid-glass nodes replacing bulky UI overlays, rendering floating interaction points (Flash/Torch top-right, Life List bottom-left, User Profile bottom-right, Shutter bottom-center).
- Throws `.ultraThinMaterial` dynamic SwiftUI hints ("Move Closer", "Too Dark") instantly without `alert` blockers.
- Orchestrates dynamic `.black` bounding boxes removing transparent elements completely when `HardwareOrchestrator` triggers thermal throttling states.

## 1.5 `GlassCircularButton.swift`

A highly reusable UI primitive resolving Glassmorphism thermal state bounds across the application.

- Accepts dynamic `.environmentObject` states securely dictating whether an `.ultraThinMaterial` backplate or an opaque `.black.opacity(0.7)` bounds natively. This ensures standard thermal drops execute globally without massive `ZStack` UI duplication.

## 1.6 `CameraZoomControl.swift`

Strictly mirrors the native Apple iOS camera application optical boundaries.

- Loops through standard `"0.5x", "1x", "2x"` arrays dynamically binding to `CameraManager.shared.availableZoomFactors` mapping explicitly against `.deviceType` boundaries (eg: avoiding `"0.5x"` allocations gracefully if the particular iPhone lacks an Ultra-Wide lens natively).

## 1.7 `ImageCropperView.swift`

Forces symmetrical constraints natively upon captured payloads prior to inference.

- Intercepts all inputs (`Camera` & `PhotosPicker`) with a `.fullScreenCover`, allowing users to pan/zoom their subject directly within a strictly enforced 1:1 `.clipShape(Rectangle())`.
- Mathematically bounds translation and zoom arrays natively using `DragGesture` and `MagnificationGesture`. It explicitly traps images within the geometric viewport dynamically mapping `maxX` and `maxY` constraints enforcing rigid boundaries. If a user tries to zoom too far out, a `withAnimation(.spring())` wrapper snaps the picture seamlessly back inside the 1:1 footprint avoiding void or black edge exposure safely natively.
- Leverages Apple's `ImageRenderer(content:)` scaled rigidly to `1.0` dynamically generating exact 1024x1024 geometric image buffers directly out of the SwiftUI layout.

## 1.8 `LifeListSearchManager` & Search Integration

Manages the core historical species cataloging system.

- Instantiates a bottom-aligned native iOS `.searchable` index filtering `LocalScanRecord` structures.
- Deduplicates identical species captures natively into unified model wrappers containing arrays of historical `additionalImagePaths`.
- Executes semantic background thread filtration dynamically utilizing Swift native `Set<String>` collections, fundamentally solving O(N²) array bottlenecks to achieve an instant **O(1)** lookup on the `@MainActor` without dropping the 60fps frame rate when handling large offline Life Lists natively.
- Strips heavy typography text labels from the `LazyVGrid` feed explicitly in favor of a dense, 3-column `GridItem` layout enforcing a perfect 1:1 `aspectRatio(contentMode: .fill)` constraint on all historical payloads mirroring a native iOS Camera Roll.

## 2. Default `InsightSheetView.swift` (Built Structure)

The physical analytical response boundary natively wrapping the `SpeciesData` schema generated natively by Deno.

- Always renders up in the "Natural Thumb Zone" from the bottom. Defaults exclusively to a full-screen `.large` presentation detent explicitly obscuring the background viewfinder cleanly.
- Implements a horizontal `TabView` carousel displaying all historical encounters natively mapping to `activePayloads` arrays. This image block strictly mathematically enforces a `1.0` `aspectRatio(contentMode: .fit)` boundary constraint making all rendered elements perfect grid-aligned squares.
- Renders dynamic metadata badges natively evaluating `isInvasive`, `ecologyType`, `isBiological`, and `isLiveCapture` flags beneath the primary confidence score UI.
- Displays dynamic Taxonomy (Kingdom, Phylum) trees visually expanding the Deno metadata inputs explicitly using horizontal glassmorphic capsules natively.
- Evaluates strict liability rules dictating `isPoisonous` renderings accurately: Merian strictly bounds a red warning badge if poisonous, otherwise defaults exclusively to "Edibility Unknown. Merian is an educational tool. Never ingest wild flora." securely protecting users from hallucinations natively.
- Automatically drops VoiceOver explicitly reading the `commonNames` strings first, followed deeply by `isPoisonous` states natively.

## 3. The Digital Terrarium (`TerrariumView` - Partially Built)

The core physical engagement reward schema natively designed inside `RiveRuntime`.

- Natively draws a vector glass sphere looping physically inside Merian.
- As users accumulate native biology logs (e.g. scans a Monarch Butterfly natively), the Terrarium dynamically initializes the vector entity (the physical butterfly) dynamically moving endlessly inside the user's saved biological state.
- Renders the "Museum Card" schema exporting natively dynamic glassmorphic text mappings physically into the iOS Photos gallery.
