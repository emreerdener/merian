# The Offline Synchronization Pipeline

Merian's core differentiator is treating Off-grid nature encounters as a first-class citizen using native Apple offline architecture.

## How the Queue Works

The `OfflineQueueManager` handles the persistence explicitly with no risk.

1. **Shutter Execution (`OfflineQueueManager.shared.enqueueCapture`)**
   When a hiker takes a picture miles away from a cell tower, the High-Res JPEG is locally written to the iOS `URL.documentsDirectory`. A new `OfflineQueuedScan` database object is written securely into the physical `.modelContainer()` using Apple `SwiftData` and instantly updates the UI badge without touching `URLSession`.

2. **Network Awakening (`NWPathMonitor`)**
   The `NWPathMonitor` instance listens natively to the internal cellular stack continuously. When a connection flips `.satisfied`, the manager debounces for 1,000 milliseconds to guarantee the pipeline has completely stabilized without thrashing before starting processing.

3. **Background Processing (`UIBackgroundTaskIdentifier`)**
   If the app is backgrounded, `OfflineQueueManager` asks the OS for explicitly 30 seconds of extended runtime securely executing `.syncPendingScans()`.

4. **Upload Lifecycle (`processScan`)**
   - **Step A:** Ephemerally pushes the JPEG blindly to Gemini's File API, retrieving a temporary lightweight `uri`.
   - **Step B:** Triggers the Supabase `/identify` Edge function via the native `MerianNetworkClient` validating the model natively.
   - **Step C:** Upon a 200 HTTP OK, fetches a Cloudflare pre-signed link safely and PUTs the actual object successfully.
   - **Step D:** Physically purges the `documentsDirectory` payload freeing storage and safely deletes the item locally inside `SwiftData`.
