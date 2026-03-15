# Feature Modules and UI Architecture

Merian's UI architecture strictly adheres to a modular, glassmorphic design philosophy, ensuring maximum reuse of Swift components while safely decoupling heavy data operations from the main rendering loop to maintain a continuous 60fps framerate.

## 1. The Life List (`LifeListSearchView`, `LifeListSearchManager`)
The Life List acts as the user's primary offline biological journal. 

### Search & Filtering
- **Native iOS 18 Bottom Search Bar**: Integrates the native iOS 18 `.searchable` and `.searchDictationBehavior(.inline)` modifiers ripped out of the top drawer and dynamically pinned to the bottom placement via `DefaultToolbarItem(kind: .search, placement: .bottomBar)`.
- **Dictation & Clear Mechanics**: Relies strictly on native SwiftUI dictated microphone capabilities and standard 'X' overlays, requiring zero custom `UIViewRepresentable` bindings. Applies `.ultraThinMaterial` toolbars natively matching the aesthetic.
- Driven by `LifeListSearchManager`, which utilizes a debounce boundary (`.onChange`) to filter arrays asynchronously without lagging the visual input.
- Binds directly to SwiftData's `allRecords` using `@Query(sort: \LocalScanRecord.timestamp, order: .reverse)`. 
- **Offline Semantic Routing**: Queries filter both explicit user-facing `commonName`/`scientificName` text and invisible `semanticTags` locally embedded by the AI model entirely off-grid.
- **LazyVGrid Rendering Resilience**: To prevent fatal SwiftUI rendering engine drops when rapidly swapping multi-thousand item text collections, `LifeListSearchManager` strictly enforces explicit `.withAnimation { self.filteredScans = ... }` boundary updates cleanly forcing OS layout calculations natively offline.

### Collections (Top-Level Photo Albums)
- In `MerianSchemaV6`, users can organize `LocalScanRecord` entries into distinct `ScanCollection` buckets.
- Leverages SwiftData `@Relationship` mapping dynamically natively inside a nested 3-column `LazyVGrid`, providing an "Explore Library" modal inside `CollectionDetailView` natively to link IDs safely without duplicating exact 12MP local images.
- Instantly navigates scans from the user's library into explicit folders dynamically, protecting original creation timestamps safely.

### Memory Integrity (`ImageDownsampler` & Concurrency)
- Natively guards the iOS lifecycle against "Out of Memory" (OOM) crashes by strictly decoupling explicit `Data` buffer conversions out of SwiftUI into an isolated `ImageDownsampler` static abstraction, leveraging Core Graphics interpolations dropping massive 12MP files seamlessly into RAM sequentially rather than instantiating memory-heavy `UIImage(contentsOfFile:)` chunks across grid loads.
- **Thread Starvation Prevention**: Execution arrays natively hitting Apple's `ImageIO` functions (`CGImageSourceCreateWithURL`) are explicitly moved cleanly into `Task.detached(priority: .userInitiated)` structures. This seamlessly protects the Swift 6 global cooperative thread pool from halting the main UI rendering matrix sequentially.
- **Sandbox Resiliency**: Physical disk file references completely drop absolute path trails prior to parsing (via `.lastPathComponent`). This gracefully secures `LifeListSearchManager` from randomly discarding `Documents/` payload bytes dynamically when the Xcode Simulator uniquely randomizes native app containers per-recompilation.

## 2. Inferences & Telemetry (`InsightSheetView`)
The `InsightSheetView` is Merian's central contextual readout, triggered immediately after an Edge API loop or seamlessly opened offline via the Life List.

