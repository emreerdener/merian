# Camera and Hardware Orchestration

The optical and physical layer of the Merian application leverages Apple's precise `AVFoundation` framework wrapped behind a thermal-aware orchestrator.

## The Core Pipeline

### `CameraManager`

The lowest level integration directly interfacing with the iPhone optics.

- Instantiates the `AVCaptureSession` mapping native inputs seamlessly via `AVCaptureDevice.DiscoverySession`, intelligently prioritizing `.builtInLiDARDepthCamera` for exact physical scale, before safely falling back down through Dual and Wide-Angle matrices for base-model iOS compatibility.
- Configures parallel buffers routing actively to `AVCaptureVideoDataOutput`, `AVCaptureDepthDataOutput`, and importantly `AVCapturePhotoOutput`.
- Evaluates `photoOutput.isDepthDataDeliverySupported` during configuration recursively mapping `.isDepthDataDeliveryEnabled` downstream natively to `AVCapturePhotoSettings`. This physical validation cleanly prevents fatal `SIGABRT` / `NSInvalidArgumentException` crash instances in AVFoundation if non-LiDAR iPhones attempt depth captures dynamically.
- Actively leverages `photoOutput.isHighResolutionCaptureEnabled = true` letting Apple's underlying OS Image Signal Processor map and shrink dynamic resolution sizes, gracefully dodging explicit `48MP` RAW byte crashes completely.
- Syncs a published `@Published var isFlashEnabled` variable actively driving hardware closures mapping natively through `device.torchMode` under `.lockForConfiguration()` streams to prevent dark environmental failures dynamically. The selected hardware flash mode is automatically resolved cleanly at shutter execution natively handling edge constraints gracefully. To satisfy Swift 6 Concurrency constraints, this MainActor property is securely copied down before executing any `queue.async` background capture enclosures. Importantly, to prevent the UI thread from stuttering during rapid IPC hardware locking commands, `toggleFlash()` executes exclusively inside a background `queue.async` explicitly pushing state changes back to the Main thread upon completion.
- Secures `AVFoundation` shutter callbacks against race conditions by actively mapping `withCheckedThrowingContinuation` assignments synchronously up onto the `@MainActor` before delegating the `capturePhoto` execution to the background queue. This physically enforces memory safety and prevents permanent UI deadlocks natively.
- Throttles preview feeds linearly to conserve internal memory loads gracefully shifting between 15-60 FPS bounds seamlessly.
- **Native Hardware Interaction (`AVCaptureEventInteraction`)**: Leverages the dedicated iOS 17.2 tactile hardware API to gracefully intercept native volume buttons, the Action button, and the iPhone 16 Camera Control natively. Bound strictly on the `.began` event phase, it provides zero-latency capture parity with the system Camera app, while intelligently disabling itself dynamically when UI sheets or modals are open to prevent cross-app volume hijacking.
- **Native Optical Zoom Parsing**: Intelligently extracts the current hardware's `minAvailableVideoZoomFactor`, `maxAvailableVideoZoomFactor`, and `virtualDeviceSwitchOverVideoZoomFactors` automatically upon session initialization. Smoothly scales and maps the UI `.ultraThinMaterial` optical zoom pill to physical constraints dynamically without UI stuttering, utilizing an optimistic `@MainActor` UI frame update before locking `device.ramp(toVideoZoomFactor:withRate:)` strictly out onto the background `deviceQueue`.

### `HardwareOrchestrator`

The battery and heat protection protocol monitoring physical usage thresholds gracefully.

- Bridges the Apple internal `.thermalStateDidChangeNotification` explicitly dropping graphic resolutions and Glassmorphism shaders immediately on `.critical` or `.serious`.
- Monitors passive `isLowPowerModeEnabled` strings mapping native 24 FPS `isExpeditionModeActive` pipelines on low-battery wilderness states explicitly. This flag securely intercepts the `OfflineQueueManager` natively, seamlessly pausing asynchronous background cellular uploads to preserve critical battery power while off-grid.

### `ViewfinderIntelligence` (VUI)

An asynchronous heuristic layer blocking wasted network limits inherently.

- Drops concurrent inference limits natively tracking frame boundaries natively by natively reading the raw `CVPixelBuffer` memory bounds dynamically. To prevent internal GPU thermal bottlenecks from millions of background hardware passes, it completely abstains from instantiating any `CIContext` or `CoreImage` pipelines natively natively dropping all `CGAffineTransform` overhead. It dynamically locks the base Luma plane address (`CVPixelBufferGetBaseAddressOfPlane`) purely on the CPU, iterating byte indices recursively to evaluate total scene brightness over a `10` step subsample natively dropping thermal and battery boundaries.
- Triggers dynamic `VUIHint` prompts across the viewfinder alerting users visually (`"Too dark"`, `"Move closer"`) without executing any internet boundaries gracefully. Explicitly evaluates an optional `distance: Float?` constraint checking for subjects > 2.5 meters.
- Explicitly blocks inference pipelines from querying cloud services for AI evaluation unless the internal brightness buffer returns successfully.

### `PhotoLibraryManager`

Acts as a dedicated `PHPhotoLibrary` handler intercepting the hardware buffers securely.

- Binds `.opportunistic` `PHImageRequestOptions` gracefully extracting the most recently added native iOS Asset asynchronously to act as the Camera Gallery icon.
- Safely wraps `PHAssetCreationRequest.forAsset()` strictly bypassing the UI actor dynamically cleanly saving the unadulterated `12MP` sensor data buffer straight into the native camera roll natively. Refusing to cast these payloads to explicit visual `UIImage` boundaries ensures physical persistence of exact EXIF, GPS tracking fields, proprietary physical 3D LiDAR boundaries, and Apple Deep Fusion algorithms safely inside the users Camera Roll prior to any external cloud inference.

### `EnvironmentContextManager`

Adheres to a "Deferred Context Fetch" philosophy.
- Instead of passively tracking location continuously which impacts thermal performance and battery, it initializes an asynchronous `withCheckedContinuation` mapping purely triggered during `CameraViewModel.handleCropCompletion`.
- Resolves the absolute pinpoint `CLLocation` lock and binds directly to Apple's `WeatherKit` `WeatherService.shared`, capturing live `weatherCondition` and `weatherTemperatureF` alongside `gpsElevation`. This precise snapshot of the environment strictly empowers the Gemini AI with profound context for regional tracking and invasive logic dynamically.
