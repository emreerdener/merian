# Camera and Hardware Orchestration

The optical and physical layer of the Merian application leverages Apple's precise `AVFoundation` framework wrapped behind a thermal-aware orchestrator.

## The Core Pipeline

### `CameraManager`

The lowest level integration directly interfacing with the iPhone optics.

- Instantiates the `AVCaptureSession` mapping native inputs seamlessly via `AVCaptureDevice.DiscoverySession`, intelligently prioritizing `.builtInLiDARDepthCamera` for exact physical scale, before safely falling back down through Dual and Wide-Angle matrices for base-model iOS compatibility.
- Configures parallel buffers routing actively to `AVCaptureVideoDataOutput`, `AVCaptureDepthDataOutput`, and importantly `AVCapturePhotoOutput`.
- Throttles preview feeds linearly to conserve internal memory loads gracefully shifting between 15-60 FPS bounds seamlessly.

### `HardwareOrchestrator`

The battery and heat protection protocol monitoring physical usage thresholds gracefully.

- Bridges the Apple internal `.thermalStateDidChangeNotification` explicitly dropping graphic resolutions and Glassmorphism shaders immediately on `.critical` or `.serious`.
- Monitors passive `isLowPowerModeEnabled` strings mapping native 24 FPS `isExpeditionModeActive` pipelines on low-battery wilderness states explicitly.

### `ViewfinderIntelligence` (VUI)

An asynchronous heuristic layer blocking wasted network limits inherently.

- Drops concurrent inference limits natively tracking frame boundaries natively via Core Image `CIAreaAverage` to actively monitor extreme luminance threshold values dynamically.
- Triggers dynamic `VUIHint` prompts across the viewfinder alerting users visually (`"Too dark"`, `"Move closer"`) without executing any internet boundaries gracefully. Explicitly evaluates an optional `distance: Float?` constraint checking for subjects > 2.5 meters.
- Explicitly blocks inference pipelines from querying cloud services for AI evaluation unless the internal brightness buffer returns successfully.
