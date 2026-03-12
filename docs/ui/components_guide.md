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

### `InsightSheetView` (The AI Resolution Context)
- Displays the successfully parsed ML taxonomy arrays correctly natively via dynamic ScrollViews cleanly mapped out across dynamic headers seamlessly globally safely across locales dynamically.
- Gracefully binds ML hallucination correction tools naturally (`FlagIssueView`), executing POST payload drops securely bypassing native UI blocks inherently.
- Extensively handles Wikipedia `WKWebView` natively via `SafariServices` smoothly preventing context switching boundaries natively.

### `LifeListSearchManager` & Discovery Grids
- Maps `LifeListThumbnailView` securely binding to `SwiftData` persistently tracking local users cleanly globally safely across device sessions.
- **Linnaean Taxonomic Filtering**: The grid utilizes an advanced decoupled mapping algorithm pushing logic explicitly off the Main Actor bounds natively out to `Task.detached`. When a user toggles an environment tab (e.g. "Insects" or "Reptiles"), it strictly evaluates the active `taxonomyClass` string directly on the `SearchableScan` object explicitly natively generating clean boundaries (e.g. `arachnida` and `entognatha` merge securely under the `insects` grid) rather than checking against fragile legacy `ecologyType` strings or user-side string filters natively rendering perfect local scientific models flawlessly!
- Automatically handles physical R2 storage expirations actively: If a taxonomy scan `image_storage_urls` array physically vanishes because of the Rolling Cloud Window 90-day GC process (`00004_storage_lifecycle_sync.sql`), the `AsyncLocalImageView` elegantly captures the 404 error explicitly rendering an interactive "Visuals Archived" state leveraging the `archivebox.fill` icon. This permanently mitigates UI crashing grids while embracing Radical Transparency formatting natively securely.
## Helper Modifiers

### `VisualEffectBlur`
- Used across the codebase seamlessly wrapping legacy `UIBlurEffect` natively inside `.edgesIgnoringSafeArea` boundaries tightly executing aesthetic bounds flawlessly internally mapping across the entire design system inherently flawlessly.

### `.injectAppDependencies(container:)`
- Standard view modifier preventing deep `$EnvironmentObject` injection chains cleanly. Passes the primary `AppDIContainer` securely across UI states dynamically.
