# Core Services & Singleton Managers

Merian uses a robust, globally accessible singleton architecture for core services, ensuring thread-safe, decoupled logic across the massive hardware payload matrix.

## 1. `OfflineQueueManager.swift`

**Responsibility:** The Circuit Breaker & Wilderness Cache.

- _Behavior:_ Subscribes to `NWPathMonitor` to detect active cell boundaries physically.
- Debounces exactly 1.0 second (`Task.sleep`) upon connection restoration to prevent thrashing.
- Writes captures straight to `URL.documentsDirectory` inside a SwiftData `OfflineQueuedScan` wrapper when iOS hits Zero-Service.
- _Background Sync:_ Wrapped within a strict 30-second `UIBackgroundTaskIdentifier` iOS limit to generate presigned staging URLs, the module actively immediately terminates execution loops on timeouts gracefully without corrupting local records. It natively interfaces directly with `URLSessionConfiguration.background`, handing the physical R2 `.jpeg` uploads securely over to the host OS. Before queueing, it downscales the exact 1024x1024 `ImageCropperView` 1:1 footprint down to a lightweight 1024px payload inside the temporary `URL.cachesDirectory`, enabling massive bandwidth reduction over 3G. The pipeline explicitly intercepts the app lifecycle using `AppDelegate` to safely execute the `backgroundCompletionHandler` exclusively on the main thread, satisfying iOS watchdog timers upon completion and purging the cache. Furthermore, the final `analyzeSubject` downstream edge inference is also heavily protected inside the URLSession callback natively utilizing a dedicated `UIBackgroundTaskIdentifier` boundary preventing iOS execution drops during slow connections. During block map loops mapping 50+ cached files securely into URLRequests, the loop uniquely hoists explicit `@MainActor` property captures (like `backgroundSession`) explicitly _outside_ the `for` loop iteration entirely natively bypassing OS-level context switching stutter during high-volume sync sequences.

## 1.5 `AppDIContainer.swift`

**Responsibility:** Centralized Dependency Injection.

- Cleans up `MerianApp.swift` completely by instantiating every singleton manager in one unified file.
- Exposes a `.injectAppDependencies()` modifier securely allowing SwiftUI components to safely receive environment objects without implicit initialization overhead on root views.
- Handles standard lifecycle events (Background, Inactive, Active) gracefully mapping tasks such as queuing ongoing inferences automatically into the background sync process when the user closes the app mid-scan.

## 1.6 `EnvironmentContextManager.swift`

**Responsibility:** Deferred Location & Weather Payload Generator.

- Implements a precise "Deferred Context Fetch" pattern natively to drastically conserve device battery life. It refuses to initialize continuous or `startUpdatingLocation` loops asynchronously.
- Instantly extracts the `CLLocation` coordinates alongside `altitude` directly upon shutter press using a dynamically checked continuation callback on `CLLocationManager.requestLocation()`.
- Fetches real-time localized contexts via `WeatherKit` gracefully returning the active condition alongside degree readings (`weatherTemperatureF`) exclusively bounding the current scene into a rich API envelope passed towards the inference layer.

## 1.7 `ScanRepository.swift`

**Responsibility:** Model Abstraction Layer.

- Securely bounds logic retrieving or modifying the physical `SwiftData` LocalScanRecord model containers avoiding scattered `@Query` operations and explicit persistence rules natively leaking into view controllers.

## 2. `ViewfinderIntelligence.swift` (VUI)

**Responsibility:** AI Pre-Qualification & Hint Engine.

- Drops out the `AVCaptureVideoDataOutput` pixel buffers onto a `.userInitiated` CPU dispatch queue instantly evaluating the physical brightness of a scene natively by locking the `CVPixelBuffer` and recursively mapping the hardware Luma channel (Plane 0) over raw CPU arrays.
- Evaluates LiDAR distances checking whether the explicit `distance: Float?` exceeds thresholds iteratively (e.g. `> 2.5`), instantly triggering "Move Closer" or "Too Dark" UI hint banners natively without hallucinating on base-model iPhones without depth arrays.
- Prevents expensive cloud payload calls when an unidentifiable blurry photo is actively detected physically.

