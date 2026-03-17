# Feature Modules and UI Architecture

Merian's UI architecture strictly adheres to a modular, glassmorphic design philosophy, ensuring maximum reuse of Swift components while safely decoupling heavy data operations from the main rendering loop to maintain a continuous 60fps framerate.

## 1. The Life List (`LifeListSearchView`, `LifeListSearchManager`)
The Life List acts as the user's primary offline biological journal. 

### Search & Filtering
- **Native iOS 18 Bottom Search Bar**: Integrates the native iOS 18 `.searchable` and `.searchDictationBehavior(.inline)` modifiers ripped out of the top drawer and dynamically pinned to the bottom placement via `DefaultToolbarItem(kind: .search, placement: .bottomBar)`.
- **Dictation & Clear Mechanics**: Relies strictly on native SwiftUI dictated microphone capabilities and standard 'X' overlays, requiring zero custom `UIViewRepresentable` bindings. Applies `.ultraThinMaterial` toolbars natively matching the aesthetic.
- Driven by `LifeListSearchManager`, which utilizes a debounce boundary (`.onChange`) to filter arrays asynchronously without lagging the visual input.
- **Dynamic Filter Bar Eradication**: The UI actively tracks the `isSearchFocused` state via the `.searchable(isPresented:)` binding alongside the `searchManager.searchQuery`. The moment a user taps the native iOS search field to bring up the keyboard or inputs a query, the horizontal Category filter pill bar dynamically unmounts to maximize the `LazyVGrid` thumbnail rendering space cleanly.
- Binds directly to SwiftData's `allRecords` using `@Query(sort: \LocalScanRecord.timestamp, order: .reverse)`. 
- **Offline Semantic Routing**: Queries filter both explicit user-facing `commonName`/`scientificName` text and invisible `semanticTags` locally embedded by the AI model entirely off-grid.
- **LazyVGrid Rendering Resilience**: To prevent fatal SwiftUI rendering engine drops when rapidly swapping multi-thousand item text collections, `LifeListSearchManager` strictly enforces explicit `.withAnimation { self.filteredScans = ... }` boundary updates cleanly forcing OS layout calculations natively offline.

### Collections (Top-Level Photo Albums)
- In `MerianSchemaV6`, users can organize `LocalScanRecord` entries into distinct `ScanCollection` buckets.
- Leverages SwiftData `@Relationship` mapping dynamically natively inside a nested 3-column `LazyVGrid`, providing an "Explore Library" modal inside `CollectionDetailView` natively to link IDs safely without duplicating exact 12MP local images.
- Instantly navigates scans from the user's library into explicit folders dynamically, protecting original creation timestamps safely.

### Primary Navigation Overlay
- **Top Bar Alignment**: The `Scans` and `Profile` primary actions are strictly hoisted to the `.topBarLeading` and `.topBarTrailing` native toolbar placements mapped securely inside the `PrimaryNavigationOverlay` modifier. 
- **Legibility Gradient**: To maintain critical text contrast ("Scans", "Profile") against complex or blown-out real world camera feed lighting conditions, a dark gradient mapping `[.black.opacity(0.9), .black.opacity(0.4), .clear]` is dynamically anchored over the safe area via `CameraRootView`. This smoothly darkens the upper bounds by an extra 180pts, ensuring the white text and SF Symbols remain prominently visible natively without breaking the fullscreen immersive glassmorphism experience.

### Memory Integrity (`ImageDownsampler` & Concurrency)
- Natively guards the iOS lifecycle against "Out of Memory" (OOM) crashes by strictly decoupling explicit `Data` buffer conversions out of SwiftUI into an isolated `ImageDownsampler` static abstraction, leveraging Core Graphics interpolations dropping massive 12MP files seamlessly into RAM sequentially rather than instantiating memory-heavy `UIImage(contentsOfFile:)` chunks across grid loads.
- **Thread Starvation Prevention**: Execution arrays natively hitting Apple's `ImageIO` functions (`CGImageSourceCreateWithURL`) are explicitly moved cleanly into `Task.detached(priority: .userInitiated)` structures. This seamlessly protects the Swift 6 global cooperative thread pool from halting the main UI rendering matrix sequentially.
- **Historical Payload Override**: To entirely avoid destroying device cellular data limits downloading massive multi-gigabyte historical image files physically into iOS, the hydration engine (`ScanRepository.syncHistoricalScansDown`) smartly forces the SwiftData payload `.localImagePath = nil` while simultaneously overriding `.referenceImageUrl` to dynamically hold the specific historical Cloudflare R2 URL. This explicitly routes all native frontend components into utilizing Apple's asynchronous cache layers dynamically downloading exactly what the UI needs exactly when the user views it. Specifically, `LifeListThumbnailView` natively bounds `.localImagePath` as a nullable `String?`. If missing, the structural component completely skips attempting to read native Sandboxed Document structures, automatically routing to the `.referenceImageUrl` executing a robust `fetchNetworkFallback` via `URLSession` natively without any redundant conditional `if let` blocks required on the caller side.
- **Sandbox Resiliency**: Physical disk file references completely drop absolute path trails prior to parsing (via `.lastPathComponent`). This gracefully secures `LifeListSearchManager` from randomly discarding `Documents/` payload bytes dynamically when the Xcode Simulator uniquely randomizes native app containers per-recompilation.

