# Core Services & Singleton Managers

Merian uses a robust, globally accessible singleton architecture for core services, ensuring thread-safe, decoupled logic across the massive hardware payload matrix.

## 1. `OfflineQueueManager.swift`

**Responsibility:** The Circuit Breaker & Wilderness Cache.

- _Behavior:_ Subscribes to `NWPathMonitor` to detect active cell boundaries physically.
- Debounces active drops (`Task.sleep` for 1 sec).
- Writes captures straight to `URL.documentsDirectory` inside a SwiftData `OfflineQueuedScan` wrapper when iOS hits Zero-Service.
- _Background Sync:_ Interfaces directly with iOS's `UIApplication.shared.beginBackgroundTask` automatically syncing all taxonomy payloads when hikers come out of a dead-zone back onto WiFi securely into Supabase/R2.

## 2. `ViewfinderIntelligence.swift` (VUI)

**Responsibility:** AI Pre-Qualification & Hint Engine.

- Drops out the `AVCaptureVideoDataOutput` pixel buffers onto a `.userInitiated` CPU dispatch queue instantly evaluating the physical brightness of a scene via `CIAreaAverage`.
- Evaluates LiDAR distances (`subjectDistanceInMeters`) to instantly trigger "Move Closer" or "Too Dark" UI hint banners natively.
- Prevents expensive cloud payload calls when an unidentifiable blurry photo is actively detected physically.

## 3. `SupabaseManager.swift`

**Responsibility:** Ghost User Identity & Vault Networking.

- Listens to PostgreSQL `authStateChanges` loop securely mapping to the native UI React layer.
- Silently executes `try await client.auth.signInAnonymously()` safely inside the iOS app launch sequence strictly enabling the 3-limit "Ghost User" capability securely.

## 4. `HardwareOrchestrator.swift`

**Responsibility:** System Thermal Downscaling & Extrapolation.

- Tracks `ProcessInfo.processInfo.thermalState` via NotificationCenter.
- Iteratively downgrades framerate capabilities (`isCriticalHeatWarningActive`) from 60fps directly down to 15fps, preventing OOM loops and physical device crash vectors during long ecological hikes.

## 5. `MerianNetworkClient.swift`

**Responsibility:** HTTP Protocol Abstraction.

- Parses `.xcconfig` payloads (preventing API leakage on GitHub logs).
- Handles the direct Cloudflare R2 Uploads via transient Presigned URL generations.
- Injects `GeminiFileResponse` tokens implicitly into the Deno Edge `identify` router.

## 6. `CameraManager.swift`

**Responsibility:** AVCaptureSession Abstraction.

- Bootstraps the heavy physical hardware session constraints (`.builtInWideAngleCamera`, `.builtInLiDARDepthCamera`).
- Actively toggles hardware idle states (down-sampling framerate) exclusively when the `InsightSheetView` is functionally open on-screen to cool the device.

## 7. `WatchAcousticManager.swift` (watchOS Extension)

**Responsibility:** Wearable Acoustic Transfer.

- Dedicated strictly to the `MerianWatch` binary extension natively tracking `WatchConnectivity`.
- Offloads heavy `.m4a` bird-song vectors transparently backward to the parent iPhone offline queue natively.
