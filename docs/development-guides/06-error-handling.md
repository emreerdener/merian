# Error Handling Patterns

This document explains the unified `MerianError` taxonomy, how offline fallback works at the network boundary, and how errors surface to the UI.

---

## `MerianError` Taxonomy

`MerianError` conforms to `LocalizedError` and acts as the singular error boundary for the entire application, bridging HTTP limits, missing hardware, and SwiftUI catch blocks.

```swift
public enum MerianError: LocalizedError, Equatable {
    case invalidURL
    case uploadFailed
    case invalidResponse
    case decodingFailed
    case httpError(statusCode: Int, message: String)
    case networkTimeout
    case proRequiredForOfflineTracking
    case hardwareUnavailable
}
```

| Case | Meaning | Caller contract |
|---|---|---|
| `invalidURL` | URL construction failed (programming error) | Log and abort. Do not retry. |
| `uploadFailed` | R2 `PUT` returned non-200. | Retain in queue for recoverable codes (429, 5xx). Tombstone for auth failures (401, 403). |
| `invalidResponse` | HTTP error or auth failure from Edge. | For sync deletions: treat as terminal. For other callers: log and surface a UI error or route to offline queue. |
| `decodingFailed` | `JSONDecoder` failed on a network response. | Refund token, surface "Analysis Failed" graceful degradation result in `InsightSheet`. |
| `networkTimeout` | The network request timed out aggressively. | Surface "Network Timeout / Offline Mode" placeholder + scan queued silently |
| `proRequiredForOfflineTracking` | Free user failed inference with no network | Refund scan token, post `TriggerPaywall` notification. Never enqueue offline. |
| `hardwareUnavailable` | LiDAR or other required physical drivers failed to boot. | Show UI alert explaining hardware constraints. |

---

## Inference Error Routing

`InferenceEngine.analyze` handles errors in this priority order:

1. **`CancellationError`** (or `URLError.cancelled`) — inference was cancelled (user navigated away or backgrounded). Do not refund the scan token. Do not surface any UI. The scan is already durably enqueued in the offline queue (written to disk synchronously in `submitActiveScan` before `analyze()` was called) and will complete via the background URLSession path.
2. **`MerianError.decodingFailed`** — Gemini returned a malformed or unreadable response. Do **not** refund the token — the scan is already in the offline queue and will be retried by the background upload path. Refunding here would give the user a free extra scan against a quota already consumed. Set `speciesData` to an "Analysis Failed" placeholder (`commonName: "Analysis Failed"`, `scientificName: "Data Unreadable"`). Show InsightSheet with degraded result.
3. **All other errors (network failure, timeout, etc.)** — Record circuit failure via `CircuitBreakerManager.shared.recordFailure()`. Set `speciesData` to a "Network Timeout / Offline Mode" placeholder. Do not refund and do not re-enqueue — the scan is already in the offline queue and will be retried by the background upload path.

---

## Offline Fallback Pattern

When a network call fails in `OfflineQueueManager`, the error classification determines queue behavior:

```
Upload (background URLSession upload task)
    ├── File missing (NSURLErrorFileDoesNotExist / CannotOpenFile)
    │   └── tombstone via softDeleteQueuedScan (terminal)
    ├── Transient connectivity error (TimedOut / NetworkConnectionLost /
    │   NotConnectedToInternet / DataNotAllowed / InternationalRoamingOff)
    │   ├── retries < maxUploadRetries (3) → retain in queue, increment uploadRetryCount
    │   └── retries ≥ 3 → tombstone (terminal)
    ├── Other transport error → log, retain in queue
    ├── HTTP 200 → dispatch background inference download task ("inference_{scanId}")
    ├── HTTP 429 / 5xx → retain in queue (recoverable)
    ├── HTTP 401 / 403 → tombstone (auth failure, terminal)
    └── HTTP 4xx (other) → tombstone (terminal)

Inference (background URLSession download task)
    ├── Transport error → handleInferenceRetry: reset to .staged (< maxUploadRetries) or tombstone
    ├── HTTP 200 → processInferenceDownloadResult → persist LocalScanRecord, delete OfflineQueuedScan
    ├── HTTP 4xx → tombstone (permanent failure, terminal)
    └── HTTP 5xx / 429 → handleInferenceRetry: reset to .staged (< maxUploadRetries) or tombstone

Cloud deletion (PendingCloudDeletionTask)
    ├── MerianError.invalidResponse → tombstone (resource already gone, no point retrying)
    └── All other errors → retain in queue
```

Both uploads and inference use the same background `URLSession` (`URLSessionConfiguration.background`) with `sessionSendsLaunchEvents = true`, so iOS can re-attach in-flight tasks on app relaunch and deliver inference results while the app is completely suspended. Upload task descriptions are `"\(scanId)_\(imageIndex)"` and inference task descriptions are `"inference_\(scanId)"` — both are used for deduplication against already-running tasks after a relaunch.

---

## UI Error Surface Patterns

| Error scenario | UI outcome |
|---|---|
| Inference decoding failure (`MerianError.decodingFailed`) | InsightSheet opens with "Analysis Failed" / "Data Unreadable" placeholder result |
| Network timeout (Pro user) | InsightSheet opens with "Network Timeout" / "Offline Mode" placeholder + scan queued silently |
| Network timeout (Free user) | Paywall sheet presented via `TriggerPaywall` notification |
| R2 upload failure (missing source file) | Scan tombstoned silently via `softDeleteQueuedScan`; user is not notified |
| R2 upload — transient error × 3 consecutive failures | Scan tombstoned silently after `maxUploadRetries` exhausted; user is not notified |
| SwiftData save failure during deletion | `.error` logged; file deletion aborted; DB state remains consistent (record still exists, deletion task not persisted) |
| JWT expiry (authenticated OAuth user) | `MerianError.invalidResponse` thrown; callers surface a re-auth prompt |

---

## Handling `401 Unauthorized`

`MerianNetworkClient.performAuthenticatedRequest` intercepts 401 responses:

1. Checks `KeychainManager.shared.bool(forKey: "Merian_HasAuthenticatedOAuth")`.
   - **Authenticated OAuth user** (`hasAuthenticatedOAuth == true`): throws `MerianError.invalidResponse` immediately — the expired JWT must be re-authenticated. No Ghost session overwrite is attempted.
   - **Ghost/anonymous session** (`hasAuthenticatedOAuth == false`): detects a zombie session, calls `SupabaseManager.shared.signOut()` followed by `initializeGhostSession()`, waits 1.5 seconds for the Kong API Gateway to sync the new ES256 signature, then retries the request once with `isRetry: true`.
2. If the retry also fails, throws `MerianError.invalidResponse`.

This logic is centralized in `performAuthenticatedRequest` — callers never need to handle JWT refresh themselves.