## 3. `DeviceIdentityManager.swift`

**Responsibility:** Keychain IDFV Identity & Secure Device Tracking.

- Intercepts physical instantiation natively requesting `UIDevice.current.identifierForVendor` (iOS) or `WKInterfaceDevice.current().identifierForVendor` (watchOS) as a persistent anonymous tracking identifier.
- Writes exclusively into the iOS Security `Keychain` framework bypassing `UserDefaults` preventing silent UUID recreation.
- Actively protects explicitly against background data-loss natively: During deep-background `URLSession` awakening events where the user hasn't unlocked their iPhone, `SecItemCopyMatching` natively returns `errSecInteractionNotAllowed`. The manager explicitly intercepts this locking state securely returning the active OS token (`identifierForVendor`) completely preventing the system from incorrectly assuming a missing ID and wiping the Keychain.
- Binds hardware strictly via the `user_id` parameter directly into every Supabase Edge Function `/identify` call completely bypassing local token expirations.

## 4. `SupabaseManager.swift`

**Responsibility:** Authenticated State & Vault Networking.

- Listens to PostgreSQL `authStateChanges` loop securely mapping to the native UI React layer for future authenticated accounts.
- Acts as a strict protector against Data Loss: During `initializeGhostSession()`, it specifically catches `AuthError` responses targeting exactly `sessionNotFound` limits. By distinguishing actual unauthenticated states from temporary network offline limits and expired Session Token loops, it actively prevents `signInAnonymously()` from wiping out User Pro states and Apple IDs via session overlaps.
- Enforces explicitly unified split-brain identity pipelines by completely disregarding the generated Supabase Ghost `user.id` upon authentication mapping. Instead, it maps `DeviceIdentityManager.shared.deviceId` directly to `RevenueCatManager` and `PostHogManager`.

## 5. `HardwareOrchestrator.swift`

**Responsibility:** System Thermal Downscaling & Extrapolation.

- Tracks `ProcessInfo.processInfo.thermalState` via NotificationCenter.
- Iteratively downgrades framerate capabilities (`isCriticalHeatWarningActive`) from 60fps directly down to 15fps, preventing OOM loops and physical device crash vectors during long ecological hikes.

## 6. `MerianNetworkClient.swift`

**Responsibility:** HTTP Protocol Abstraction.

- Parses `.xcconfig` payloads (preventing API leakage on GitHub logs).
- Handles the direct Cloudflare R2 Uploads via transient Presigned URL generations.
- Injects `r2ObjectKey` tokens implicity into the Deno Edge `identify` router, shifting the LLM upload boundary strictly to the Cloudflare gateway.

## 7. `CameraManager.swift`

**Responsibility:** AVCaptureSession Abstraction.

- Bootstraps the heavy physical hardware session constraints seamlessly instantiating `AVCaptureDevice.DiscoverySession` prioritizing `.builtInLiDARDepthCamera` hardware bounds before recursively failing down through standard Wide-Angle inputs.
- Actively leverages `isHighResolutionCaptureEnabled` to prevent iOS 16 fallback crash warnings cleanly on dynamic iPhone Pro modules.
- Actively toggles hardware idle states (down-sampling framerate) exclusively when the `InsightSheetView` is functionally open on-screen to cool the device.

## 8. `WatchAcousticManager.swift` (watchOS Extension)

**Responsibility:** Wearable Acoustic Transfer.

- Dedicated strictly to the `MerianWatch` binary extension natively tracking `WatchConnectivity`.
- Offloads heavy `.m4a` bird-song vectors transparently backward to the parent iPhone offline queue natively.

## 9. `UsageManager.swift`

**Responsibility:** Free-Tier Usage Limit Enforcement.

- Tracks usage bounds directly against `DeviceIdentityManager.shared.deviceId`.
- Grants 3 free scans per 24 hours UTC, actively resetting local quotas daily.
- Triggers the application paywall if physically exhausted before completing further backend Edge executions over the Cloudflare grid.

