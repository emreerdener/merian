# Camera and Hardware Orchestration

The optical and physical layer of the Merian application leverages Apple's precise `AVFoundation` framework wrapped behind a thermal-aware orchestrator.

## The Core Pipeline

### `CameraManager`

The lowest level integration directly interfacing with the iPhone optics.

- Instantiates the `AVCaptureSession` mapping native inputs seamlessly via `AVCaptureDevice.DiscoverySession`, strictly prioritizing `.builtInLiDARDepthCamera` for exact physical scale, explicitly stripping out natively nested physical Zoom heuristics because Apple locks LiDAR exclusively to Wide-Angle models structurally.
- Configures parallel buffers routing actively to `AVCaptureVideoDataOutput`, `AVCaptureDepthDataOutput`, and importantly `AVCapturePhotoOutput`.
- Evaluates `photoOutput.isDepthDataDeliverySupported` during configuration recursively mapping `.isDepthDataDeliveryEnabled` downstream natively to `AVCapturePhotoSettings`. This physical validation cleanly prevents fatal `SIGABRT` / `NSInvalidArgumentException` crash instances in AVFoundation if non-LiDAR iPhones attempt depth captures dynamically.
- Actively leverages `photoOutput.isHighResolutionCaptureEnabled = true` letting Apple's underlying OS Image Signal Processor map and shrink dynamic resolution sizes, gracefully dodging explicit `48MP` RAW byte crashes completely.
- Syncs a published `@Published var isFlashEnabled` variable actively driving hardware closures mapping natively through `device.torchMode` under `.lockForConfiguration()` streams to prevent dark environmental failures dynamically. The selected hardware flash mode is automatically resolved cleanly at shutter execution natively handling edge constraints gracefully. To satisfy Swift 6 Concurrency constraints, this MainActor property is securely copied down before executing any `queue.async` background capture enclosures. Importantly, to prevent the UI thread from stuttering during rapid IPC hardware locking commands, `toggleFlash()` executes exclusively inside a background `queue.async` explicitly pushing state changes back to the Main thread upon completion.
- Configures `setupSession()` initialization natively routing it entirely onto an underlying background `queue.async` loop inside `init()`, entirely eliminating synchronous >500ms blockings on the UI Main Thread for instant seamless boots.
- Throttle dynamic 60fps LiDAR physical bounding data loops (`depthDataOutput`) to strict 3fps limitations actively by managing an injected low-level `NSLock()` throttler structurally locking down Apple Core Processor flooding, ensuring physical thermal reductions instantaneously prior to triggering `@MainActor` jumps contextually. 
- Secures `AVFoundation` shutter callbacks against race conditions by actively mapping `withCheckedThrowingContinuation` assignments synchronously up onto the `@MainActor` before delegating the `capturePhoto` execution to the background queue. This physically enforces memory safety and prevents permanent UI deadlocks natively.
- Throttles preview feeds linearly to conserve internal memory loads gracefully shifting between 15-60 FPS bounds seamlessly.
- **Native Hardware Interaction (`AVCaptureEventInteraction`)**: Leverages the dedicated iOS 17.2 tactile hardware API to gracefully intercept native volume buttons, the Action button, and the iPhone 16 Camera Control natively. Bound strictly on the `.began` event phase, it provides zero-latency capture parity with the system Camera app, instantly grabbing a live `CLLocation` snapshot to bind coordinates directly into the hardware flash, while intelligently disabling itself dynamically when UI sheets or modals are open to prevent cross-app volume hijacking.
- **Tap-to-Focus & Tap-to-Expose**: Leverages `.captureDevicePointConverted` internally via `CameraPreviewView` translating strict UI touches flawlessly into hardware bounds. Offloads native `lockForConfiguration` adjustments securely to the background queue initializing `.autoFocus` and `.autoExpose` tracking physically against tapped coordinate interests without deadlocking. Seamlessly enables `isSubjectAreaChangeMonitoringEnabled`, securely registering `.AVCaptureDeviceSubjectAreaDidChange` loops resetting the focus mapping gracefully back to continuous tracking the moment physical iPhone rotation dynamically detects physical pan-away seamlessly.

### `HapticManager`

Centralizes UI and structural physical vibrations actively protecting UI Thread framerates seamlessly.

- Instantiates ".heavy", ".light", ".rigid", ".medium" `UIImpactFeedbackGenerator` motors silently waking them sequentially inside `init()` using `.prepare()`. 
- Global pre-warming universally bounds `AppDIContainer.shared.hapticManager` directly into `CameraViewModel` Shutter callbacks and `ImageCropperView` crop confirmations, decisively eliminating the 15+ millisecond stutter natively dropping frames caused by generating uninitialized "cold" taptic engines concurrently to physical input bounds.

### `HardwareOrchestrator`

The battery and heat protection protocol monitoring physical usage thresholds gracefully.

- Bridges the Apple internal `.thermalStateDidChangeNotification` explicitly dropping graphic resolutions and Glassmorphism shaders immediately on `.critical` or `.serious`.
- Monitors passive `isLowPowerModeEnabled` strings mapping native 24 FPS `isExpeditionModeActive` pipelines on low-battery wilderness states explicitly. This flag securely intercepts the `OfflineQueueManager` natively, seamlessly pausing asynchronous background cellular uploads to preserve critical battery power while off-grid.

### `ViewfinderIntelligence` (VUI)

An asynchronous heuristic layer blocking wasted network limits inherently.

