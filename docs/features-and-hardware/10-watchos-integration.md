# watchOS Integration

Naturebook ships a companion watchOS target (`apps/watch/MerianWatch/`) that captures acoustic data from the Apple Watch microphone and delivers it to the iOS app for server-side identification.

> **Status**: The watchOS capture pipeline is fully implemented. The iOS `WCSessionDelegate` receiver is not yet implemented — payloads dispatched from the watch are not currently handled on the iPhone side. This document reflects the current code state.

## Architecture

```
[Apple Watch]
    │
    │  AVAudioRecorder (15s AAC window)
    │  + CoreLocation (GPS)
    │  + WeatherKit (conditions)
    │
    ▼
[WatchAcousticManager]
    │
    ├─ WCSession.sendMessage (foreground — immediate delivery)
    └─ WCSession.transferUserInfo (background — queued delivery)
            │
            ▼
    [iPhone OfflineQueueManager]  ← NOT YET IMPLEMENTED
            │
            ▼
    [/identify-multimodal Edge Function]
```

## `WatchAcousticManager`

`WatchAcousticManager` is a `@MainActor ObservableObject` declared in `apps/watch/MerianWatch/WatchAcousticManager.swift`. It is the sole business logic class in the watchOS target, injected into `ContentView` as an `@EnvironmentObject`.

### Responsibilities

- Requests microphone and location permissions on init
- Manages `AVAudioSession` lifecycle (category: `.record`, mode: `.measurement`)
- Captures a 15-second M4A audio window via `AVAudioRecorder`
- Fetches a single GPS fix from `CLLocationManager` (stops immediately after first update to conserve battery)
- Assembles an identification payload with audio + GPS + weather + locale context
- Delivers the payload to the iOS app via `WatchConnectivity`
- **Purges the temporary `.m4a` file from watchOS storage immediately after encoding** — prevents storage bloat on constrained watch storage

### Published State

| Property | Type | Meaning |
|---|---|---|
| `isRecording` | `Bool` | `true` while the 15-second audio window is open |
| `isProcessing` | `Bool` | `true` while encoding and dispatching the payload |
| `authorizationState` | `CLAuthorizationStatus` | Current location permission status |

### Capture Flow

1. `startAcousticCapture()` is called from the UI tap
2. `AVAudioSession` is configured and `AVAudioRecorder.record(forDuration: 15.0)` begins
3. `WKInterfaceDevice.current().play(.start)` provides haptic feedback
4. After 15 seconds, `audioRecorderDidFinishRecording` fires on the delegate
5. `WKInterfaceDevice.current().play(.success)` signals completion
6. `processPayload(fileURL:)` encodes the audio as base64 and dispatches via WatchConnectivity
7. The `.m4a` temp file is deleted inside a `defer` block regardless of dispatch success

## Payload Schema

The payload delivered to the iPhone via `WCSession` is a watch handoff envelope. It is not yet consumed by iOS, and the eventual receiver should translate it into Merian's current non-visual `/identify-multimodal` request shape:

```json
{
  "audioData": "<base64-encoded M4A watch recording>",
  "currentMonth": 4,
  "deviceLocale": "en_US",
  "gpsLatitude": 37.7749,
  "gpsLongitude": -122.4194,
  "gpsElevation": 42.5,
  "weatherCondition": "Clear",
  "weatherTemperatureF": 68.2
}
```

`gpsLatitude`, `gpsLongitude`, `gpsElevation` are included only when a location fix was obtained. `weatherCondition` and `weatherTemperatureF` are included only when `WeatherKit` returned a result.

## WatchConnectivity Delivery

`WatchAcousticManager` uses a two-tier delivery strategy:

**Foreground (preferred):**
```swift
session.sendMessage(payload, replyHandler: nil) { error in
    // Falls back to background on failure
    self.session?.transferUserInfo(payload)
}
```

**Background (fallback):**
`transferUserInfo` queues the payload for delivery the next time the iPhone app is reachable. This is the path used when the iPhone is locked, out of Bluetooth range, or the Merian app is not running.

## iOS Receiver (Not Yet Implemented)

The iPhone side requires a `WCSessionDelegate` that:
1. Implements `session(_:didReceiveMessage:)` for foreground payloads
2. Implements `session(_:didReceiveUserInfo:)` for background-queued payloads
3. Converts or transcodes the watch `.m4a` handoff into the supported non-visual audio flow
4. Forwards the payload into `OfflineQueueManager` as an acoustic identification job routed through `/identify-multimodal`

Until this is implemented, payloads from the watch are silently dropped on the iOS side. The watch capture and dispatch pipeline is fully functional — the work remaining is entirely on the iOS receiver.

## Platform Constraints

- **Storage**: The temporary `.m4a` recording buffer is written to `FileManager.default.temporaryDirectory` and deleted immediately after base64 encoding. watchOS temporary storage is not cleared automatically between sessions.
- **Battery**: `CLLocationManager.stopUpdatingLocation()` is called immediately after the first GPS fix to prevent the location radio from running during the full recording window.
- **Session**: `WCSession` is activated in `init()` and reused for the lifetime of the `WatchAcousticManager` instance.
- **Audio quality**: 44.1 kHz, mono, AAC High quality — sufficient for species-level acoustic identification.