## 2. Inferences & Telemetry (`InsightSheetView`)
The `InsightSheetView` is Merian's central contextual readout, triggered immediately after an Edge API loop or seamlessly opened offline via the Life List.

### Core Rendering Logic
- **Safety Critical Block**: `InsightToxicityBanner` parses `speciesData?.insightData.isPoisonous` instantly displaying red alert ribbons above the fold to guarantee hiker safety natively.
- **Ecological Validations**: Binds fallback indicators for "Not biological" or "Not a live capture" gracefully routing edge failure cases into a clean UI without hard-crashing. If an item scores `<85%` confidence, it triggers the `DiagnosticComparisonView`.
- **Life List Contextual Imagery**: When opened directly from the historical Life List, the system intelligently intercepts the UI routing and physically forces the *user's natively captured local photograph* to dominate the Hero Carousel, rather than defaulting to the Wikipedia/GBIF reference imagery. This builds profound personal connection to the data.
- **Decoupled Asynchronous Validations**: To protect rendering bounds cleanly, all asynchronous `FileManager` fetches structurally identifying historic local payloads are cleanly removed from `InsightCarouselView` and natively isolated natively into the background threaded `load` pipeline inside `InferenceEngine`.
- **Isolated Animation Engine**: Features a complex, continuously rotating 360-degree `LinearGradient` (rainbow styling) for pending AI states. To guarantee perfect 60fps frame rates without stuttering, the animation logic is rigorously decoupled and strictly bound inside a localized struct/equatable bound, completely isolating it from `CameraViewModel` SwiftUI layout redraw strikes.
- **Visual Virality & Sharing**: Implements a fully native `UIActivityViewController` pipeline explicitly built to stage rich imagery payloads perfectly. When tapped, the system dynamically intercepts the actual photograph (live capture, local disk cache, or safely pulled Cloudflare URL while actively discarding Wikipedia reference limits), drops the `UIImage` natively into `index 0` of the Apple Share Sheet, and prepends a custom scientific identification string plus the `merian.app` Universal Link directly into the iMessage/Instagram story payload for massive downstream conversion clicks. It also enables explicit "Add to Collection" integration natively via the `.folder.badge.plus` toolbar component.
- **Exporting Raw Photography (`Save my photos`)**: Inside the toolbar menu, users can extract their biological captures directly to the iOS Camera Roll universally without triggering the Auto-Save settings. It actively parses `PhotoLibraryManager.saveImageManual(imageData:)` with `.addOnly` permissions natively filtering the `inferenceEngine` remote payload arrays, securely grabbing live captures, historical local caches, and remote Cloudflare R2 links (`media.merian.app`), while simultaneously explicitly hard-ignoring Wikipedia/GBIF external reference URIs to prevent polluting the user's local photo albums with third-party textbook imagery.
- **Optimistic UX (Deletions)**: Users can permanently obliterate local and global data securely via `.contextMenu` bounds (Library, Collections) or the Toolbar `Menu` inside Insight bounds. Instantly bounding a `.destructive` `confirmationDialog`, pressing "Delete" executes an immediate zero-latency removal from the local UI matrix, triggering a heavy `HapticManager.shared.triggerErrorThump()` drop, while securely routing physical R2 bytes and PostgreSQL rows to the `PendingCloudDeletionTask` detached background queue invisibly to not block the UI thread.
### External API Enrichment
- Spawns parallel external lookups fetching the full taxonomic classification into the visual `InsightTaxonomyTree`.
- Triggers Safari modals securely fetching Wikipedia data via a secondary decoupled asynchronous `WikipediaService` hook natively embedded in the background to not lock the UI actor during network spin-ups.

## 3. Account (`UserProfileView`) and Settings (`SettingsView`)
The primary identity portal bridging local usage limits with the Supabase Ghost Session ecosystem.

