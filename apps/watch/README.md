# Naturebook Watch

The watchOS companion app for Naturebook. Its technical target remains
`MerianWatch`.

This target (`MerianWatch`) is built for watchOS 10.0+ and focuses on acoustic capture. It allows users to record audio directly from their Apple Watch and securely dispatch it to the iOS app for identification.

## Architecture

- **Acoustic Capture**: The watch app captures audio and encodes it to base64 via `WatchAcousticManager`.
- **WatchConnectivity**: The encoded audio payload is dispatched to the iOS counterpart via `WCSession`. 
- **No Direct Network Calls**: The watchOS app does **not** perform independent inferences or direct network calls to Supabase or Gemini. It acts purely as a capture surface, delegating network operations and offline queuing to the iOS host.
- **Storage Management**: The temporary `.m4a` recording buffer is written to `FileManager.default.temporaryDirectory` and purged immediately after base64 encoding and dispatch to prevent watchOS storage bloat.

## Development

The watch app is located in `apps/watch/MerianWatch/`.
It relies on the `MerianWatch` target in `project.yml`. Be sure to regenerate the project with `xcodegen` if modifying targets or schemes.

*Note: The iOS `WCSessionDelegate` receiver must be implemented to ingest payloads dispatched from the watch into the iPhone's offline queue.*
