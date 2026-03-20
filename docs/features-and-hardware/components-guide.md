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
- Delegates user profile interactions cleanly out to `UserProfileView.swift` preventing monolithic Main Actor View bloat by natively embedding the entirety of the legacy Settings modules directly mapping `StatCardView` components under fluid List architecture without requiring sequential routing sheets.

### `InsightSheetView` (The AI Resolution Context)
- Displays the successfully parsed ML taxonomy arrays natively mapped out across a declarative, componentized layout (`InsightMainComponents` and `InsightComponents`).
- The entire view is wrapped in a native `NavigationStack`, heavily utilizing a native toolbar for actions (e.g. `isBiological` driven native share/export buttons and native close actions), permanently discarding bespoke rigid header bars.
- Its localized parsing abstractions block logic purely via abstracted domain models located cleanly in `Models/SpeciesData.swift` decoupling data bounds from structural view logic flawlessly.
- Key logical container boundaries:
  - `InsightCarouselView`: Handles rendering uploaded archives alongside aggressively prioritized ML data loops. To entirely eradicate native `ScrollView` vertical bounce gaps, it rigorously enforces an explicit `GeometryReader` coordinate intercept natively driving a flawless Apple-standard **Stretchy Header Parallax** effect physically pinning the 1-to-1 aspect ratio image flush against the absolute device boundary natively dragging into an elastic scale transformation natively rather than clipping.
  - `InsightTaxonomyHeader` & `InsightTaxonomyTree`: Repositions analytical boundaries cleanly. The header features the localized common name, scientific name, and a newly dynamic horizontal `.BadgeView` layout array natively stacking `.ecologyType` string heuristics natively completely obsoleting legacy card views. The Tree renders a vertical key-value `.glassCard` dictionary explicitly outlining classification mapping natively.
  - `InsightEnvironmentCard`: *Explicitly Deprecated and Natively Scraped.* All fallback structural environment string behaviors were massively decentralized directly into `TaxonomyHeader` rendering bounds organically via independent `BadgeView` vectors.
  - `InsightConservationCard`: Modular `.ultraThinMaterial` capsule safely projecting strict continuous IUCN status states structurally.
  - `Taxonomy Badges`: Entirely abstracted `.ultraThinMaterial` pipeline supporting `LocationBadgeView`, `WeatherBadgeView`, and `ConfidenceBadgeView` seamlessly mapped atop the Carousel straddle boundary explicitly mapping dynamic space-between alignment routing strictly when offline metadata is suppressed.
  - `Collection Routing`: The global "Add to collection" boundary was actively migrated out of standard sheet bounds seamlessly generating a strict iOS 15 `Menu` abstraction yielding immediate native Frosted Glass context menus explicitly supporting "Favorites", "Sightings", and "New Form" fallbacks natively.
  - `InsightDescriptionSection`: Dynamically populates AI rationale securely and natively renders extracted Wikipedia paragraphs directly within the app bounds, gracefully wrapping fallback buttons that open direct pipelines into local `SafariServices` bounds (`WKWebView`).
  - `Photo Extraction Engine`: Binds explicit toolbar `Menu` commands to `PhotoLibraryManager.saveImageManual(imageData:)` and the Apple Share Sheet natively. It safely filters remote URLs and actively captures local caches via direct iOS sandbox boundary evaluations (`URL.documentsDirectory.appendingPathComponent`) dynamically dumping bytes to the exact OS target without breaking on abstract filename bounds.
- Gracefully binds ML hallucination correction tools naturally (`FlagIssueView`), executing POST payload drops securely bypassing native UI blocks inherently.

### `ScanningOverlayView` (The Analysis Transition State)
- This boundary intercepts the optical viewfinder exactly upon shutter press. It serves to completely abstract edge networking delays natively from the user.
- **Isolated Animation Engine**: It features a complex, continuously rotating 360-degree `LinearGradient` (rainbow styling). To guarantee completely smooth frame rates that do not physically stutter or flicker when other `@Published` `CameraViewModel` states mutate around it, the animation logic is rigorously decoupled and strictly bound inside a localized struct or `.equatable` bound. This isolates SwiftUI layout renders from interrupting the sheer physics loops maintaining the premium glassmorphism aesthetics perfectly.