### Native OAuth & Entitlements
- Implements purely native Swift `SignInWithAppleButton` and `GoogleSignInButton` SDK boundaries securely retrieving external `.idTokens`.
- Reassigns initial Anonymous IDFV GoTrue Sessions natively merging user arrays into persistent Cloud records.
- Instantly pulls explicit `RevenueCatManager.shared.isProActive` booleans conditionally hiding or throwing the `PaywallView` dynamically if they hit their daily 3-scan limit. The `SettingsView` natively leverages this observed property to dynamically label the user's current subscription tier (e.g. "Merian Pro" or "Free") explicitly inside the Manage Plan row. The `PaywallView` seamlessly inherits physical system color schemes dynamically rendering in stunning Light or Dark mode.
- Renders global gamification statistics including `uniqueSpeciesCount` and `currentStreak` in the stats grid, while evaluating the user's `persona` (Explorer Rank) dynamically purely offline within the profile header. Instead of blocking the UI on remote PostgreSQL network requests, it utilizes heavily optimized `SwiftData` `@Query` property wrappers mapping array statistics natively preventing UI lag and dropping network errors cleanly for a flawless "Digital Terrarium" profile reflection.

### Aesthetic Customizations
- Contains the `AppIconManager` allowing `Pro` users to natively swap their iOS Springboard Icon using `UIApplication.shared.setAlternateIconName` natively. This natively updates both the app boundary and the underlying `Config.xcconfig` bounds safely without requiring a restart.

### Field & Hardware Options
- **Expedition Mode**: Manually throttles the `HardwareOrchestrator` to 24fps and disables intensive visual blurs to preserve battery.
- **Legacy Viewfinder**: Allows users to manually pause the real-time ViewfinderIntelligence hints. This is set to ON by default on modern devices (iPhone 14+) to prevent excessive thermal loads.
- **System Haptics & Camera Roll**: UserDefaults bindings to dynamically skip `HapticManager` calls or directly prevent `PhotoLibraryManager` from pushing raw buffer bytes into the iOS Photos ecosystem.

### Privacy & Science
- **Geoprivacy Control (`SettingsGeoprivacyView`)**: Extracted into a dedicated sub-page providing comprehensive user education on coordinate tracking natively. Contains detailed explanations for `Open` (raw sharing for researchers), `Obscured` (50km radius randomized blurring), and `Private` (completely hidden from discovery feed). Modifying selections elegantly cascades a Supabase edge update to the `users` PostgreSQL table immediately in the background via closures. Completely accessible to Ghost Users mapping natively to their anonymous UUID.
- **Export Life List (DwC-A)**: *(Auth Required)* Connects to the `/export-dwca` Deno task through a `Task.detached` thread to pull a `.zip` archive URL back efficiently natively rendering a `ShareLink` payload safely out of memory constraints. Fallback "Sign in with Apple" prompt prevents anonymous users from generating payloads before creating an account.

### Danger Zone & Data Lifecycle
- **Local Cache Management**: Allows dumping `ImageCache.shared` and orphaned `/Caches/` JPG payloads directly off the iPhone flash memory.
- **Account Eraaaasure**: Features a hardline "Delete Account & Data" action executing a native `.destructive` `.confirmationDialog`. This forces a sequential 4-part wipe: triggering the Deno `/safe-delete` endpoint natively, destroying the GoTrue identity locally (`signOut`), and explicitly dumping the entire device SQLite boundary dynamically (`ScanRepository.shared.purgeAllData`) pushing the user gracefully back into the generic Camera interface smoothly without crashing.


## 4. Hardware Integrations (`AVCaptureEventInteraction`)
- Directly hooks into iOS 17.2 tactile hardware boundaries ensuring that depressing physical hardware configurations natively triggers the exact same `EnvironmentContextManager` background `MKReverseGeocodingRequest` and `WeatherService` hooks seamlessly as the screen UI.
- All points of access guarantee zero-latency capturing and GPS binding natively mapped straight into EXIF metadata directly inside the user's core iPhone Photo Roll.

## 5. UI Abstract Modularization
- The UI hierarchy strictly avoids massive structural bindings. The primary navigational routing structure (Scans/Profile) explicitly abstracts completely out of the monolithic `CameraRootView` natively into the ultra-lightweight `PrimaryNavigationOverlay` ViewModifier. To retain perfect iOS visual consistency, it binds safely into a true iOS `ToolbarItem(placement: .topBarLeading / .topBarTrailing)`. The native UIKit `.toolbarBackground(.hidden, for: .navigationBar)` is applied to float cleanly over the live camera session. All core camera utilities (Flash Toggle, Camera Roll Picker) are tightly consolidated into an `HStack(alignment: .bottom)` explicitly anchoring them to the bottom/left corners while staggering the central Shutter button dynamically `32pts` higher. This precisely mimics the physical ergonomic layout curve natively shipped in the core Apple iOS Camera app.
- `UserProfileView` natively abstracts completely. The massive scrolling interface was strictly decoupled into `UserProfileHeaderView` (Avatar metadata, Explorer Persona, Auth Status routing), `UserProfileStatsView` (isolated SwiftData queries/calendar aggregations)...