## 10. `InferenceEngine.swift`

**Responsibility:** AI Execution & State Management.

- Coordinates all physical cloud validations (`MerianNetworkClient`) natively with UI interaction.
- Extracts `gpsLatitude` and `weatherCondition` context natively transferring it to the `/identify` API.
- Explictly prevents UI shutter lag by wrapping the heavy `CGImageSourceCreateThumbnailAtIndex` operations and physical `URL.documentsDirectory` file-system writes in `Task.detached(priority: .userInitiated)` hooks. This offloads synchronous CoreGraphics and SwiftData write overhead off the `@MainActor`. Furthermore, to eradicate local sandbox storage bloat, it explicitly writes the lightweight 1:1 `compressedData` thumbnail generated by the `ImageCropperView` (~300KB) into the documents directory rather than the heavy 12MP original, preserving a 60fps camera viewfinder smoothly while concurrently pushing the `downsampleLocalPayload` pipeline back down the native thread. This identical `Task.detached` pattern is aggressively repeated during Life List rehydration (`load(from: LocalScanRecord)`) natively forcing heavy `Data(contentsOf:)` local filesystem buffer operations entirely off the Main Thread preventing severe frame-rate stuttering when a user clicks a historical entity in their grid natively.
- Acts as the explicit gatekeeper for `GamificationManager` and `UsageManager`; it ONLY triggers a successful scan statistic and gamification badge if the Gemini Edge infrastructure returns a confidence score `> 0.0`.
- Catches network drops and cancellation states (`URLError`), intelligently deferring captures explicitly back to the `OfflineQueueManager` for physical local caching rather than updating usage limits.

## 11. `PhotoLibraryManager.swift`

**Responsibility:** Secure Camera Roll Integrations.

- Resolves explicit `PHPhotoLibrary.authorizationStatus` boundaries purely on the UI thread without silently crashing the App.
- Securely extracts exactly `1` asset (the most recent photo) bounded aggressively using an `NSSortDescriptor(key: "creationDate", ascending: false)` constraint.
- Seamlessly acts as the passive bridge capturing `URL.documentsDirectory` 12MP payloads securely downstream straight into the Apple physical Camera Roll safely utilizing `PHAssetCreationRequest.forAsset()` the second a user pulls the shutter trigger. This entirely bypasses traditional `UIImage` extraction, explicitly guaranteeing that deep metadata, GPS EXIF attributes, Deep Fusion vectors, and physical 3D LiDAR maps are securely written to the Camera Roll natively.

## 11.5 `ArchiveManager.swift`

**Responsibility:** Batch Photo Library Syncing & Storage Limits.

- Proactively halts syncing and alerts the user if `getAvailableDiskSpace()` falls below a strict 500MB safety threshold, preventing hard iOS out-of-storage crashes.
- Offloads heavy multimegabyte local disk I/O reads natively. Inside `downloadToLocalLibrary(url:)`, it explicitly executes `Data(contentsOf: url)` within a `Task.detached(priority: .userInitiated)` hooks to prevent the 60fps `@MainActor` UI Viewfinder thread from stuttering or freezing when archiving massive high-resolution captures.

## 12. `HapticManager.swift`

**Responsibility:** Intuitive Vibration Feedback & UI Response.

- Strictly declared as an `@MainActor` singleton natively to intercept and instantly execute `UIImpactFeedbackGenerator` boundaries securely without triggering generic thread-safety crashes from background SDKs parsing on child threads.

## 13. `SocialGuardManager.swift`

**Responsibility:** Moderation RLS Overrides & Toxicity Preventions.

- Completely decouples blocking executions away from Supabase Native RLS (Row Level Security). Instead, it abstracts the boundary directly to a serverless Edge function (`/functions/v1/block-user`).
- Automatically intercepts the internal hardware UUID (`DeviceIdentityManager.shared.deviceId`) injecting it cleanly as the `blocker_id`, ensuring completely anonymous moderation actions reliably process.
