# Feature Modules and UI Architecture

Merian's UI architecture strictly adheres to a modular, glassmorphic design philosophy, ensuring maximum reuse of Swift components while safely decoupling heavy data operations from the main rendering loop to maintain a continuous 60fps framerate.

## 1. The Life List (`LifeListSearchView`, `LifeListSearchManager`)
The Life List acts as the user's primary offline biological journal. 

### Search & Filtering
- Driven by `LifeListSearchManager`, which utilizes a debounce boundary (`.onChange`) to filter arrays asynchronously without lagging the `UISearchBar` input.
- Automatically strips `UITextField.appearance().clearButtonMode` internally to avoid layout collisions with our custom clear logic gracefully.
- Binds directly to SwiftData's `allRecords` using `@Query(sort: \LocalScanRecord.timestamp, order: .reverse)`. 
- **Offline Semantic Routing**: Queries filter both explicit user-facing `commonName`/`scientificName` text and invisible `semanticTags` locally embedded by the AI model entirely off-grid.

### Collections (Top-Level Photo Albums)
- In `MerianSchemaV6`, users can organize `LocalScanRecord` entries into distinct `ScanCollection` buckets.
- Leverages SwiftData `@Relationship` mapping dynamically natively inside a nested 3-column `LazyVGrid`, providing an "Explore Library" modal inside `CollectionDetailView` natively to link IDs safely without duplicating exact 12MP local images.
- Instantly navigates scans from the user's library into explicit folders dynamically, protecting original creation timestamps safely.

### Memory Integrity (`LifeListThumbnailView`)
- Natively guards the iOS lifecycle against "Out of Memory" (OOM) crashes by strictly leveraging Core Graphics interpolations downsampling massive 12MP files into RAM sequentially rather than instantiating memory-heavy `UIImage(contentsOfFile:)` chunks across grid loads. 

## 2. Inferences & Telemetry (`InsightSheetView`)
The `InsightSheetView` is Merian's central contextual readout, triggered immediately after an Edge API loop or seamlessly opened offline via the Life List.

### Core Rendering Logic
- **Safety Critical Block**: `InsightToxicityBanner` parses `speciesData?.insightData.isPoisonous` instantly displaying red alert ribbons above the fold to guarantee hiker safety natively.
- **Ecological Validations**: Binds fallback indicators for "Not biological" or "Not a live capture" gracefully routing edge failure cases into a clean UI without hard-crashing. If an item scores `<85%` confidence, it triggers the `DiagnosticComparisonView`.
- **Bookmark & Share System**: Generates standard `ShareLink` protocols referencing the `merian.app` website explicitly pulling the active `commonName` seamlessly into the native iOS Share Sheet constraints. It also enables explicit "Save to Collection" integration natively via the `.folder.badge.plus` toolbar component.

### External API Enrichment
- Spawns parallel external lookups fetching the full taxonomic classification into the visual `InsightTaxonomyTree`.
- Triggers Safari modals securely fetching Wikipedia data via a secondary decoupled asynchronous `WikipediaService` hook natively embedded in the background to not lock the UI actor during network spin-ups.

## 3. Account and Settings (`UserProfileView`)
The primary identity portal bridging local usage limits with the Supabase Ghost Session ecosystem.

### Native OAuth & Entitlements
- Implements purely native Swift `SignInWithAppleButton` and `GoogleSignInButton` SDK boundaries securely retrieving external `.idTokens`.
- Reassigns initial Anonymous IDFV GoTrue Sessions natively merging user arrays into persistent Cloud records.
- Immediately pulls explicit `RevenueCatManager.shared.isProActive` booleans conditionally hiding or throwing the `SubscriptionPaywallView` dynamically if they hit their daily 3-scan limit.
- Renders their global `currentStreakCount` and total discovered species securely fetched from Postgres limits safely.

### Aesthetic Customizations
- Contains the `AppIconManager` allowing `Pro` users to natively swap their iOS Springboard Icon using `UIApplication.shared.setAlternateIconName` natively. This natively updates both the app boundary and the underlying `Config.xcconfig` bounds safely without requiring a restart.
- Safely hooks the `HapticsToggle` physically pausing the `AppDIContainer.shared.hapticManager` directly from user preferences.

## 4. Hardware Integrations (`AVCaptureEventInteraction`)
- Directly hooks into iOS 17.2 tactile hardware boundaries ensuring that depressing physical hardware configurations natively triggers the exact same `EnvironmentContextManager` background `CLGeocoder()` and `WeatherService` hooks seamlessly as the screen UI.
- All points of access guarantee zero-latency capturing and GPS binding natively mapped straight into EXIF metadata directly inside the user's core iPhone Photo Roll.
