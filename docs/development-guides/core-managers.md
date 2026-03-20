# Core Application Services & Managers

Merian relies heavily on a structured Singleton paradigm bound inside the strict `AppDIContainer.swift` file. These singletons control global application state efficiently without inducing excessive SwiftUI view rebuilding contexts.

## Hardware Domain

### `CameraManager`
- Direct AVFoundation abstraction explicitly tied to `.builtInLiDARDepthCamera` arrays on physical devices.
- Triggers strictly when `.handleActivePhase()` calls within `MerianApp.swift`.
- Governs `subjectDistanceInMeters`, auto-focus thresholds, thermal bounds, and frame drops safely natively inside a `DispatchQueue(label: "camera.session")`.

### `EnvironmentContextManager`
- Explicit mapping for configuring dual properties natively inside the `EnvironmentContext` dependency graph without invoking UI rerenders:
  - **CoreLocation**: Caches and strictly updates precise physics logic (`CLLocationCoordinate2D`, `altitude`, `course`).
  - **WeatherKit**: Aggregates hyper-local edge metrics like `temperature` and `condition` instantaneously natively to supplement inference payloads.
- Intelligently locks variables globally to `cacheThreshold` boundaries directly shielding the device battery pool smoothly.

### `HapticManager`
- Governs `UIImpactFeedbackGenerator` tactile bumps.
- Generates `NotificationFeedback` natively tying into success/failure workflows across the core application safely bypassing standard `AudioToolbox` imports.

## AI & Offline Synchronization

### `InferenceEngine`
- The core processing unit inside `merian/Core/AI/`.
- Dispatches securely decoupled sensor structures via `CaptureTelemetry`, explicitly forwarding `depthScaleText`, `deviceLocale`, `currentMonth`, and physical coordinate states natively out to the Supabase Node (`MerianNetworkClient.analyzeSubject`).
- Automatically filters natively against `gemini-2.5-flash` or `gemini-2.5-pro` (dynamically allocated based on user subscription tier) payloads binding the structural taxonomy strings mapped specifically right back down to native local properties.
- Responsible for mutating and triggering the "Graceful Degradation" UI bounds when network calls fail natively by dumping the payload explicitly down to `OfflineQueueManager`.

### `OfflineQueueManager`
- Dictates completely silent `URLSession` background mappings dynamically allowing the app to seamlessly stash pending physical imagery natively into the local disk partition (Document Directory).
- Explicitly registers background handlers inside `AppDelegate` safely guaranteeing `URLSession` callbacks natively execute uploads seamlessly completely apart from the main user UI grid logic.
- Utilizes a unified static abstraction `BackgroundTaskWrapper.execute(name:operation:)` natively to rigidly encapsulate active memory environments binding OS threat loops securely to `UIBackgroundTaskIdentifier` instances gracefully preventing system leaks under suspension natively.

### `ArchiveManager` (Archive Safety Protocol)
- Explicit background worker strictly mapped to protect the data of Free tier users against the Cloudflare R2 90-day global purge logic (`00004_storage_lifecycle_sync.sql`).
- Polls locally via `getAvailableDiskSpace()`.
- Dynamically `evaluateAndRescueAgingScans` queries SwiftData logs looking for `.isLocallyArchived == false` records older than 80 days strictly executed locally via `.handleActivePhase()` native UI lifecycle hooks once per day saving images directly into explicit bounds. To physically block RAM spikes triggering JetSam boundaries during batch rescues, the system completely bypasses massive `.data(from:)` array loadings. Instead, it securely cross-references the remote database edge for `image_storage_urls`, and safely streams the binary payload down securely via `URLSession.shared.download(from:)` explicitly piping the temp file cleanly over to the document partition via `FileManager.default.moveItem`. Crucially, the system structurally writes only the relative `filename` string into SwiftData rather than the `fileURL.path`. This correctly prevents Absolute Sandbox Path map breakages caused by iOS dynamically altering and randomizing container UUIDs on device reboots and physical app updates seamlessly avoiding broken image renders natively completely.
- **N+1 Query Eradication**: Completely skips sequential Supabase round-trips natively mapping the background dataset arrays. It preemptively extracts a complete array of `.identifier` strings, and sends a single `O(1)` `.in("id", ...)` PostgREST query payload cleanly pulling all storage relationships dynamically directly preventing worker starvation!

## Networking

### `MerianNetworkClient`
- Isolates physical Deno function endpoints mapping directly via `MerianEnvironment.supabaseUrl`.
- Inherently abstracts API invocations natively using a centralized `performAuthenticatedRequest` pipeline, effortlessly intercepting duplicated JWT validation layers sequentially securely mapping identity configurations locally over all 5 discrete public endpoints natively.
- Actively forces exact asynchronous REST calls (`/identify`, `/generate-upload-urls`, `/flag-issue`).
- Automatically extracts the `DeviceIdentityManager.shared.deviceId` strictly bypassing arbitrary session state dependencies smoothly executing Supabase payload pushes correctly mapped directly to the active iOS `ProcessInfo` environment.
- Safely traps `.401 Unauthorized` responses natively within `performAuthenticatedRequest`. Crucially, it completely abstracts JWT validation by delegating to `SupabaseManager.shared.getValidAuthHeaders()`, ensuring all network calls inherently benefit from the unified self-healing Ghost session fallback loops seamlessly securely.

### `SupabaseManager`
- Completely delegates the secure API boundary parsing natively wrapped into GoTrue bindings.
- Exports a singular, unified `getValidAuthHeaders() async throws -> [String: String]` abstraction. This completely consolidates the OAuth conditional checks (`Merian_HasAuthenticatedOAuth`) and automatic Ghost Session regeneration logic (using `.identifierForVendor`), ensuring a 100% success rate on stateless REST requests across `MerianNetworkClient` and `SocialGuardManager` natively.
- **DRY OAuth Abstraction**: Explicitly abstracts Apple Sign In and Google Sign In fallback mapping networks securely isolating identical duplication directly into `private func finalizeOAuthLogin`. This securely maps `.linkIdentityWithIdToken` arrays against `.signInWithIdToken` bounds avoiding massive code redundancy mathematically!
- Executes `signInAnonymously()` exclusively mapped to `.uuidString` metrics inside `.identifierForVendor`.
- Maps native Apple/Google OAuth hooks seamlessly migrating Ghost User mappings cleanly explicitly calling `RevenueCatManager.shared.linkWithSupabase()` correctly aligning payment limits securely natively.

## Telemetry & Billing

### `RevenueCatManager`
- Integrates seamlessly handling `isProActive`.
- Resolves mapping safely preventing unhandled `.purchaserInfo()` exceptions internally hooking right into identical Ghost UI bounds locally securely mapping onto `revenuecat-webhook` Edge structures directly natively.

### `PostHogManager`
- Manages anonymous telemetry flows handling `.identifyUser()` logs globally preventing lost analytic strings seamlessly across all native iOS boundary state contexts cleanly.