- Drops concurrent inference limits natively tracking frame boundaries by strictly utilizing a generic `NSLock` natively evaluating generic `CFAbsoluteTimeGetCurrent()` thresholds inherently on the background memory queue. This inherently drops native iOS scheduler pipeline floods, intelligently dropping 60fps frame callbacks down to 3fps *before* forcing expensive thread boundary jumps out to the `@MainActor`. To prevent internal GPU thermal bottlenecks from millions of background hardware passes, it completely abstains from instantiating any `CIContext` or `CoreImage` pipelines natively natively dropping all `CGAffineTransform` overhead. It dynamically locks the base Luma plane address (`CVPixelBufferGetBaseAddressOfPlane`) purely on the CPU, iterating byte indices recursively to evaluate total scene brightness over a `10` step subsample natively dropping thermal and battery boundaries.
- **Initialization Suppression**: To prevent the OS Image Signal Processor's initial low-light boot sequence from triggering false-positive alerts, `CameraManager` explicitly suspends VUI evaluation (`pauseAnalysis(for: 2.5)`) for the first 2.5 seconds upon camera start or restoration from an idle state.
- Triggers dynamic `VUIHint` prompts across the viewfinder alerting users visually (`"Too dark"`, `"Move closer"`) without executing any internet boundaries gracefully. Explicitly evaluates an optional `distance: Float?` constraint checking for subjects > 2.5 meters.
- Explicitly blocks inference pipelines from querying cloud services for AI evaluation unless the internal brightness buffer returns successfully.

### `PhotoLibraryManager`

Acts as a dedicated `PHPhotoLibrary` handler intercepting the hardware buffers securely.

- Binds `.opportunistic` `PHImageRequestOptions` gracefully extracting the most recently added native iOS Asset asynchronously to act as the Camera Gallery icon. All internal variable callbacks (such as mutating `latestThumbnail` instances) are explicitly guarded structurally inside asynchronous `Task { @MainActor in }` loops internally dropping implicit iCloud data fetch thread concurrency panics smoothly.
- Safely wraps `PHAssetCreationRequest.forAsset()` strictly bypassing the UI actor dynamically cleanly saving the unadulterated `12MP` sensor data buffer straight into the native camera roll natively. Refusing to cast these payloads to explicit visual `UIImage` boundaries ensures physical persistence of exact EXIF GPS tracking fields, proprietary physical 3D LiDAR boundaries, and Apple Deep Fusion algorithms safely inside the users Camera Roll natively. Crucially, the save logic integrates zero-latency spatial coordinates from `EnvironmentContextManager`, injecting them natively as `PHAssetCreationRequest.location` payloads securely prior to any external cloud inference. Evaluation of `PHPhotoLibrary.authorizationStatus` natively operates smoothly: if the permission state evaluates to `.notDetermined`, it elegantly cascades an asynchronous `requestAuthorization` suspend-call executing `performChanges` without dropping silent failure boundaries.
- **Historical Data Extraction**: When a user selects a photo from their library natively, the manager securely pulls the underlying `PHAsset` directly via its local identifier, extracting the original GPS coordinate location and Native Creation Date to align AI context natively to the historical timestamp of the photo capture, bypassing the current physical device location completely.

### `EnvironmentContextManager`

Adheres to a "Live Context Tracking" continuous background philosophy during the camera lifecycle.
- Instead of passively tracking location exclusively after cropping (which caused zero-EXIF bugs for hardware shutters), it initializes a continuous `locationManager.startUpdatingLocation()` internally whenever the camera viewport is physically visible. It safely terminates updates on viewport disappearance to save battery. The immediate `cachedLocation` is extracted flawlessly with absolute zero-latency precisely when `CameraViewModel.executeCapture` runs natively, binding physical coordinates straight down into the `PhotoLibraryManager` payload natively.
- Resolves the absolute pinpoint `CLLocation` lock and binds directly to Apple's `WeatherKit` `WeatherService.shared`, capturing live `weatherCondition` and `weatherTemperatureF` alongside `gpsElevation`. It also concurrently executes `CLGeocoder().reverseGeocodeLocation` to accurately map a `locationName` explicitly. This precise snapshot of the environment strictly empowers the Gemini AI with profound context for regional tracking and invasive logic dynamically, while also persisting UI metrics in the offline Life List. **(Note: This natively requires the exact `com.apple.developer.weatherkit` property mapped as `true` in `project.yml` entitlements to bind correctly, otherwise it silently fails returning `nil` across both parameters.)**
- **Historical Weather & Location Backfilling**: Uses a dedicated `fetchHistoricalContext` executing dynamic temporal range queries purely using `WeatherKit` by querying `.hourly(startDate: date, endDate: date.addingTimeInterval(3600))`, while mapping past `CLGeocoder` pins. This physically maps backwards in time securely allowing Library uploads to query exact environment conditions years locally without external servers.
- During coordinate fetching loops, `EnvironmentContextManager` actively defers its CPU locks *beneath* structural Optimistic UI executions manually deployed within `CameraViewModel`. Crucially, bounds a strict OS `Task { Task.sleep }` 2.0-second delay natively actively capturing and nullifying `activeContinuationWrapper = nil` before resuming the coordinate callback returning `nil`. This simultaneously prevents satellite acquisitions in deep forest domains from triggering infinite "Acquiring coordinates..." loops while structurally avoiding fatal Swift Continutation crash faults caused by native runtime double-resumes.
