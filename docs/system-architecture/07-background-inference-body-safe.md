# Background Inference: Body-Safe Pattern

This document captures the current background inference body contract after the May 2026 zero-OOM hardening pass.

## Current State

- Images use the staged-R2 path: background `uploadTask(with:fromFile:)` to `staging/{userId}/...`, then a tiny inference request carrying `r2ObjectKeys`.
- Queued audio now uses the same staged-R2 upload phase. Audio-bearing `OfflineQueuedScan` records enter `.pending`; `MediaStagingContract` builds the sanitized filename/object-key manifest, includes `sizeBytes` in the `/generate-upload-urls` request, validates byte budgets and audio-file count locally and on the Edge before signing, uploads the WAV/M4A file with the correct signed `Content-Type`, persists the resulting staging key in `stagedR2Keys`, and sends `audioR2ObjectKeys` to `/identify-multimodal`.
- Live foreground audio remains inline as `audioBase64s`, but `MerianNetworkClient` preflights file byte size before reading or base64-encoding the WAV. Oversized audio fails with `MerianError.payloadTooLarge` before any large body is built.
- `identify-multimodal` accepts both inline `audioBase64s` and staged `audioR2ObjectKeys`. It validates clip count, base64 length, raw byte length, IDOR ownership, and path traversal before decoding or fetching. Staged audio is cleaned up after successful ingestion.
- `audio-spec` has matching inline/R2 byte-budget checks before decode and before/after R2 download.

## Why This Is Body-Safe

Queued replay no longer serializes large audio into a background `URLRequest.httpBody`. The OS background session owns media bytes only through file-backed R2 upload tasks, while the inference download task carries a small JSON payload of object keys, telemetry, and observation contexts.

Live audio still uses inline base64 because it is a foreground request and avoids the extra R2 round trip. The client and edge budget checks keep that path bounded.

## Source Of Truth

- iOS request builders: `MerianNetworkClient.buildIdentifyRequest(...)`, `analyzeSubject(...)`, and `buildMultiModalRequest(...)`, all backed by the private `InferencePayloadBuilder` so user context, telemetry formatting, observation contexts, and inline media budget checks stay identical across `/identify` and `/identify-multimodal`.
- Upload staging contract: `MediaStagingContract` in `OfflineSyncTypes.swift`
- Cross-language upload manifest contract: `docs/contracts/media-staging-upload-manifest.json`
- Upload orchestration: `OfflineQueueManager+Sync.prepareUploadItems(from:userId:)`
- Replay dispatcher: `OfflineQueueManager+URLSession.dispatchInferenceDownloadTask(...)`
- Shared Edge media budget helpers: `supabase/functions/_shared/mediaBudgets.ts`
- Edge handler: `supabase/functions/identify-multimodal/index.ts`
- Pre-signed URL signing and manifest validation: `supabase/functions/generate-upload-urls/storage.ts`

## Guardrails

- Do not reintroduce inline audio bodies for queued replay.
- Do not build inference JSON bodies by hand in new call sites. Route `/identify` and `/identify-multimodal` request assembly through `MerianNetworkClient`'s shared inference payload builder so body-size checks happen before large inline base64 payloads are serialized.
- Keep `audioR2ObjectKeys` separate from image `r2ObjectKeys`; image moderation/publication still runs only on visual media.
- Any longer recording mode must lower concurrency or raise budgets deliberately on both client and edge. Never let the edge decode base64 before checking length.
- R2 staging keys must stay under `staging/{userId}/` and must reject `..` path traversal before fetch. Edge code should call `_shared/mediaBudgets.ts` for this check instead of duplicating string-prefix logic.
- Queue upload code must not hand-roll `staging/{userId}/...` strings. Use `MediaStagingContract` so filename sanitization, task descriptions, budget checks, and image/audio key splitting stay in one place.
- `/generate-upload-urls` must prefer the structured `files` manifest over legacy `fileNames`; structured entries must validate `mediaKind`, `contentType`, and `sizeBytes` before returning a signed PUT URL.

## Regression Coverage

- Swift tests cover `buildMultiModalRequestBody` emitting `audioR2ObjectKeys` without inline `audioBase64s`, visual inline bodies using the same camelCase payload contract, oversized inline image payloads failing before network dispatch, and `MerianNetworkClient.validateInlineAudioFileBudget(fileURLs:)` rejecting oversized WAV files before `Data(contentsOf:)` or base64 allocation.
- Deno tests cover `_shared/mediaBudgets.ts` directly, plus endpoint-level uses in `identify-multimodal`, `audio-spec`, and `generate-upload-urls`.
- Queue tests assert audio-bearing nonvisual captures enter `.pending` for R2 staging, while description-only queued captures remain `.staged`. `MediaStagingContract` tests cover sanitized mixed-media keys, underscore-safe upload task descriptions, and staged-audio byte rejection before upload dispatch.
- Capture workspace tests assert offline visual and audio queued-only submissions do not call `InferenceEngine.prepareForNewScan()` or open the live insight sheet.
- Edge tests mirror the staged-audio budget contract for `identify-multimodal` and `audio-spec`: clip count, inline base64 length, missing source, and R2 path traversal are rejected before decode/fetch.