### `ScansSearchManager` & Discovery Grids
- Maps `ScansThumbnailView` securely binding to `SwiftData` persistently tracking local users cleanly globally safely across device sessions.
- **Native Paging Navigation**: Replaces legacy horizontal drag gesture handling by abstracting completely out of UIKit boundaries natively implementing an iOS 17 pure `ScrollView(.horizontal)` combined with `.scrollTargetBehavior(.paging)`. This delivers frictionless 1:1 finger tracking between the library and collections directly inside the safe area without layout bugs. Includes automated logic wrapping state re-assignments natively mapping `.scrollPosition` bindings dynamically sweeping users back when they tap bottom search elements.
- **Scans Ecosystem Integration**: When a user physically taps a local biological trace from their `ScansSearchView`, it seamlessly opens the `InsightSheetView` passing the `LocalScanRecord`. The view dynamically prioritizes population of the `InsightCarouselView`, taking the exact geometric image they snapped securely off the disk and locking it natively as the primary `index 0` carousel focal point prior to loading any peripheral reference media out of external databases natively.
- **Search Interactions**: To adhere to premium iOS design language, the search abstraction explicitly deploys a native iOS text binding anchored flawlessly to the *bottom* boundary of the view ensuring thumb-reachability cleanly natively. It leverages the `.searchable(isPresented:)` modifier to track keyboard focus actively cleanly unmounting horizontal filter pills to yield maximal screen real estate for the search returns. It includes an explicit native `X` bound clear-button trigger to reset queries intuitively seamlessly natively dynamically mutating local `SwiftData` arrays instantly.
- **Linnaean Taxonomic Filtering**: The grid utilizes an advanced decoupled mapping algorithm pushing logic explicitly off the Main Actor bounds natively out to `Task.detached`. When a user toggles an environment tab (e.g. "Insects" or "Reptiles"), it strictly evaluates the active `taxonomyClass` string directly on the `SearchableScan` object explicitly natively generating clean boundaries (e.g. `arachnida` and `entognatha` merge securely under the `insects` grid) rather than checking against fragile legacy `ecologyType` strings or user-side string filters natively rendering perfect local scientific models flawlessly!
- **LocalImageLoader Integration**: To entirely avoid destroying device cellular data limits and prevent massive 150-line code duplication, iOS natively maps `ScansThumbnailView` and `AsyncLocalImageView` caching to a globally shared `LocalImageLoader` actor.
- `LocalImageLoader.shared` intelligently filters `ImageCache` lookups, physical RAM Sandbox byte extraction (`CGImageSourceCreateThumbnailAtIndex`), and `.ultraThinMaterial` fallback networks gracefully shielding Apple's cooperative thread pool dynamically out-of-the-box perfectly syncing UI flows flawlessly.
## 6. Global Core/UI/ Primitives

To brutally eliminate SwiftUI structural redundancy (ZStacks, Confirmation Dialogs, Repetitive Icons), core application placeholders are hoisted totally outside localized feature boundaries into `merian/Core/UI/`:
- **`EmptyStateView (Components/EmptyStateView.swift)`**: Completely abstracts repetitive VStacks, systemName bounding, and headline/subheadline styling uniformly across `ScansSearchView`, `NonBiologicalScansView`, and `CollectionDetailView`. Natively accepts a generic `@ViewBuilder content` to safely drop Explore Library buttons seamlessly into the layout.
- **`ArchivedVisualsView (Components/ArchivedVisualsView.swift)`**: Eradicates legacy `ZStack` boilerplate spanning `AsyncImage` bounds when 90-day Cloudflare R2 Lifecycle policies intrinsically expire Free-tier objects. Maps identical `.ultraThinMaterial` styling recursively into `ScansThumbnailView` and `AsyncLocalImageView` naturally.
- **`ScanDeletionDialogModifier (Modifiers/ScanDeletionDialogModifier.swift)`**: Secures `.confirmationDialog` actions preventing repetitive IDOR/Haptic boundaries directly inside explicit SwiftUI Views. Forces the execution thread to safely eradicate records via the `ScanRepository` globally seamlessly wrapping the destructive `Task` and `HapticManager.shared.triggerErrorThump()` organically.

## Helper Modifiers

### `.injectAppDependencies(container:)`
- Standard view modifier preventing deep `$EnvironmentObject` injection chains cleanly. Passes the primary `AppDIContainer` securely across UI states dynamically.
