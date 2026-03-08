# SwiftUI UI Components Guide

Merian enforces a radical, zero-friction UI mapping exclusively to physical hardware. Standard UI navigation stacks (`UINavigationController`) are completely removed in favor of single-view contextual overlays.

## 1. `CameraRootView.swift`

The massive full-bleed base architecture.

- Maps an `AVCaptureVideoPreviewLayer` wrapping `UIViewRepresentable` entirely behind a `ZStack` physically.
- Listens to the `@StateObject var vui = ViewfinderIntelligence.shared`.
- Integrates iOS native `PhotosPicker` natively within a floating Top Toolbar to scan legacy captures directly from the camera roll.
- Renders contextual `VisualEffectBlur(blurStyle: .systemUltraThinMaterialDark)` liquid-glass nodes replacing bulky UI overlays, rendering floating interaction points (Flash/Torch top-right, Life List bottom-left, User Profile bottom-right, Shutter bottom-center).
- Throws `.ultraThinMaterial` dynamic SwiftUI hints ("Move Closer", "Too Dark") instantly without `alert` blockers.
- Orchestrates dynamic `.black` bounding boxes removing transparent elements completely when `HardwareOrchestrator` triggers thermal throttling states.

## 1.5 `LifeListSearchManager` & Search Integration

Manages the core historical species cataloging system.

- Instantiates a bottom-aligned native iOS `.searchable` index filtering `LocalScanRecord` structures.
- Deduplicates identical species captures natively into unified model wrappers containing arrays of historical `additionalImagePaths`.

## 2. Default `InsightSheetView.swift` (Built Structure)

The physical analytical response boundary natively wrapping the `SpeciesData` schema generated natively by Deno.

- Always renders up in the "Natural Thumb Zone" from the bottom. Defaults exclusively to a full-screen `.large` presentation detent explicitly obscuring the background viewfinder cleanly.
- Implements a horizontal `TabView` carousel displaying all historical encounters natively mapping to `activePayloads` arrays.
- Renders dynamic metadata badges natively evaluating `isInvasive`, `ecologyType`, `isBiological`, and `isLiveCapture` flags beneath the primary confidence score UI.
- Displays dynamic Taxonomy (Kingdom, Phylum) trees visually expanding the Deno metadata inputs explicitly using horizontal glassmorphic capsules natively.
- Evaluates strict liability rules dictating `isPoisonous` renderings accurately: Merian strictly bounds a red warning badge if poisonous, otherwise defaults exclusively to "Edibility Unknown. Merian is an educational tool. Never ingest wild flora." securely protecting users from hallucinations natively.
- Automatically drops VoiceOver explicitly reading the `commonNames` strings first, followed deeply by `isPoisonous` states natively.

## 3. The Digital Terrarium (`TerrariumView` - Partially Built)

The core physical engagement reward schema natively designed inside `RiveRuntime`.

- Natively draws a vector glass sphere looping physically inside Merian.
- As users accumulate native biology logs (e.g. scans a Monarch Butterfly natively), the Terrarium dynamically initializes the vector entity (the physical butterfly) dynamically moving endlessly inside the user's saved biological state.
- Renders the "Museum Card" schema exporting natively dynamic glassmorphic text mappings physically into the iOS Photos gallery.
