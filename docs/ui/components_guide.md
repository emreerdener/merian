# UI & SwiftUI Architectural Boundaries

Merian embraces the `WindowGroup` logic seamlessly across `SwiftUI` avoiding `.xib` or `UIKit` storyboards entirely (with the sole exception of `AVFoundation`'s `AVCaptureVideoPreviewLayer` bridge natively rendered via `UIViewRepresentable`).

## Layout & Glassmorphism Aesthetics

- Enforces stunning `.ultraThinMaterial` backgrounds universally across sheets cleanly providing immediate tactile and visual contextualization perfectly merging reality with data payloads natively.
- Prevents opaque blocking elements that hide the `CameraPreviewView` strictly.
- Heavy use of native iOS human interface guidelines explicitly integrating SF Symbols naturally rendering elements via dynamic `.primary` and `.secondary` layers transparently natively globally.

## The Active UI Flow

### `CameraRootView`
- The monolithic foundation mapping the complete UI hierarchy seamlessly across standard layout bindings globally natively across iPhones cleanly.
- Responsible for presenting `MerianActionBar`, rendering `AsyncImage` carousels from the active `Discovery Feed`, and calling into `LocationManager` seamlessly requesting permissions seamlessly gracefully falling back cleanly.
- Delegates user profile interactions cleanly out to `UserProfileView.swift` preventing monolithic Main Actor View bloat by isolating `StatCardView` modules securely into their own feature domains.

### `InsightSheetView` (The AI Resolution Context)
- Displays the successfully parsed ML taxonomy arrays natively mapped out across a declarative, componentized layout (`InsightMainComponents` and `InsightComponents`).
- The entire view is wrapped in a native `NavigationStack`, heavily utilizing a native toolbar for actions (e.g. `isBiological` driven native share/export buttons and native close actions), permanently discarding bespoke rigid header bars.
- Its localized parsing abstractions block logic purely via abstracted domain models located cleanly in `Models/SpeciesData.swift` decoupling data bounds from structural view logic flawlessly.
- Key logical container boundaries:
  - `InsightCarouselView`: Handles rendering legacy uploaded archives seamlessly alongside aggressively prioritized local `.userInitiated` `Task.detached` ML evaluation data loops. Critically, it proactively pre-filters historical file paths out of the loops if the local capture has expired, intelligently collapsing empty views out of existence and dynamically forcing the carousel to feature the stunning encyclopedic Wikipedia or GBIF Reference thumbnails to preserve visual perfection.
  - `InsightToxicityBanner`: High-priority `.isHeader` accessibility mapped warning boundaries gracefully prioritizing user safety actively.
  - `InsightTaxonomyHeader` & `InsightTaxonomyTree`: Strictly parses the taxonomy objects perfectly dynamically routing to `BadgeView` grids and `TaxonomyNode` capsules across interactive horizontal scroll bounds natively.
  - `InsightDescriptionSection`: Dynamically populates AI rationale securely and natively renders extracted Wikipedia paragraphs directly within the app bounds, gracefully wrapping fallback buttons that open direct pipelines into local `SafariServices` bounds (`WKWebView`).
- Gracefully binds ML hallucination correction tools naturally (`FlagIssueView`), executing POST payload drops securely bypassing native UI blocks inherently.

### `ScanningOverlayView` (The Analysis Transition State)
- This boundary intercepts the optical viewfinder exactly upon shutter press. It serves to completely abstract edge networking delays natively from the user.
- **Isolated Animation Engine**: It features a complex, continuously rotating 360-degree `LinearGradient` (rainbow styling). To guarantee completely smooth frame rates that do not physically stutter or flicker when other `@Published` `CameraViewModel` states mutate around it, the animation logic is rigorously decoupled and strictly bound inside a localized struct or `.equatable` bound. This isolates SwiftUI layout renders from interrupting the sheer physics loops maintaining the premium glassmorphism aesthetics perfectly.

### `LifeListSearchManager` & Discovery Grids
- Maps `LifeListThumbnailView` securely binding to `SwiftData` persistently tracking local users cleanly globally safely across device sessions.
- **Life List Ecosystem Integration**: When a user physically taps a local biological trace from their `LifeListSearchView`, it seamlessly opens the `InsightSheetView` passing the `LocalScanRecord`. The view dynamically prioritizes population of the `InsightCarouselView`, taking the exact geometric image they snapped securely off the disk and locking it natively as the primary `index 0` carousel focal point prior to loading any peripheral reference media out of external databases natively.
- **Search Interactions**: To adhere to premium iOS design language, the search abstraction explicitly deploys a native iOS text binding anchored flawlessly to the *bottom* boundary of the view ensuring thumb-reachability cleanly natively. It includes an explicit native `X` bound clear-button trigger to reset queries intuitively seamlessly natively dynamically mutating local `SwiftData` arrays instantly.
- **Linnaean Taxonomic Filtering**: The grid utilizes an advanced decoupled mapping algorithm pushing logic explicitly off the Main Actor bounds natively out to `Task.detached`. When a user toggles an environment tab (e.g. "Insects" or "Reptiles"), it strictly evaluates the active `taxonomyClass` string directly on the `SearchableScan` object explicitly natively generating clean boundaries (e.g. `arachnida` and `entognatha` merge securely under the `insects` grid) rather than checking against fragile legacy `ecologyType` strings or user-side string filters natively rendering perfect local scientific models flawlessly!
- Automatically handles physical R2 storage expirations actively: If a taxonomy scan `image_storage_urls` array physically vanishes because of the Rolling Cloud Window 90-day GC process (`00004_storage_lifecycle_sync.sql`), the `AsyncLocalImageView` and `LifeListThumbnailView` elegantly trap the 404 explicitly. Rather than aggressively rendering "Visuals Archived", the system utilizes a high-performance `fetchNetworkFallback` hook. It securely unzips the GBIF or Wikipedia Reference URL into a tiny footprint (500x500 `CGSize`), loads it perfectly into `ImageCache.shared` explicitly, and dynamically replaces the expired local file gracefully with zero extra scrolling data latency across the grid UI natively.
## Helper Modifiers

### `VisualEffectBlur`
- Used across the codebase seamlessly wrapping legacy `UIBlurEffect` natively inside `.edgesIgnoringSafeArea` boundaries tightly executing aesthetic bounds flawlessly internally mapping across the entire design system inherently flawlessly.

### `.injectAppDependencies(container:)`
- Standard view modifier preventing deep `$EnvironmentObject` injection chains cleanly. Passes the primary `AppDIContainer` securely across UI states dynamically.
