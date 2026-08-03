# Background Inference: Body-Safe Pattern

This document captures the current background inference body contract after the
May 2026 zero-OOM hardening pass.

## Current State

- Images use the staged-R2 path: background `uploadTask(with:fromFile:)` to
  `staging/{userId}/...`, then a tiny inference request carrying `r2ObjectKeys`.
- Queued audio now uses the same staged-R2 upload phase. Audio-bearing
  `OfflineQueuedScan` records enter `.pending`; `MediaStagingContract` builds
  the sanitized filename/object-key manifest, includes `sizeBytes` in the
  `/generate-upload-urls` request, validates byte budgets and audio-file count
  locally and on the Edge before signing, uploads the WAV/M4A file with the
  response-declared signed `Content-Type` and `Content-Length`, persists the
  resulting staging key in
  `stagedR2Keys`, and sends `audioR2ObjectKeys` to `/identify-multimodal`.
- Live foreground audio remains inline as `audioBase64s`, but
  `MerianNetworkClient` preflights file byte size before reading or
  base64-encoding the WAV. Oversized audio fails with
  `MerianError.payloadTooLarge` before any large body is built.
- `identify-multimodal` accepts both inline `audioBase64s` and staged
  `audioR2ObjectKeys`. It validates clip count, base64 length, raw byte length,
  IDOR ownership, and path traversal before decoding or fetching. Staged audio
  is cleaned up after successful ingestion.
- `audio-spec` remains as a compatibility route with matching inline/R2
  byte-budget checks before decode and before/after R2 download. It also writes
  the shared ingestion ledger so staged legacy audio rows can replay through
  `/identify-multimodal`.
- Media-bearing Edge request JSON is parsed with `readRequestJsonWithinBudget`,
  not raw `req.json()`. R2 and HTTP media responses are read with
  `readResponseArrayBufferWithinBudget`. Declared `Content-Length` remains a
  fast reject, but the streaming reader is the authoritative guard for chunked
  or missing-length bodies.

## Why This Is Body-Safe

Queued replay no longer serializes large audio into a background
`URLRequest.httpBody`. The OS background session owns media bytes only through
file-backed R2 upload tasks, while the inference download task carries a small
JSON payload of object keys, telemetry, and observation contexts.

Live audio still uses inline base64 because it is a foreground request and
avoids the extra R2 round trip. The client and edge budget checks keep that path
bounded.

## Source Of Truth

- iOS request builders: `MerianNetworkClient.buildIdentifyRequest(...)`,
  `analyzeSubject(...)`, and `buildMultiModalRequest(...)`, all backed by the
  private `InferencePayloadBuilder` so user context, telemetry formatting,
  observation contexts, and inline media budget checks stay identical across
  `/identify` and `/identify-multimodal`. New scan work should route through
  `/identify-multimodal`; `/identify` is compatibility-only and writes the
  shared ingestion ledger for recovery.
- Upload staging contract: `MediaStagingContract` in `OfflineSyncTypes.swift`
- Cross-language upload manifest contract:
  `docs/contracts/media-staging-upload-manifest.json`
- Upload orchestration:
  `OfflineQueueManager+Sync.prepareUploadItems(from:userId:)`
- Replay dispatcher:
  `OfflineQueueManager+URLSession.dispatchInferenceDownloadTask(...)`
- Shared Edge media budget helpers:
  `services/supabase/functions/_shared/mediaBudgets.ts`
- Edge handler: `services/supabase/functions/identify-multimodal/index.ts`
- Compatibility ledger:
  `services/supabase/functions/_shared/scanIngestionCompatibility.ts`
- Pre-signed URL signing and manifest validation:
  `services/supabase/functions/generate-upload-urls/storage.ts`

## Guardrails

- Do not reintroduce inline audio bodies for queued replay.
- Do not build inference JSON bodies by hand in new call sites. Route
  `/identify` and `/identify-multimodal` request assembly through
  `MerianNetworkClient`'s shared inference payload builder so body-size checks
  happen before large inline base64 payloads are serialized. New scan modes
  should prefer `/identify-multimodal`; compatibility endpoints must use
  `_shared/scanIngestionCompatibility.ts` if they can create a scan row.
- Do not parse media-bearing Edge JSON with raw `req.json()`, and do not call
  `response.arrayBuffer()` on staged media. Use the capped stream helpers from
  `_shared/mediaBudgets.ts` so the 256 MB V8 isolate heap is protected even when
  upstream omits `Content-Length`.
- Keep `audioR2ObjectKeys` separate from image `r2ObjectKeys`; image
  moderation/publication still runs only on visual media.
- Any longer recording mode must lower concurrency or raise budgets deliberately
  on both client and edge. Never let the edge decode base64 before checking
  length.
- R2 staging keys must stay under `staging/{userId}/` and must reject `..` path
  traversal before fetch. Edge code should call `_shared/mediaBudgets.ts` for
  this check instead of duplicating string-prefix logic.
- Queue upload code must not hand-roll `staging/{userId}/...` strings. Use
  `MediaStagingContract` so filename sanitization, task descriptions, budget
  checks, and image/audio key splitting stay in one place.
- Queue upload code must sign and dispatch only scan IDs returned by
  `BackgroundDatabaseActor.markScansAsUploading(scanIds:)`; if the
  `.pending → .uploading` save rolls back, no R2 upload task should be created.
- `/generate-upload-urls` accepts only the structured `files` manifest;
  `fileNames` and missing-size requests fail with `400 size_bytes_required`.
  Entries must validate `mediaKind`, `contentType`, `sizeBytes`, and optional
  `clientScanId`/`mediaRole` before returning a signed PUT URL with exact
  required `Content-Type` and `Content-Length` headers. The signature uses the
  exact `content-length;content-type;host` set. Every iOS data, file, repair,
  restore, avatar, foreground, and background PUT applies the response map; a
  file-backed PUT re-stats immediately before task creation and re-signs when
  size changed. Scan uploads with `clientScanId`/`mediaRole` must create staged
  `scan_media_assets` rows and return optional `mediaAssetId` /
  `mediaSessionId` fields.

## Regression Coverage

- Swift tests cover `buildMultiModalRequestBody` emitting `audioR2ObjectKeys`
  without inline `audioBase64s`, visual inline bodies using the same camelCase
  payload contract, oversized inline image payloads failing before network
  dispatch, and `MerianNetworkClient.validateInlineAudioFileBudget(fileURLs:)`
  rejecting oversized WAV files before `Data(contentsOf:)` or base64 allocation.
- Deno tests cover `_shared/mediaBudgets.ts` directly, including oversized
  chunked streams, capped response streams, valid JSON parsing, and malformed
  JSON rejection, plus endpoint-level uses in `identify-multimodal`,
  `audio-spec`, and `generate-upload-urls`.
- Queue tests assert audio-bearing nonvisual captures enter `.pending` for R2
  staging, while description-only queued captures remain `.staged`.
  `MediaStagingContract` tests cover sanitized mixed-media keys, underscore-safe
  upload task descriptions, and staged-audio byte rejection before upload
  dispatch.
- Capture workspace tests assert offline visual and audio queued-only
  submissions do not call `InferenceEngine.prepareForNewScan()` or open the live
  insight sheet.
- Edge tests mirror the staged-audio budget contract for `identify-multimodal`
  and `audio-spec`: clip count, inline base64 length, missing source, and R2
  path traversal are rejected before decode/fetch.
  `_shared/scanIngestionCompatibility_test.ts` covers staged legacy audio replay
  payloads and inline-media redaction.