### Core Rendering Logic
- **Safety Critical Block**: `InsightToxicityBanner` parses `speciesData?.insightData.isPoisonous` instantly displaying red alert ribbons above the fold to guarantee hiker safety natively.
- **Ecological Validations**: Binds fallback indicators for "Not biological" or "Not a live capture" gracefully routing edge failure cases into a clean UI without hard-crashing. If an item scores `<85%` confidence, it triggers the `DiagnosticComparisonView`.
- **Life List Contextual Imagery**: When opened directly from the historical Life List, the system intelligently intercepts the UI routing and physically forces the *user's natively captured local photograph* to dominate the Hero Carousel, rather than defaulting to the Wikipedia/GBIF reference imagery. This builds profound personal connection to the data.
- **Decoupled Asynchronous Validations**: To protect rendering bounds cleanly, all asynchronous `FileManager` fetches structurally identifying historic local payloads are cleanly removed from `InsightCarouselView` and natively isolated natively into the background threaded `load` pipeline inside `InferenceEngine`.
- **Isolated Animation Engine**: Features a complex, continuously rotating 360-degree `LinearGradient` (rainbow styling) for pending AI states. To guarantee perfect 60fps frame rates without stuttering, the animation logic is rigorously decoupled and strictly bound inside a localized struct/equatable bound, completely isolating it from `CameraViewModel` SwiftUI layout redraw strikes.
- **Bookmark & Share System**: Generates standard `ShareLink` protocols referencing the `merian.app` website explicitly pulling the active `commonName` seamlessly into the native iOS Share Sheet constraints. It also enables explicit "Save to Collection" integration natively via the `.folder.badge.plus` toolbar component.
- **Optimistic UX (Deletions)**: Users can permanently obliterate local and global data securely via `.contextMenu` bounds (Library, Collections) or the Toolbar `Menu` inside Insight bounds. Instantly bounding a `.destructive` `confirmationDialog`, pressing "Delete" executes an immediate zero-latency removal from the local UI matrix, triggering a heavy `HapticManager.shared.triggerErrorThump()` drop, while securely routing physical R2 bytes and PostgreSQL rows to the `PendingCloudDeletionTask` detached background queue invisibly to not block the UI thread.

### External API Enrichment
- Spawns parallel external lookups fetching the full taxonomic classification into the visual `InsightTaxonomyTree`.
- Triggers Safari modals securely fetching Wikipedia data via a secondary decoupled asynchronous `WikipediaService` hook natively embedded in the background to not lock the UI actor during network spin-ups.

## 3. Account and Settings (`UserProfileView`)
The primary identity portal bridging local usage limits with the Supabase Ghost Session ecosystem.

### Native OAuth & Entitlements
- Implements purely native Swift `SignInWithAppleButton` and `GoogleSignInButton` SDK boundaries securely retrieving external `.idTokens`.
- Reassigns initial Anonymous IDFV GoTrue Sessions natively merging user arrays into persistent Cloud records.
- Instantly pulls explicit `RevenueCatManager.shared.isProActive` booleans conditionally hiding or throwing the `PaywallView` dynamically if they hit their daily 3-scan limit. The `PaywallView` seamlessly inherits physical system color schemes dynamically rendering in stunning Light or Dark mode.
- Renders global gamification statistics including `uniqueSpeciesCount`, `currentStreak`, `rareFinds` and `Explorer Rank` morphs dynamically entirely offline. Instead of blocking the UI on remote PostgreSQL network requests, it utilizes heavily optimized `SwiftData` `@Query` property wrappers mapping array statistics natively preventing UI lag and dropping network errors cleanly for a flawless "Digital Terrarium" profile reflection.

### Aesthetic Customizations
- Contains the `AppIconManager` allowing `Pro` users to natively swap their iOS Springboard Icon using `UIApplication.shared.setAlternateIconName` natively. This natively updates both the app boundary and the underlying `Config.xcconfig` bounds safely without requiring a restart.
- Safely hooks the `HapticsToggle` physically pausing the `AppDIContainer.shared.hapticManager` directly from user preferences.

## 4. Hardware Integrations (`AVCaptureEventInteraction`)
- Directly hooks into iOS 17.2 tactile hardware boundaries ensuring that depressing physical hardware configurations natively triggers the exact same `EnvironmentContextManager` background `MKReverseGeocodingRequest` and `WeatherService` hooks seamlessly as the screen UI.
- All points of access guarantee zero-latency capturing and GPS binding natively mapped straight into EXIF metadata directly inside the user's core iPhone Photo Roll.

## 5. UI Abstract Modularization
- The UI hierarchy strictly avoids massive structural bindings. The bottom navigational routing structure (Scans/Profile) explicitly abstracts completely out of the monolithic `CameraRootView` natively into the ultra-lightweight `CameraNavigationBarOverlay` ViewModifier. This explicitly removes hundreds of geometric recalculations protecting shutter interaction latency strictly dynamically during capture sequences.
- `UserProfileView` natively abstracts completely. The massive scrolling interface was strictly decoupled into `UserProfileHeaderView` (Avatar metadata), `UserProfileStatsView` (isolated SwiftData queries/calendar aggregations), and `UserProfileAuthSection` (decoupled OAuth networking). This preserves frame fluidity natively when fetching massive profile arrays.
