---
description: Faking Camera Captures on iOS Simulator
---

# 🚀 Merian Simulator Inference Injection

Since the iOS Simulator explicitly lacks a real camera output (returning an opaque or default colored screen), generating true `AVCapturePhoto` objects for Gemini 2.5 is impossible on a standard simulator run. However, debugging the UI layout for the `InsightSheetView` and the asynchronous telemetry pipelines requires a way to force Cache Misses via Edge network routing.

## Step 1: Procuring the Mock Payload
You need a high-quality `.jpg` or `.png` reference image of the species you're testing (e.g. `mock_butterfly.jpg`). It MUST be placed into the Xcode project, typically within the `Assets.xcassets` bundle or dragged directly into the `merian` workspace context.

## Step 2: Modifying CameraManager
Navigate to `merian/Core/Hardware/CameraManager.swift`. We need to intercept the `capturePhoto()` output and artificially substitute the memory buffer with our mock payload before the image lands in the `OfflineQueueManager`.

```swift
func capturePhoto(with settings: AVCapturePhotoSettings, delegate: AVCapturePhotoCaptureDelegate) {
    #if targetEnvironment(simulator)
    // 1. Mock the Capture Buffer
    let mockImage = UIImage(named: "mock_butterfly")!
    let mockData = mockImage.jpegData(compressionQuality: 0.8)!
    
    // 2. Bypass AVFoundation
    // Because we cannot instantiate AVCapturePhoto natively, invoke the InferenceEngine entry delegate directly!
    Task {
        await self.inferenceDelegate?.processSimulatedImage(mockData)
    }
    #else
    self.photoOutput.capturePhoto(with: settings, delegate: delegate)
    #endif
}
```

> [!CAUTION]
> Never commit this specific testing stub to `main`. This is explicitly a diagnostic configuration.

## Step 3: Triggering The Payload
Run the app in the simulator. Tap the main UI Shutter button.
The `inferenceDelegate` will fire the exact same pipeline handling logic as a real photo capture:

1. Writing the exact mock image into `URL.documentsDirectory`.
2. Hashing the image visually.
3. Engaging the `InferenceEngine` to communicate with the Supabase `/identify` Edge function.
4. Parsing the resulting telemetry directly into `SwiftData`.
5. Spawning the `BiologicalView` Insight Sheet.

## Step 4: Edge Case Overrides
Because we bypassed the `AVCapturePhoto` entirely, native hardware telemetry such as `CaptureTelemetry.zoomFactor`, `.subjectDistanceInMeters`, or EXIF `GPSAltitude` will be null or fallback to device defaults. If you need to debug specific UI metrics connected to these properties (e.g. the MapKit location reverse geocoding), manually append static coordinates to the `InferenceEngine` ingestion step!
