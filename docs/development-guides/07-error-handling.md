# Error Handling Patterns

This document explains the `NetworkError` enum cases and the caller contract for each, how offline fallback works at the network boundary, and how errors surface to the UI.

---

## `NetworkError` Cases

```swift
enum NetworkError: Error {
    case invalidURL
    case uploadFailed
    case invalidResponse
    case decodingFailed
}
```

| Case | Meaning | Caller contract |
|---|---|---|
| `invalidURL` | URL construction failed (programming error) | Log and abort. Do not retry. |
| `uploadFailed` | R2 `PUT` returned non-200, or `URLSession` could not cast the response to `HTTPURLResponse` | Retain in offline queue for next connectivity cycle unless HTTP 4xx non-403, in which case tombstone. |
| `invalidResponse` | HTTP error or auth failure from Edge; also used as sentinel when `getValidAuthHeaders()` fails entirely | For sync deletions: treat as terminal (resource is already gone), remove the task. For other callers: log and surface a UI error or route to offline queue. |
| `decodingFailed` | `JSONDecoder` failed on a network response | Log `.error`. Do not retry the same request. For inference: throw `APIError.decodingFailed` which triggers the graceful degradation UI. |

---

## `APIError` Cases

```swift
enum APIError: Error {
    case proRequiredForOfflineTracking
    case decodingFailed
}
```

| Case | Meaning | Caller contract |
|---|---|---|
| `proRequiredForOfflineTracking` | Free user failed inference with no network | Refund scan token, post `TriggerPaywall` notification. Never enqueue offline. |
| `decodingFailed` | Gemini returned a hallucinated or unparseable JSON payload (`DecodingError` from `JSONDecoder`) | Refund scan token, surface "Analysis Failed" graceful degradation result in `InsightSheet`. |

---

## Inference Error Routing

`InferenceEngine.analyze` handles errors in this priority order:

1. **`CancellationError`** (or `URLError.cancelled`) — inference was cancelled (user navigated away, background rescue). Refund scan token via `UsageManager.shared.refundScan()`. Set `isProcessing = false`. Do not surface any UI. If `isBackgroundRescued` is `true`, do not refund (the token was already consumed by the background rescue path).
2. **`APIError.decodingFailed`** — Gemini hallucination. Refund token. Set `speciesData` to an "Analysis Failed" placeholder (`commonName: "Analysis Failed"`, `scientificName: "Data Unreadable"`). Set `isProcessing = false`. Show InsightSheet with degraded result.
3. **Free user + any other error** — Refund token. Post `TriggerPaywall` notification via `NotificationCenter`. Set `isProcessing = false`. Do not enqueue offline.
4. **Pro user + any other error** — Record circuit failure via `CircuitBreakerManager.shared.recordFailure()`. Enqueue to offline queue via `OfflineQueueManager.shared.enqueueCapture`. Set `speciesData` to a "Network Timeout / Offline Mode" placeholder. `isProcessing` is cleared by the unconditional block after the catch.

---

## Offline Fallback Pattern

When a network call fails in `OfflineQueueManager`, the error classification determines queue behavior:

```
Upload (background URLSession task)
    ├── File missing at source path → tombstone via softDeleteQueuedScan (terminal)
    ├── HTTP 200 → proceed; webhook triggers Gemini inference server-side
    └── Non-200 → retain in queue for next connectivity cycle

Cloud deletion (PendingCloudDeletionTask)
    ├── NetworkError.invalidResponse → tombstone (resource already gone, no point retrying)
    └── All other errors → retain in queue
```

Uploads use a background `URLSession` (`URLSessionConfiguration.background`) with `sessionSendsLaunchEvents = true`, so iOS can re-attach in-flight tasks on app relaunch. Task descriptions are set to `"\(scanId)_\(imageIndex)"` to allow deduplication against already-running tasks when `syncPendingScans` is called after a relaunch.

---

## UI Error Surface Patterns

| Error scenario | UI outcome |
|---|---|
| Inference decoding failure (`APIError.decodingFailed`) | InsightSheet opens with "Analysis Failed" / "Data Unreadable" placeholder result |
| Network timeout (Pro user) | InsightSheet opens with "Network Timeout" / "Offline Mode" placeholder + scan queued silently |
| Network timeout (Free user) | Paywall sheet presented via `TriggerPaywall` notification |
| R2 upload failure (missing source file) | Scan tombstoned silently via `softDeleteQueuedScan`; user is not notified |
| SwiftData save failure during deletion | `.error` logged; file deletion aborted; DB state remains consistent (record still exists, deletion task not persisted) |
| JWT expiry (authenticated OAuth user) | `NetworkError.invalidResponse` thrown; callers surface a re-auth prompt |

---

## Handling `401 Unauthorized`

`MerianNetworkClient.performAuthenticatedRequest` intercepts 401 responses:

1. Checks `KeychainManager.shared.bool(forKey: "Merian_HasAuthenticatedOAuth")`.
   - **Authenticated OAuth user** (`hasAuthenticatedOAuth == true`): throws `NetworkError.invalidResponse` immediately — the expired JWT must be re-authenticated. No Ghost session overwrite is attempted.
   - **Ghost/anonymous session** (`hasAuthenticatedOAuth == false`): detects a zombie session, calls `SupabaseManager.shared.signOut()` followed by `initializeGhostSession()`, waits 1.5 seconds for the Kong API Gateway to sync the new ES256 signature, then retries the request once with `isRetry: true`.
2. If the retry also fails, throws `NetworkError.invalidResponse`.

This logic is centralized in `performAuthenticatedRequest` — callers never need to handle JWT refresh themselves.
